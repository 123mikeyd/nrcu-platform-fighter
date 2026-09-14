extends Control
# NRCU Results — winner-first payoff screen (Doc 06, WP-E; corrective WP-5).
#
# Pure presentation/navigation over an explicit MatchResult snapshot: the
# screen sorts by `placement`, resolves the winner model from `fighter_id`,
# and never infers rank from stats (Doc 06 §3/§21). Every decision the screen
# makes is bound to the lane/wp5-resolution data contract and NOT re-derived
# here (Doc 06 §4 "Results does not derive match truth"):
#   * FFA standings order = `placement`, ties broken by station order only —
#     the shared ranks the resolver produced are displayed as-is;
#   * team standings = `team_standings()` groups: a shared-rank group header
#     ("1ST · TEAM A", Doc 01 §12) followed by its member rows; teammates are
#     never ranked against each other;
#   * `eliminated` is read from the snapshot (never inferred from stocks) and
#     an OUT entry shows OUT with no damage field (Doc 06 §4);
#   * the hero group is `winning_entries()` — TEAM mode renders EVERY member of
#     the winning team, including one eliminated before match end;
#   * DRAW: no winner hero at all, entries exactly as supplied.
#
# Composition at 1280x720 inside a centered ReferenceFrame (Doc 06 §6):
#   Top outcome header  y ~26-112   WINNER / P2 DOGE MAN or TEAM A / rule
#   Main payoff         y ~110-510  winner hero | final standings
#   Action bar          y ~585-670  Rematch / Change Fighters / [Stage] / Main Menu
# Team mode: the hero field is a WIDE group field whose aspect IS the winning
# group's measured field (Doc 06 §7 — never composed 2:1 and cropped into
# 1.1:1), and each winning fighter keeps its own resolved palette variant
# (Doc 06 §10 — independently paletted subjects).
# No StatPanel, no page navigation, no duplicate player inspector.
#
# Reveal (Doc 06 §16, tick-driven on FrontendClock):
#   0-6f field, 4-18f outcome+hero, 12-30f standings with a 3-tick row
#   stagger, 26-40f action bar -> full useful screen by ~0.65 s. A fresh
#   confirm after the safety window finishes the reveal immediately and is
#   consumed in `_input`, before the GUI stage, so one event can never both
#   finish the reveal and activate an action (RESULT_REVEAL_GUARD).

signal rematch_requested
signal setup_requested
signal menu_requested
signal stage_requested

const Tokens = preload("res://scripts/ui_tokens.gd")
const MatchResultScript = preload("res://scripts/match_result.gd")
const Factory = preload("res://scripts/frontend/fighter_presentation_factory.gd")
const FighterRenderViewScript = preload("res://scripts/frontend/fighter_render_view.gd")
const Roster = preload("res://scripts/roster.gd")
const ResultRowScene = preload("res://scenes/components/ResultRow.tscn")
const ActionBarScene = preload("res://scenes/components/ActionBar.tscn")
# Doc 03 §6/§13: authored anchors + explicit topology + recovery.
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")

const FPS := 60.0

# --- layout (1280x720 reference frame) ------------------------------------
const LEAD_X := 64.0
const EYEBROW_Y := 26.0
const OUTCOME_Y := 44.0
const RULE_Y := 108.0
const HERO_X := 64.0
const HERO_Y := 125.0
const HERO_W := 436.0
const HERO_H := 395.0
const FIELD_PAD_X := 16.0
const FIELD_PAD_Y := 8.0
const STAND_X := 544.0
const STAND_W := 680.0
const STAND_HEAD_Y := 130.0
const STAND_RULE_Y := 152.0
const ROW_Y0 := 170.0
const ROW_STRIDE := 86.0
const ROW_H := 78.0
# Team standings (Doc 01 §12): a shared-rank group header, then its members.
# Two team groups of two are 6 rows: 2 headers + 4 member rows.
const FFA_ROWS := 4
const MAX_ROWS := 6
const TEAM_HEADER_H := 30.0
const TEAM_MEMBER_H := 60.0
const TEAM_GROUP_GAP := 10.0
# The team hero field (Doc 06 §7): wide enough for the measured group field,
# bounded by the standings column and the authored main-payoff band.
const TEAM_HERO_W := 456.0
const TEAM_HERO_MIN_H := 190.0
const ACTION_Y := 585.0
const MENU_X := 680.0
const MENU_X_TIGHT := 456.0   # Main Menu slides up when Change Stage is absent

# --- reveal timeline (ticks at 60 Hz, Doc 06 §16) --------------------------
const SAFETY_TICKS := 6       # carry-over window before input may finish the reveal
const TL_FIELD := 2           # 0-6f: result field tint resolves
const TL_OUTCOME := 4         # 4-18f: outcome + winner hero resolve
const TL_ROWS := 12           # 12-30f: standings enter, 3-tick stagger
const TL_ROW_STAGGER := 3
const TL_ACTIONS := 26        # 26-40f: action bar resolves
const TL_DONE := 40           # full useful screen; actions interactive
const OUTCOME_POP := 14.0 / FPS
const HERO_SETTLE := 16.0 / FPS
const ROW_REVEAL := 10.0 / FPS
const BAR_REVEAL := 12.0 / FPS
const FIELD_REVEAL := 8.0 / FPS

const ACTIONS := [
    {"node": "Rematch", "id": "rematch", "primary": true},
    {"node": "ChangeFighters", "id": "setup", "primary": false},
    {"node": "ChangeStage", "id": "stage", "primary": false},
    {"node": "MainMenu", "id": "menu", "primary": false},
]

# Winner heading label for main.gd's HUD wiring (read-only for callers).
var outcome_label: Label = null

var _result = null                 # MatchResult snapshot; null before first show
var _cursor: Control = null
var _clock: Node = null

