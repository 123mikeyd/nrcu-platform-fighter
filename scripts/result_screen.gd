extends Control
# NRCU Results — winner-first payoff screen (Doc 06, WP-E).
#
# Pure presentation/navigation over an explicit MatchResult snapshot: the
# screen sorts by `placement`, resolves the winner model from `fighter_id`,
# and never infers rank from stats (Doc 06 §3/§21).
#
# Composition at 1280x720 inside a centered ReferenceFrame (Doc 06 §6):
#   Top outcome header  y ~26-112   WINNER / P2 DOGE MAN / rule
#   Main payoff         y ~110-510  winner hero | final standings
#   Action bar          y ~585-670  Rematch / Change Fighters / [Stage] / Main Menu
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
const MAX_ROWS := 4
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
var _standings_label: Label
var _standings_rule: Panel
var _standings_list: Control
var _rows: Array = []
var _action_bar: Control
var _actions: Dictionary = {}
var _row_entries: Array = []
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
    _standings_list.size = Vector2(STAND_W, ROW_STRIDE * MAX_ROWS)
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
            heading = "TEAM %s WINS!" % ("A" if team == 0 else "B")
            _accent = Tokens.TEAM_A if team == 0 else Tokens.TEAM_B
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
    var ordered: Array = []
    if _result != null:
        ordered = _result.entries.duplicate()
        ordered.sort_custom(func(a, b): return int(a["placement"]) < int(b["placement"]))
    _row_entries = ordered
    _row_count = mini(_row_entries.size(), MAX_ROWS)
    for i in _rows.size():
        var row: Control = _rows[i]
        if i >= _row_count:
            row.visible = false
            continue
        _fill_row(row, _row_entries[i])

func _fill_row(row: Control, entry: Dictionary) -> void:
    var place := int(entry.get("placement", 0))
    var stocks := int(entry.get("stocks_remaining", 0))
    var eliminated: bool = stocks <= 0
    var player_index := int(entry.get("player_index", 0))
    var color := _player_color(player_index)
    var plate: Panel = row.get_node("Plate")
    plate.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_1 if eliminated else Tokens.SURFACE_HI, Tokens.RULE, Tokens.STROKE))
    var side: Panel = row.get_node("Side")
    side.add_theme_stylebox_override("panel", Tokens.flat(color))
    var rank: Label = row.get_node("Rank")
    rank.text = _placement_text(place)
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
    stocks_label.text = "OUT" if eliminated else "STOCKS %d" % stocks
    stocks_label.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    stocks_label.add_theme_font_size_override("font_size", Tokens.T_META)
    stocks_label.position.y = 28.0 if eliminated else 10.0
    var damage_label: Label = row.get_node("Damage")
    # Eliminated players show OUT and NO damage: lose_stock() resets
    # damage_percent to 0, so the value is not match information (Doc 06 §19).
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
    if _hero_group == null or _result == null:
        return
    if str(_result.outcome) != MatchResultScript.OUTCOME_WIN:
        return
    var ids: Array = []
    if bool(_result.team_mode):
        for entry in _result.winning_entries():
            var id := str(entry.get("fighter_id", ""))
            if Roster.ids().has(id):
                ids.append(id)
    else:
        var winner: Dictionary = _result.winner_entry()
        if winner.is_empty():
            return
        var id := str(winner.get("fighter_id", ""))
        if Roster.ids().has(id):
            ids.append(id)
        else:
            # Unknown id: keep a text hero, never a blank frame and never a
            # display-name reverse lookup (Doc 06 §3).
            _hero_text.text = str(winner.get("fighter_name", ""))
            _hero_text.show()
    if ids.is_empty():
        return
    _hero_ids = ids
    # One FighterRenderView per result: RESULTS_HERO for the FFA winner,
    # RESULTS_TEAM for the coordinated winning-team group (Doc 06 §9).
    var view = FighterRenderViewScript.new()
    view.set_profile("RESULTS_TEAM" if bool(_result.team_mode) else "RESULTS_HERO")
    view.position = Vector2.ZERO
    view.size = Vector2(HERO_W, HERO_H)
    _hero_group.add_child(view)
    view.set_subjects(ids)
    _hero_views.append(view)

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
    _hero_group.position.y = HERO_Y + 10.0
    _hero_group.scale = Vector2(0.97, 0.97)
    _start(_hero_group, "modulate:a", 1.0, HERO_SETTLE)
    _start(_hero_group, "position:y", HERO_Y, HERO_SETTLE)
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
    _hero_group.position = Vector2(HERO_X, HERO_Y + 10.0)
    for i in _rows.size():
        var row: Control = _rows[i]
        row.modulate.a = 0.0
        row.position = Vector2(-14.0, i * ROW_STRIDE)
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
    _hero_group.position = Vector2(HERO_X, HERO_Y)
    for i in _rows.size():
        var row: Control = _rows[i]
        row.position = Vector2(0.0, i * ROW_STRIDE)
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