var _eyebrow: Label
var _screen_label: Label
var _outcome_rule: Panel
var _rule_w := 360.0
var _accent := Tokens.CREAM_DIM
var _hero_field: Panel
var _hero_tint: Panel
var _hero_accent: Panel
var _hero_group: Control
var _hero_text: Label
var _hero_views: Array = []
var _hero_ids: Array = []
var _hero_rect := Rect2(HERO_X, HERO_Y, HERO_W, HERO_H)
var _standings_label: Label
var _standings_rule: Panel
var _standings_list: Control
var _rows: Array = []
var _action_bar: Control
var _actions: Dictionary = {}
var _row_entries: Array = []
var _row_kinds: Array = []
var _row_y: Array = []
var _row_count := 0

var _reveal_active := false
var _reveal_tick := 0
var _reveal_events := 0
var _field_shown := false
var _outcome_shown := false
var _rows_shown := 0
var _actions_shown := false
var _interactive := false
var _tweens: Array = []
var _focus_action := ""
var _hover_action := ""
var _stage_supported := false
var _reveal_acc := 0.0

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    theme = Tokens.make_theme()
    var root = get_node_or_null("/root/Cursor")
    if root != null:
        _cursor = root.hand
    if _cursor != null and _cursor.has_signal("modality_changed") and not _cursor.modality_changed.is_connected(_on_cursor_modality):
        _cursor.modality_changed.connect(_on_cursor_modality)
    _clock = get_node_or_null("/root/FrontendClock")
    if _clock != null and _clock.has_signal("tick"):
        _clock.tick.connect(_on_tick)
        set_process(false)
    else:
        set_process(true)   # defensive: run the timeline off _process at 60 Hz
    # §7: the reveal guard is answered on the semantic confirm path, not by
    # decoding raw device events here.
    FrontendInput.set_confirm_consumer(_consume_semantic_confirm)
    var frame := Tokens.make_reference_frame(self)
    _build_header(frame)
    _build_hero(frame)
    _build_standings(frame)
    _build_actions(frame)
    _reset_for_show()

# --- construction ----------------------------------------------------------

func _build_header(frame: Control) -> void:
    var header := Control.new()
    header.name = "OutcomeHeader"
    header.mouse_filter = Control.MOUSE_FILTER_IGNORE
    frame.add_child(header)
    _eyebrow = _label(header, "WINNER", Tokens.T_META, Tokens.ACCENT, Rect2(LEAD_X, EYEBROW_Y, 220.0, 18.0))
    _eyebrow.name = "OutcomeEyebrow"
    outcome_label = _label(header, "", Tokens.T_DISPLAY, Tokens.CREAM, Rect2(LEAD_X, OUTCOME_Y, 900.0, 62.0))
    outcome_label.name = "OutcomeText"
    _screen_label = _label(header, "RESULTS", Tokens.T_META, Tokens.CREAM_DIM,
        Rect2(Tokens.DESIGN.x - Tokens.MARGIN_RIGHT - 160.0, 30.0, 160.0, 18.0), HORIZONTAL_ALIGNMENT_RIGHT)
    _screen_label.name = "ScreenLabel"
    _outcome_rule = Tokens.band(_accent, 3.0)
    _outcome_rule.name = "OutcomeRule"
    _outcome_rule.position = Vector2(LEAD_X, RULE_Y)
    _outcome_rule.size = Vector2(_rule_w, 3.0)
    header.add_child(_outcome_rule)

func _build_hero(frame: Control) -> void:
    var main_result := Control.new()
    main_result.name = "MainResult"
    main_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
    frame.add_child(main_result)
    var area := Control.new()
    area.name = "WinnerHeroArea"
    area.mouse_filter = Control.MOUSE_FILTER_IGNORE
    main_result.add_child(area)
    var field_rect := Rect2(HERO_X - FIELD_PAD_X, HERO_Y - FIELD_PAD_Y, HERO_W + FIELD_PAD_X * 2.0, HERO_H + FIELD_PAD_Y * 2.0)
    _hero_field = _plate(area, field_rect, Tokens.SURFACE_1, Tokens.RADIUS_FLAT)
    _hero_field.name = "HeroField"
    _hero_tint = _plate(area, field_rect, Color(0, 0, 0, 0), Tokens.RADIUS_FLAT)
    _hero_tint.name = "WinnerTint"
    _hero_accent = _plate(area, Rect2(HERO_X + 8.0, field_rect.position.y + field_rect.size.y - 26.0, 120.0, 3.0), _accent, Tokens.RADIUS_FLAT)
    _hero_accent.name = "PlayerAccent"
    _hero_text = _label(area, "", Tokens.T_HERO, Tokens.CREAM, Rect2(HERO_X, HERO_Y + 130.0, HERO_W, 90.0), HORIZONTAL_ALIGNMENT_CENTER)
    _hero_text.name = "HeroText"
    _hero_text.hide()
    _hero_group = Control.new()
    _hero_group.name = "WinnerHeroGroup"
    _hero_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hero_group.position = Vector2(HERO_X, HERO_Y)
    _hero_group.size = Vector2(HERO_W, HERO_H)
    _hero_group.pivot_offset = Vector2(HERO_W * 0.5, HERO_H)
    area.add_child(_hero_group)

func _build_standings(frame: Control) -> void:
    var main_result := frame.get_node("MainResult")
    var standings := Control.new()
    standings.name = "Standings"
    standings.mouse_filter = Control.MOUSE_FILTER_IGNORE
    main_result.add_child(standings)
    _standings_label = _label(standings, "FINAL STANDINGS", Tokens.T_META, Tokens.CREAM_DIM, Rect2(STAND_X, STAND_HEAD_Y, 320.0, 18.0))
    _standings_label.name = "StandingsLabel"
    _standings_rule = Tokens.band(Tokens.RULE, 1.0)
    _standings_rule.name = "StandingsRule"
    _standings_rule.position = Vector2(STAND_X, STAND_RULE_Y)
    _standings_rule.size = Vector2(STAND_W, 1.0)
    standings.add_child(_standings_rule)
    _standings_list = Control.new()
    _standings_list.name = "StandingsList"
    _standings_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _standings_list.position = Vector2(STAND_X, ROW_Y0)
    _standings_list.size = Vector2(STAND_W, ROW_STRIDE * FFA_ROWS)
    standings.add_child(_standings_list)
    for i in MAX_ROWS:
        # Rows are Controls, not Buttons: nothing here performs an action
        # (Doc 06 §11).
        var row: Control = ResultRowScene.instantiate()
        row.name = "ResultRow%d" % i
        row.position = Vector2(0.0, i * ROW_STRIDE)
        row.visible = false
        _standings_list.add_child(row)
        _rows.append(row)

func _build_actions(frame: Control) -> void:
    _action_bar = ActionBarScene.instantiate()
    _action_bar.position = Vector2(Tokens.MARGIN, ACTION_Y)
    frame.add_child(_action_bar)
    for spec in ACTIONS:
        var button: Button = _action_bar.get_node(str(spec["node"]))
        var underline: Panel = button.get_node("Underline")
        var anchor: Control = button.get_node("CursorAnchor")
        Tokens.apply_styles(button, {
            "normal": Tokens.flat(Color(0, 0, 0, 0)),
            "hover": Tokens.flat(Color(1, 1, 1, 0.05)),
            "pressed": Tokens.flat(Color(1, 1, 1, 0.09)),
            "disabled": Tokens.flat(Color(0, 0, 0, 0)),
            "focus": Tokens.flat(Color(0, 0, 0, 0)),
        })
        button.add_theme_font_size_override("font_size", Tokens.T_ACTION)
        var id := str(spec["id"])
        button.focus_entered.connect(_on_action_focus.bind(id, true))
        button.focus_exited.connect(_on_action_focus.bind(id, false))
        button.mouse_entered.connect(_on_action_hover.bind(id, true))
        button.mouse_exited.connect(_on_action_hover.bind(id, false))
        button.pressed.connect(_on_action_pressed.bind(id))
        _actions[id] = {"button": button, "underline": underline, "anchor": anchor, "primary": bool(spec["primary"])}

# --- presentation application ---------------------------------------------

func show_result(result, allow_stage_change := false) -> void:
    _result = result
    _stage_supported = allow_stage_change
    _reveal_active = true
    _reveal_tick = 0
    _reveal_events = 0
    _field_shown = false
    _outcome_shown = false
    _rows_shown = 0
    _actions_shown = false
    _interactive = false
    _focus_action = ""
    _hover_action = ""
    _apply_outcome()
    _apply_rows()
    _apply_actions()
    _apply_hero()
    _cursor_entry()
    _reset_for_show()

func _apply_outcome() -> void:
    var heading := "DRAW"
    var eyebrow := ""
    _accent = Tokens.CREAM_DIM
    var rule_len := 148.0
    if _result != null and str(_result.outcome) == MatchResultScript.OUTCOME_WIN:
        eyebrow = "WINNER"
        if bool(_result.team_mode) and int(_result.winning_team) >= 0:
            var team := int(_result.winning_team)
            # Doc 01 §12 / the WP-5 schematic: "WINNER" above "TEAM A" — the
            # eyebrow already states the outcome, so a second WINS! is
            # redundant (Doc 06 §6 "no tiny redundant information").
            heading = _team_name(team)
            _accent = _team_color(team)
        else:
            var winner: Dictionary = _result.winner_entry()
            if not winner.is_empty():
                heading = "P%d %s" % [int(winner["player_index"]), str(winner["fighter_name"])]
                _accent = _player_color(int(winner["player_index"]))
            else:
                # Malformed payload (WIN without a winner entry): state the
                # outcome, never invent an identity or a fake placement.
                heading = "WIN"
                eyebrow = ""
    outcome_label.text = heading
    outcome_label.visible = true
    _eyebrow.text = eyebrow
    _eyebrow.visible = eyebrow != ""
    _eyebrow.add_theme_color_override("font_color", Tokens.ACCENT)
    _outcome_rule.add_theme_stylebox_override("panel", Tokens.flat(_accent))
    _hero_tint.add_theme_stylebox_override("panel", Tokens.flat(Color(_accent.r, _accent.g, _accent.b, 0.10)))
    _hero_accent.add_theme_stylebox_override("panel", Tokens.flat(_accent))
    _rule_w = clampf(_measure(outcome_label), 96.0, 640.0) if eyebrow != "" else rule_len
    _outcome_rule.size = Vector2(_rule_w, 3.0)

func _apply_rows() -> void:
    # The standings are PLANNED first (kind + data per row), then shaped and
    # filled. FFA: `placement` order over the snapshot entries — a shared rank
    # orders by station only and is never re-ranked. Team: `team_standings()`
    # groups — one shared-rank group header per team, then its member rows
    # (Doc 01 §12, Doc 06 §3).
    _row_entries = []
    _row_kinds = []
    _row_y = []
    if _result != null:
        if bool(_result.team_mode):
            _plan_team_rows()
        else:
            _plan_ffa_rows()
    _row_count = mini(_row_entries.size(), MAX_ROWS)
    _plan_row_geometry()
    for i in _rows.size():
        var row: Control = _rows[i]
        if i >= _row_count:
            row.visible = false
            continue
        _fill_row(row, i)

func _plan_ffa_rows() -> void:
    var ordered: Array = _result.entries.duplicate()
    ordered.sort_custom(_placement_order)
    for entry in ordered:
        _row_entries.append(entry)
        _row_kinds.append("player")

func _plan_team_rows() -> void:
    for group in _result.team_standings():
        _row_entries.append(group)
        _row_kinds.append("team_header")
        for entry in group["entries"]:
            _row_entries.append(entry)
            _row_kinds.append("team_member")

func _placement_order(a: Dictionary, b: Dictionary) -> bool:
    # Explicit placement first (owned by match resolution); inside a shared
    # rank the station order only ORDERS the display — it never re-ranks
    # anybody (Doc 06 §2 "do not invent unique placement").
    if int(a["placement"]) != int(b["placement"]):
        return int(a["placement"]) < int(b["placement"])
    return int(a["player_index"]) < int(b["player_index"])

func _plan_row_geometry() -> void:
    # Row offsets are measured in the same units for both compositions, so the
    # reveal stagger and every read surface stay index-based.
    var y := 0.0
    for i in _row_count:
        var kind := str(_row_kinds[i])
        if kind == "team_header":
            if i > 0:
                y += TEAM_GROUP_GAP
            _row_y.append(y)
            y += TEAM_HEADER_H
        elif kind == "team_member":
            _row_y.append(y)
            y += TEAM_MEMBER_H
        else:
            _row_y.append(y)
            y += ROW_STRIDE

func _fill_row(row: Control, index: int) -> void:
    _shape_row(row, str(_row_kinds[index]))
    row.position.y = float(_row_y[index])
    if str(_row_kinds[index]) == "team_header":
        _fill_team_header(row, _row_entries[index])
    else:
        _fill_player_row(row, _row_entries[index], str(_row_kinds[index]) == "team_member")

func _row_offset(index: int) -> float:
    if index >= 0 and index < _row_y.size():
        return float(_row_y[index])
    return 0.0

func _shape_row(row: Control, kind: String) -> void:
    # One component, three authored shapes: the FFA player row (78px), the team
    # group header band (30px) and the compact team member row (60px).
    var plate: Panel = row.get_node("Plate")
    var side: Panel = row.get_node("Side")
    var rank: Label = row.get_node("Rank")
    var port: Label = row.get_node("Port")
    var name_label: Label = row.get_node("Name")
    var stocks: Label = row.get_node("Stocks")
    var damage: Label = row.get_node("Damage")
    rank.visible = true
    port.visible = true
    name_label.visible = true
    stocks.visible = true
    damage.visible = true
    if kind == "team_header":
        row.size = Vector2(STAND_W, TEAM_HEADER_H)
        plate.size = Vector2(STAND_W, TEAM_HEADER_H)
        side.position = Vector2.ZERO
        side.size = Vector2(4.0, TEAM_HEADER_H)
        rank.position = Vector2(24.0, 0.0)
        rank.size = Vector2(STAND_W - 48.0, TEAM_HEADER_H)
        port.visible = false
        name_label.visible = false
        stocks.visible = false
        damage.visible = false
        return
    if kind == "team_member":
        row.size = Vector2(STAND_W, TEAM_MEMBER_H)
        plate.size = Vector2(STAND_W, TEAM_MEMBER_H)
        side.position = Vector2(0.0, 8.0)
        side.size = Vector2(4.0, TEAM_MEMBER_H - 16.0)
        rank.visible = false            # the rank lives on the group header
        port.position = Vector2(24.0, 8.0)
        port.size = Vector2(84.0, 28.0)
        name_label.position = Vector2(120.0, 8.0)
        name_label.size = Vector2(310.0, TEAM_MEMBER_H - 16.0)
        stocks.position = Vector2(434.0, 6.0)
        stocks.size = Vector2(222.0, 24.0)
        damage.position = Vector2(434.0, 32.0)
        damage.size = Vector2(222.0, 24.0)
        return
    row.size = Vector2(STAND_W, ROW_H)
    plate.size = Vector2(STAND_W, ROW_H)
    side.position = Vector2(0.0, 10.0)
    side.size = Vector2(4.0, ROW_H - 20.0)
    rank.position = Vector2(24.0, 12.0)
    rank.size = Vector2(84.0, 30.0)
    port.position = Vector2(24.0, 44.0)
    port.size = Vector2(84.0, 20.0)
    name_label.position = Vector2(120.0, 12.0)
    name_label.size = Vector2(310.0, 54.0)
    stocks.position = Vector2(434.0, 10.0)
    stocks.size = Vector2(222.0, 24.0)
    damage.position = Vector2(434.0, 44.0)
    damage.size = Vector2(222.0, 24.0)

func _fill_team_header(row: Control, group: Dictionary) -> void:
    # The shared team rank (Doc 01 §12 "1ST · TEAM A"): ONE line carrying the
    # rank the whole group shares and the team it belongs to. Members below
    # deliberately carry no rank of their own — teammates are never ranked
    # against each other (Doc 06 §3).
    var place := int(group.get("placement", MatchResultScript.NO_PLACEMENT))
    var team_id := int(group.get("team_id", MatchResultScript.NO_TEAM))
    var color := _team_color(team_id)
    var plate: Panel = row.get_node("Plate")
    plate.add_theme_stylebox_override("panel", Tokens.flat(Color(0, 0, 0, 0), Tokens.RULE, Tokens.STROKE))
    var side: Panel = row.get_node("Side")
    side.add_theme_stylebox_override("panel", Tokens.flat(color))
    var rank: Label = row.get_node("Rank")
    rank.text = "%s · %s" % [_placement_text(place), _team_name(team_id)]
    rank.add_theme_color_override("font_color", color)
    rank.add_theme_font_size_override("font_size", Tokens.T_META)

func _fill_player_row(row: Control, entry: Dictionary, is_member: bool) -> void:
    # Every value displayed here is snapshot data. `eliminated` is the explicit
    # field (Doc 06 §4) — it is never re-derived from stocks, and an eliminated
    # entry shows OUT with NO damage field, because lose_stock() resets the
    # damage the match is over (Doc 06 §4).
    var stocks_remaining := int(entry.get("stocks_remaining", 0))
    var eliminated: bool = bool(entry.get("eliminated", stocks_remaining <= 0))
    var is_winner: bool = bool(entry.get("is_winner", false))
    var player_index := int(entry.get("player_index", 0))
    var color := _player_color(player_index)
    var plate: Panel = row.get_node("Plate")
    plate.add_theme_stylebox_override("panel", Tokens.flat(
        Tokens.SURFACE_HI if is_winner else Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE))
    var side: Panel = row.get_node("Side")
    side.add_theme_stylebox_override("panel", Tokens.flat(color))
    var rank: Label = row.get_node("Rank")
    rank.text = _placement_text(int(entry.get("placement", 0)))
    rank.add_theme_color_override("font_color", Tokens.CREAM_DIM if eliminated else Tokens.CREAM)
    rank.add_theme_font_size_override("font_size", Tokens.T_NAV)
    var port: Label = row.get_node("Port")
    port.text = "P%d" % player_index
    port.add_theme_color_override("font_color", color)
    port.add_theme_font_size_override("font_size", Tokens.T_META)
    var name_label: Label = row.get_node("Name")
    name_label.text = str(entry.get("fighter_name", ""))
    name_label.add_theme_color_override("font_color", Tokens.CREAM)
    name_label.add_theme_font_size_override("font_size", Tokens.T_NAV)
    var stocks_label: Label = row.get_node("Stocks")
    stocks_label.text = "OUT" if eliminated else "STOCKS %d" % stocks_remaining
    stocks_label.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    stocks_label.add_theme_font_size_override("font_size", Tokens.T_META)
    # An OUT row centres its single state line in the row band.
    stocks_label.position.y = (row.size.y - 24.0) * 0.5 if eliminated else stocks_label.position.y
    var damage_label: Label = row.get_node("Damage")
    damage_label.visible = not eliminated
    damage_label.text = "" if eliminated else "%d%%" % int(entry.get("damage_percent", 0))
    damage_label.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    damage_label.add_theme_font_size_override("font_size", Tokens.T_META)

func _apply_actions() -> void:
    _actions["stage"]["button"].visible = _stage_supported
    _actions["menu"]["button"].position.x = MENU_X if _stage_supported else MENU_X_TIGHT
    for id in _actions:
        var spec: Dictionary = _actions[id]
        spec["underline"].visible = false
        var button: Button = spec["button"]
        button.add_theme_color_override("font_color", Tokens.CREAM if bool(spec["primary"]) else Tokens.CREAM_DIM)
    _wire_action_graph()
    _ensure_focus_alive()

func _wire_action_graph() -> void:
    # Doc 03 §13: REMATCH <-> CHANGE FIGHTERS <-> CHANGE STAGE <-> MAIN MENU,
    # explicitly wired, NO wrap. When CHANGE STAGE is absent (the stage is not
    # swappable in this match) the chain simply closes up around it, and a
    # hidden or disabled action is not focusable at all.
    var chain: Array = []
    for spec in ACTIONS:
        var id := str(spec["id"])
        if not _actions.has(id):
            continue
        var button: Button = _actions[id]["button"]
        var reachable: bool = button.visible and not button.disabled
        button.focus_mode = Control.FOCUS_ALL if reachable else Control.FOCUS_NONE
        FocusGraph.clear(button, [&"top", &"bottom", &"left", &"right"])
        if reachable:
            chain.append(button)
    FocusGraph.chain(chain, false)
    for i in chain.size():
        var button: Button = chain[i]
        if i > 0:
            FocusGraph.wire(button, chain[i - 1], [&"left"])
        if i + 1 < chain.size():
            FocusGraph.wire(button, chain[i + 1], [&"right"])

func action_chain() -> Array:
    # The surviving action chain in authored order (read surface for the
    # traversal manifest and the route tests).
    var out: Array = []
    for spec in ACTIONS:
        var id := str(spec["id"])
        if not _actions.has(id):
            continue
        var button: Button = _actions[id]["button"]
        if button.visible and button.focus_mode != Control.FOCUS_NONE:
            out.append(button)
    return out

func focus_anchor_for(control: Control) -> Control:
    # The authored hand target of a focusable control on this screen (Doc 03 §6).
    for id in _actions:
        if _actions[id]["button"] == control:
            return _actions[id]["anchor"]
    return FocusGraph.anchor_of(control)

func _ensure_focus_alive() -> void:
    # §6: Change Stage may disappear (or every action may be disabled during the
    # reveal); focus must move to the surviving semantic neighbour at once.
    if not is_inside_tree():
        return
    var before := FrontendInput.focus_owner()
    var owner := FocusGraph.recover(get_viewport(), self, func() -> Control:
        var chain := action_chain()
        return chain[0] if not chain.is_empty() else null)
    if owner != null and owner != before and _cursor != null and _cursor.mode == 1:
        var anchor := focus_anchor_for(owner)
        if anchor != null:
            _cursor.set_focus_target(anchor)

func _apply_hero() -> void:
    for view in _hero_views:
        if is_instance_valid(view):
            # Detach now so a re-show never leaves two render views in the
            # tree for a frame (counts and hit-free overlays stay exact).
            _hero_group.remove_child(view)
            view.queue_free()
    _hero_views.clear()
    _hero_ids = []
    _hero_text.hide()
    _hero_rect = Rect2(HERO_X, HERO_Y, HERO_W, HERO_H)
    _set_hero_frame(_hero_rect)
    if _hero_group == null or _result == null:
        return
    if str(_result.outcome) != MatchResultScript.OUTCOME_WIN:
        return
    # The hero GROUP is the snapshot's winning entries (Doc 06 §3): in team mode
    # EVERY member of the winning team, including one eliminated before match
    # end; in FFA the declared winner.
    var ids: Array = []
    var palettes: Array = []
    if bool(_result.team_mode):
        for entry in _result.winning_entries():
            var member_id := str(entry.get("fighter_id", ""))
            if Roster.ids().has(member_id):
                ids.append(member_id)
                palettes.append(int(entry.get("palette_index", 0)))
    else:
        var winner: Dictionary = _result.winner_entry()
        if winner.is_empty():
            return
        var id := str(winner.get("fighter_id", ""))
        if Roster.ids().has(id):
            ids.append(id)
            palettes.append(int(winner.get("palette_index", 0)))
        else:
            # Unknown id: keep a text hero, never a blank frame and never a
            # display-name reverse lookup (Doc 06 §3).
            _hero_text.text = str(winner.get("fighter_name", ""))
            _hero_text.show()
    if ids.is_empty():
        return
    _hero_ids = ids
    # One FighterRenderView per result, through the WP-3 presentation factory:
    # RESULTS_HERO for the FFA winner, RESULTS_TEAM for the coordinated winning
    # group (Doc 06 §7/§10). The team field is the ACTUAL wide group field (its
    # aspect IS the measured group box), so the render is never composed wide
    # and cropped into the FFA frame.
    var team_view := bool(_result.team_mode) and ids.size() > 1
    var profile: String = Factory.PROFILE_RESULTS_TEAM if team_view else Factory.PROFILE_RESULTS_HERO
    _hero_rect = _hero_rect_for(ids, profile)
    _set_hero_frame(_hero_rect)
    var view = FighterRenderViewScript.new()
    view.name = "WinnerRenderView"
    view.position = Vector2.ZERO
    view.size = _hero_rect.size
    _hero_group.add_child(view)
    view.set_profile(profile)
    view.set_subjects(ids)
    # Per-subject palette identity (Doc 06 §10): every winner keeps the variant
    # the match resolved for that station, so a duplicate fighter can never
    # collapse to one colour in the group.
    view.set_subject_palettes(palettes)
    # LIVE_IDLE while the surface is visible (Doc 06 §10), inside the ONE
    # viewport the live-view budget allocates to Results.
    view.set_presentation_mode(Factory.MODE_LIVE_IDLE)
    view.request_render()
    _hero_views.append(view)

func _hero_rect_for(ids: Array, profile: String) -> Rect2:
    # FFA and single-subject groups use the authored hero frame. A multi-subject
    # team group gets the wide group field: width fills the hero column and the
    # height follows the group's own measured aspect.
    if ids.size() <= 1 or profile != Factory.PROFILE_RESULTS_TEAM:
        return Rect2(HERO_X, HERO_Y, HERO_W, HERO_H)
    var box: AABB = Factory.box_for(ids, profile)
    var aspect := clampf(box.size.x / maxf(box.size.y, 0.01), 1.0, 2.4)
    var height := clampf(TEAM_HERO_W / aspect, TEAM_HERO_MIN_H, HERO_H)
    return Rect2(HERO_X, HERO_Y, TEAM_HERO_W, height)

func _set_hero_frame(rect: Rect2) -> void:
    var field := Rect2(rect.position.x - FIELD_PAD_X, rect.position.y - FIELD_PAD_Y,
        rect.size.x + FIELD_PAD_X * 2.0, rect.size.y + FIELD_PAD_Y * 2.0)
    _hero_field.position = field.position
    _hero_field.size = field.size
    _hero_tint.position = field.position
    _hero_tint.size = field.size
    _hero_accent.position = Vector2(rect.position.x + 8.0, field.position.y + field.size.y - 26.0)
    _hero_group.position = rect.position
    _hero_group.size = rect.size
    _hero_group.pivot_offset = Vector2(rect.size.x * 0.5, rect.size.y)

func _cursor_entry() -> void:
    # Always the regular NRCU cursor: pointer position untouched, stale hover
    # cleared, any carried token dropped (Doc 06 §15).
    if _cursor == null:
        return
    _cursor.visible = true
    _cursor.begin_screen("results")
    _cursor.clear_hover()
    if _cursor.is_carrying():
        _cursor.clear_carry()

# --- reveal timeline -------------------------------------------------------

func _on_tick(_index: int) -> void:
    if not _reveal_active:
        return
    _reveal_tick += 1
    if _reveal_tick >= TL_DONE:
        _complete_reveal()
        return
    if not _field_shown and _reveal_tick >= TL_FIELD:
        _field_shown = true
        _start(_hero_field, "modulate:a", 0.55, FIELD_REVEAL)
        _start(_hero_tint, "modulate:a", 1.0, FIELD_REVEAL)
    if not _outcome_shown and _reveal_tick >= TL_OUTCOME:
        _outcome_shown = true
        _start_outcome()
    while _rows_shown < _row_count and _reveal_tick >= TL_ROWS + TL_ROW_STAGGER * _rows_shown:
        _start_row(_rows_shown)
        _rows_shown += 1
    if not _actions_shown and _reveal_tick >= TL_ACTIONS:
        _actions_shown = true
        _start_actions()

func _process(delta: float) -> void:
    # Only used when the FrontendClock autoload is unavailable.
    if not _reveal_active:
        return
    _reveal_acc += delta
    while _reveal_acc >= 1.0 / FPS:
        _reveal_acc -= 1.0 / FPS
        _on_tick(0)

func _start_outcome() -> void:
    _start(_eyebrow, "modulate:a", 1.0, OUTCOME_POP)
    outcome_label.position.y = OUTCOME_Y + 8.0
    _start(outcome_label, "modulate:a", 1.0, OUTCOME_POP)
    _start(outcome_label, "position:y", OUTCOME_Y, OUTCOME_POP)
    _start(_outcome_rule, "modulate:a", 1.0, OUTCOME_POP)
    _start(_outcome_rule, "size:x", _rule_w, OUTCOME_POP)
    _start(_hero_accent, "modulate:a", 1.0, OUTCOME_POP)
    _hero_group.position.y = _hero_rect.position.y + 10.0
    _hero_group.scale = Vector2(0.97, 0.97)
    _start(_hero_group, "modulate:a", 1.0, HERO_SETTLE)
    _start(_hero_group, "position:y", _hero_rect.position.y, HERO_SETTLE)
    _start(_hero_group, "scale", Vector2.ONE, HERO_SETTLE)

func _start_row(index: int) -> void:
    var row: Control = _rows[index]
    row.visible = true
    row.position.x = -14.0
    _start(row, "modulate:a", 1.0, ROW_REVEAL)
    _start(row, "position:x", 0.0, ROW_REVEAL)

func _start_actions() -> void:
    _action_bar.position.y = ACTION_Y + 8.0
    _start(_action_bar, "modulate:a", 1.0, BAR_REVEAL)
    _start(_action_bar, "position:y", ACTION_Y, BAR_REVEAL)

func _complete_reveal() -> void:
    if not _reveal_active and _interactive:
        return
    _reveal_active = false
    _field_shown = true
    _outcome_shown = true
    _rows_shown = _row_count
    _actions_shown = true
    _kill_tweens()
    _apply_final_states()
    if _interactive:
        return
    _interactive = true
    _enable_actions()
    _seed_focus()
    if _reveal_events == 0:
        _reveal_events += 1
        FrontendEvents.emit_results_reveal()

func finish_reveal() -> void:
    # A fresh confirm after the safety window finishes the reveal now; the
    # action bar becomes interactive, but the finishing event itself was
    # consumed before the GUI stage (see _input).
    _complete_reveal()

func skip_wait() -> void:
    finish_reveal()   # legacy alias kept for the character-select route test

func _reset_for_show() -> void:
    _kill_tweens()
    _eyebrow.modulate.a = 0.0
    outcome_label.modulate.a = 0.0
    outcome_label.position.y = OUTCOME_Y + 8.0
    _outcome_rule.modulate.a = 0.0
    _outcome_rule.size.x = _rule_w * 0.5
    _hero_field.modulate.a = 0.0
    _hero_tint.modulate.a = 0.0
    _hero_accent.modulate.a = 0.0
    _hero_group.modulate.a = 0.0
    _hero_group.scale = Vector2(0.97, 0.97)
    _hero_group.position = Vector2(_hero_rect.position.x, _hero_rect.position.y + 10.0)
    for i in _rows.size():
        var row: Control = _rows[i]
        row.modulate.a = 0.0
        row.position = Vector2(-14.0, _row_offset(i))
        if i >= _row_count:
            row.visible = false
    _action_bar.modulate.a = 0.0
    _action_bar.position.y = ACTION_Y + 8.0
    for id in _actions:
        var button: Button = _actions[id]["button"]
        button.disabled = true
        button.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _actions[id]["underline"].visible = false
    # A disabled action is not focusable: re-author the chain and release a
    # focus that a previously shown reveal had placed on an action (Doc 03 §6).
    _wire_action_graph()
    _ensure_focus_alive()
    _seed_focus()

func _apply_final_states() -> void:
    _eyebrow.modulate.a = 1.0
    outcome_label.modulate.a = 1.0
    outcome_label.position.y = OUTCOME_Y
    _outcome_rule.modulate.a = 1.0
    _outcome_rule.size.x = _rule_w
    _hero_field.modulate.a = 0.55
    _hero_tint.modulate.a = 1.0
    _hero_accent.modulate.a = 1.0
    _hero_group.modulate.a = 1.0
    _hero_group.scale = Vector2.ONE
    _hero_group.position = _hero_rect.position
    for i in _rows.size():
        var row: Control = _rows[i]
        row.position = Vector2(0.0, _row_offset(i))
        if i < _row_count:
            row.visible = true
            row.modulate.a = 1.0
        else:
            row.visible = false
    _action_bar.modulate.a = 1.0
    _action_bar.position.y = ACTION_Y

func _enable_actions() -> void:
    for id in _actions:
        var button: Button = _actions[id]["button"]
        button.disabled = false
        button.mouse_filter = Control.MOUSE_FILTER_STOP
        if _cursor != null:
            _cursor.add_target(button)
    # The actions became reachable: re-author the chain (the disabled ones were
    # not part of it) and seed the authored default focus.
    _wire_action_graph()
    _seed_focus()

func _seed_focus() -> void:
    # Controller/keyboard focus seeds REMATCH through its authored anchor; a
    # mouse user keeps the pointer and no focus ring appears (Doc 06 §15).
    if _cursor == null or _interactive == false:
        return
    if _cursor.mode == 1:
        var spec: Dictionary = _actions["rematch"]
        spec["button"].grab_focus()
        _cursor.set_focus_target(spec["anchor"])

func _on_cursor_modality(mouse_mode: bool) -> void:
    if mouse_mode or not _interactive:
        return
    _seed_focus()

# --- actions ---------------------------------------------------------------

func _on_action_pressed(action_id: String) -> void:
    match action_id:
        "rematch":
            rematch_requested.emit()
        "setup":
            setup_requested.emit()
        "stage":
            stage_requested.emit()
        "menu":
            menu_requested.emit()

func _on_action_focus(action_id: String, focused: bool) -> void:
    _focus_action = action_id if focused else ("" if _focus_action == action_id else _focus_action)
    if focused and _cursor != null and _cursor.mode == 1:
        FocusGraph.track(self, _actions[action_id]["button"])
        _cursor.set_focus_target(_actions[action_id]["anchor"])
    _refresh_action_emphasis()

func _on_action_hover(action_id: String, hovered: bool) -> void:
    # A stationary pointer must not take over the screen (mouse intent §5).
    if _cursor != null and not _cursor.is_mouse_active():
        return
    _hover_action = action_id if hovered else ("" if _hover_action == action_id else _hover_action)
    _refresh_action_emphasis()

func _refresh_action_emphasis() -> void:
    for id in _actions:
        var spec: Dictionary = _actions[id]
        var button: Button = spec["button"]
        var emphasized: bool = id == _focus_action or id == _hover_action
        spec["underline"].visible = emphasized
        button.add_theme_color_override("font_color", Tokens.CREAM if (emphasized or bool(spec["primary"])) else Tokens.CREAM_DIM)

# --- semantic input (Doc 03 §7 / Doc 06 §16 reveal guard) -------------------

func _consume_semantic_confirm(_source: String) -> bool:
    # The first confirm after the safety window completes the reveal. It is
    # claimed through the semantic service BEFORE the GUI stage, so one event
    # can never both finish the reveal and activate an action (RESULT_REVEAL_
    # GUARD). Mouse-left, keyboard accept and controller A all reach here —
    # the same single path for all three devices.
    if not is_visible_in_tree():
        return false
    if not _reveal_active or _reveal_tick < SAFETY_TICKS:
        return false
    finish_reveal()
    return true

func _exit_tree() -> void:
    if FrontendInput != null:
        FrontendInput.clear_confirm_consumer(_consume_semantic_confirm)

# --- helpers ---------------------------------------------------------------

func _start(node: Object, property_path: String, value, seconds: float) -> void:
    var tween := create_tween()
    tween.tween_property(node, property_path, value, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    _tweens.append(tween)

func _kill_tweens() -> void:
    for tween in _tweens:
        if tween != null and tween.is_valid():
            tween.kill()
    _tweens.clear()

func _label(parent: Node, text: String, font_size: int, color: Color, rect: Rect2, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
    var label := Label.new()
    label.text = text
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.position = rect.position
    label.size = rect.size
    label.horizontal_alignment = align
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    parent.add_child(label)
    return label

func _plate(parent: Node, rect: Rect2, bg: Color, radius: int) -> Panel:
    var plate := Panel.new()
    plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
    plate.position = rect.position
    plate.size = rect.size
    plate.add_theme_stylebox_override("panel", Tokens.flat(bg, Color(0, 0, 0, 0), 0, radius))
    parent.add_child(plate)
    return plate

func _measure(label: Label) -> float:
    var font := label.get_theme_font("font")
    if font == null:
        return 360.0
    return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x

func _player_color(player_index: int) -> Color:
    var colors: Array = Tokens.PLAYER_COLORS
    return colors[posmod(player_index - 1, colors.size())]

func _team_name(team_id: int) -> String:
    # Team identity is a letter, never a player identity (Doc 06 §5).
    return "TEAM %s" % String.chr(65 + posmod(maxi(team_id, 0), 26))

func _team_color(team_id: int) -> Color:
    # Team color is deliberately separate from the P1..P4 player colors
    # (Doc 06 §5 / canonical 06 §8).
    return Tokens.TEAM_A if posmod(maxi(team_id, 0), 2) == 0 else Tokens.TEAM_B

func _placement_text(place: int) -> String:
    var suffix := "TH"
    if place % 100 < 11 or place % 100 > 13:
        match place % 10:
            1:
                suffix = "ST"
            2:
                suffix = "ND"
            3:
                suffix = "RD"
    return "%d%s" % [place, suffix]

# --- test surface ----------------------------------------------------------

func get_result():
    return _result

func is_interactive() -> bool:
    return _interactive

func is_revealing() -> bool:
    return _reveal_active

func is_outcome_revealed() -> bool:
    return _outcome_shown

func is_row_revealed(index: int) -> bool:
    return index >= 0 and index < _rows_shown

func reveal_tick() -> int:
    # WP-0 step 5: the PostMatch surface applies the Doc 01 §14 cancel rule
    # (ui_cancel leaves only after the reveal safety) against exactly the guard
    # window this screen already uses to ignore carry-over input.
    return _reveal_tick

func get_hero_ids() -> Array:
    return _hero_ids.duplicate()

func get_accent_color() -> Color:
    return _accent

func row_count() -> int:
    # Planned standings rows for the current result (FFA: one per player;
    # team: one group header per team plus its members).
    return _row_count

func row_kind(index: int) -> String:
    # "player" | "team_header" | "team_member" | "" (read surface for tests and
    # the evidence tool).
    if index >= 0 and index < _row_kinds.size():
        return str(_row_kinds[index])
    return ""

func row_entry(index: int) -> Dictionary:
    # The snapshot entry (or team group, for a header row) behind a row.
    if index >= 0 and index < _row_entries.size():
        return _row_entries[index]
    return {}

func row_text(index: int) -> String:
    # The row's one-line reading, exactly as composed on screen: a player row is
    # "RANK  P#  NAME" (rank omitted on team member rows), a team header row is
    # its shared-rank line ("1ST · TEAM A").
    if index < 0 or index >= _row_count:
        return ""
    var row: Control = _rows[index]
    if row == null:
        return ""
    if str(_row_kinds[index]) == "team_header":
        return (row.get_node("Rank") as Label).text
    var rank_label: Label = row.get_node("Rank")
    var port_label: Label = row.get_node("Port")
    var name_label: Label = row.get_node("Name")
    var parts: Array = []
    if rank_label.visible and rank_label.text != "":
        parts.append(rank_label.text)
    parts.append(port_label.text)
    parts.append(name_label.text)
    return "  ".join(parts)

func hero_view():
    # The ONE winner render view this screen owns (WP-3 FighterRenderView), or
    # null when the result has no hero (draw / unresolvable id).
    for view in _hero_views:
        if is_instance_valid(view):
            return view
    return null

func hero_rect() -> Rect2:
    # The authored hero group field actually used for this result: the FFA hero
    # frame, or the wide measured group field in team mode.
    return _hero_rect
