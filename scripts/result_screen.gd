extends Control
# Result screen — the payoff frame (Melee result grammar, Doc 03 §5, recomposed):
#   - the winner payoff resolves first: the 3D hero rig (visual spec §10) plus
#     the winner wording (WinnerBanner, authored by main) pops in immediately
#   - standings panes, the detail inspector and the actions row phase in after
#     160 ticks of waiting OR on the first input (gmresult x1==0)
#   - one page per player; LEFT/RIGHT walk the pages with wraparound
#     (retail: A = next page, B = prev page; here one page per player)
#   - ranking: stocks desc, then damage asc; pane i shows its placement
#   - sounds and the stick-scroll stat tables stay out of scope until audio
#     assets exist (same reason Stufe 1.3 is still open)

signal rematch_requested
signal setup_requested
signal menu_requested
signal stage_requested

const Tokens = preload("res://scripts/ui_tokens.gd")
const Roster = preload("res://scripts/roster.gd")
const HeroRigScript = preload("res://scripts/hero_rig.gd")

const FPS := 60.0
const WAIT_TICKS := 160.0

# --- composition (1280x720 canvas, Tokens.DESIGN) -------------------------
const LEAD_X := 64.0          # left margin (Tokens.MARGIN)
const RIGHT_X := 544.0        # right column: standings + detail inspector
const MAIN_Y := 100.0         # top of the content area
const HERO_W := 448.0         # winner column width
const HERO_VIEW_H := 330.0    # 3D hero frame height
const CAPTION_H := 122.0      # winner wording plate height
const PANE_H := 72.0
const PANE_STRIDE := 80.0     # pane height + Tokens.S8
const PANE_Y0 := 132.0
const INSPECT_Y := 456.0
const INSPECT_H := 108.0
const FOOT_RULE_Y := 588.0
const HINT_Y := 600.0
const ACTIONS_Y := 604.0
const ACTIONS_H := 48.0

# Authored motion (doc bands: micro 6-10f, state 16-24f, screen 240-400 ms).
const HERO_POP_SECONDS := 0.30
const PANE_REVEAL_SECONDS := 0.16   # ~10 frames: micro band
const PANE_REVEAL_STEP := 0.055   # per placement: 1ST lands first
const FADE_SECONDS := 0.24
const PANE_DIM := 0.62            # unselected panes recede

var banner: Label  # WinnerBanner — main.gd writes the winner wording before show

var _phase := 0    # 0 = wait (gmresult x1==0), 1 = interactive (x1==3)
var _wait := 0.0
var _pages: Array = []
var _page := 0
var _ranks: Dictionary = {}
var _panes: Array = []            # {box, plate, rank, who, name, stocks, damage, home}
var _reveal_done := false
var _reveal_pending := 0
var _reveal_tweens: Array = []
var _hero                        # hero rig (SubViewportContainer subclass)
var _hero_col: Control
var _hero_id := ""
var _hero_text: Label
var _caption_bar: Panel
var _winner_tag: Label
var _winner_who: Label
var _standings_head: Label
var _standings_rule: Panel
var _hint: Label
var _inspector: Panel
var _insp_plate: Panel
var _name_label: Label
var _stocks_label: Label
var _damage_label: Label
var _page_label: Label
var _prev: Button
var _next: Button
var _actions: HBoxContainer
var _actions_home_y := ACTIONS_Y
var _rematch: Button
var _setup: Button
var _stage_button: Button
var _menu_button: Button
var _cursor: Control

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var root = get_node_or_null("/root/Cursor")
    if root != null:
        _cursor = root.hand
    _build()

func _build() -> void:
    var view: Vector2 = get_viewport_rect().size
    var right_edge: float = view.x - Tokens.MARGIN_RIGHT
    var pane_w: float = maxf(right_edge - RIGHT_X, 360.0)
    _build_header(right_edge)
    _build_hero_column()
    _build_standings(right_edge, pane_w)
    _build_footer(view, right_edge)

func _build_header(right_edge: float) -> void:
    var title := _make_label(self, "RESULTS", Tokens.T_SCREEN, Tokens.CREAM, Rect2(LEAD_X, 24.0, 320.0, 40.0))
    title.name = "Title"
    var meta := _make_label(self, "FINAL STANDINGS", Tokens.T_META, Tokens.CREAM_DIM, Rect2(right_edge - 280.0, 30.0, 280.0, 26.0), HORIZONTAL_ALIGNMENT_RIGHT)
    meta.name = "HeaderMeta"
    var rule := Tokens.band(Tokens.RULE, 1.0)
    rule.name = "TitleRule"
    rule.position = Vector2(LEAD_X, 74.0)
    rule.size = Vector2(right_edge - LEAD_X, 1.0)
    add_child(rule)
    var accent := Tokens.band(Tokens.ACCENT, 2.0)
    accent.name = "TitleAccent"
    accent.position = Vector2(LEAD_X, 73.0)
    accent.size = Vector2(112.0, 2.0)
    add_child(accent)

func _build_hero_column() -> void:
    _hero_col = Control.new()
    _hero_col.name = "WinnerHero"
    _hero_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hero_col.position = Vector2(LEAD_X, MAIN_Y)
    _hero_col.size = Vector2(HERO_W, HERO_VIEW_H + Tokens.S12 + CAPTION_H)
    _hero_col.pivot_offset = _hero_col.size * 0.5
    add_child(_hero_col)
    # Stage plate under the model: quiet surface, thin frame (hard edges).
    var stage := _make_plate(_hero_col, Rect2(0.0, 0.0, HERO_W, HERO_VIEW_H), Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_FRAME)
    stage.name = "HeroPlate"
    # Text hero: kept when no model can be resolved — never a blank frame.
    _hero_text = _make_label(_hero_col, "", Tokens.T_HERO, Tokens.CREAM, Rect2(Tokens.S24, 105.0, HERO_W - Tokens.S48, 120.0), HORIZONTAL_ALIGNMENT_CENTER)
    _hero_text.name = "HeroText"
    _hero_text.hide()
    # Wording plate: player color as structure, one accent, WinnerBanner inside.
    var caption := _make_plate(_hero_col, Rect2(0.0, HERO_VIEW_H + Tokens.S12, HERO_W, CAPTION_H), Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_PLATE)
    caption.name = "WinnerPlate"
    _caption_bar = _make_plate(caption, Rect2(0.0, 0.0, 6.0, CAPTION_H), Tokens.SURFACE_3, Color(0, 0, 0, 0), 0, Tokens.RADIUS_FLAT)
    _caption_bar.name = "WinnerColor"
    _winner_tag = _make_label(caption, "WINNER", Tokens.T_META, Tokens.ACCENT, Rect2(Tokens.S24, 12.0, 220.0, 18.0))
    _winner_tag.name = "WinnerTag"
    _winner_who = _make_label(caption, "", Tokens.T_META, Tokens.CREAM, Rect2(HERO_W - Tokens.S24 - 96.0, 12.0, 96.0, 18.0), HORIZONTAL_ALIGNMENT_RIGHT)
    _winner_who.name = "WinnerWho"
    banner = Label.new()
    banner.name = "WinnerBanner"
    banner.text = ""
    banner.position = Vector2(Tokens.S24, 34.0)
    banner.size = Vector2(HERO_W - Tokens.S48, 76.0)
    banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    banner.add_theme_font_size_override("font_size", Tokens.T_IDENTITY)
    banner.add_theme_color_override("font_color", Tokens.CREAM)
    caption.add_child(banner)

func _build_standings(right_edge: float, pane_w: float) -> void:
    _standings_head = _make_label(self, "STANDINGS", Tokens.T_META, Tokens.CREAM_DIM, Rect2(RIGHT_X, MAIN_Y + 4.0, 320.0, 20.0))
    _standings_head.name = "StandingsHead"
    _standings_rule = Tokens.band(Tokens.RULE, 1.0)
    _standings_rule.name = "StandingsRule"
    _standings_rule.position = Vector2(RIGHT_X, MAIN_Y + 26.0)
    _standings_rule.size = Vector2(right_edge - RIGHT_X, 1.0)
    add_child(_standings_rule)
    for i in 4:
        _build_pane(i, pane_w)
    _build_inspector(pane_w)

func _build_pane(index: int, pane_w: float) -> void:
    # Ranking row: player color plate + rank header + name/P tag + stats.
    var pane := Button.new()
    pane.name = "ResultPane" + str(index)
    pane.text = ""
    pane.position = Vector2(RIGHT_X, PANE_Y0 + index * PANE_STRIDE)
    pane.size = Vector2(pane_w, PANE_H)
    pane.focus_mode = Control.FOCUS_ALL
    Tokens.apply_styles(pane, Tokens.row_styles())
    pane.pressed.connect(_select_page.bind(index))
    add_child(pane)
    var plate := _make_plate(pane, Rect2(0.0, 0.0, 6.0, PANE_H), Tokens.SURFACE_3, Color(0, 0, 0, 0), 0, Tokens.RADIUS_FLAT)
    plate.name = "Color"
    var rank := _make_label(pane, "", Tokens.T_NAV, Tokens.CREAM, Rect2(Tokens.S24, 21.0, 76.0, 30.0))
    rank.name = "Rank"
    var who := _make_label(pane, "", Tokens.T_META, Tokens.CREAM, Rect2(108.0, 44.0, 150.0, 18.0))
    who.name = "Who"
    var pname := _make_label(pane, "", Tokens.T_NAV, Tokens.CREAM, Rect2(108.0, 12.0, pane_w - 108.0 - 220.0, 30.0))
    pname.name = "Name"
    var stocks := _make_label(pane, "", Tokens.T_META, Tokens.CREAM_DIM, Rect2(pane_w - Tokens.S24 - 170.0, 14.0, 170.0, 20.0), HORIZONTAL_ALIGNMENT_RIGHT)
    stocks.name = "Stocks"
    var damage := _make_label(pane, "", Tokens.T_META, Tokens.CREAM_DIM, Rect2(pane_w - Tokens.S24 - 170.0, 42.0, 170.0, 20.0), HORIZONTAL_ALIGNMENT_RIGHT)
    damage.name = "Damage"
    _panes.append({
        "box": pane, "plate": plate, "rank": rank, "who": who,
        "name": pname, "stocks": stocks, "damage": damage,
        "home": pane.position,
    })

func _build_inspector(pane_w: float) -> void:
    # Detail inspector: page nav + page label + the selected player's stats.
    _inspector = _make_plate(self, Rect2(RIGHT_X, INSPECT_Y, pane_w, INSPECT_H), Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_FRAME)
    _inspector.name = "StatPanel"
    _insp_plate = _make_plate(_inspector, Rect2(0.0, 0.0, 6.0, INSPECT_H), Tokens.SURFACE_3, Color(0, 0, 0, 0), 0, Tokens.RADIUS_FLAT)
    _insp_plate.name = "Color"
    _name_label = _make_label(_inspector, "", Tokens.T_IDENTITY, Tokens.CREAM, Rect2(Tokens.S24, 18.0, pane_w - 24.0 - 200.0, 44.0))
    _name_label.name = "Name"
    _stocks_label = _make_label(_inspector, "", Tokens.T_META, Tokens.CREAM_DIM, Rect2(Tokens.S24, 70.0, 168.0, 20.0))
    _stocks_label.name = "Stocks"
    _damage_label = _make_label(_inspector, "", Tokens.T_META, Tokens.CREAM_DIM, Rect2(204.0, 70.0, 168.0, 20.0))
    _damage_label.name = "Damage"
    var nav_x: float = pane_w - Tokens.S24 - 188.0
    _prev = _nav_button("PrevPage", "<", Vector2(nav_x, 32.0), prev_page)
    _page_label = _make_label(_inspector, "- / -", Tokens.T_NAV, Tokens.CREAM, Rect2(nav_x + 52.0, 32.0, 84.0, 44.0), HORIZONTAL_ALIGNMENT_CENTER)
    _page_label.name = "PageLabel"
    _next = _nav_button("NextPage", ">", Vector2(nav_x + 144.0, 32.0), next_page)

func _build_footer(view: Vector2, right_edge: float) -> void:
    var rule := Tokens.band(Tokens.RULE, 1.0)
    rule.name = "FootRule"
    rule.position = Vector2(LEAD_X, FOOT_RULE_Y)
    rule.size = Vector2(right_edge - LEAD_X, 1.0)
    add_child(rule)
    _hint = _make_label(self, "PRESS ANY KEY", Tokens.T_META, Tokens.CREAM_DIM, Rect2(0.0, HINT_Y, view.x, 24.0), HORIZONTAL_ALIGNMENT_CENTER)
    _hint.name = "WaitHint"
    _hint.hide()
    _actions = HBoxContainer.new()
    _actions.name = "ActionsRow"
    _actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _actions.position = Vector2(LEAD_X, ACTIONS_Y)
    _actions.custom_minimum_size = Vector2(0.0, ACTIONS_H)
    _actions.size = Vector2(760.0, ACTIONS_H)
    _actions.add_theme_constant_override("separation", int(Tokens.S12))
    add_child(_actions)
    _rematch = _action_button("Rematch", "Rematch", 168.0, true, func(): rematch_requested.emit())
    _setup = _action_button("ChangeFighters", "Change Fighters", 196.0, false, func(): setup_requested.emit())
    _stage_button = _action_button("ChangeStage", "Change Stage", 176.0, false, func(): stage_requested.emit())
    _menu_button = _action_button("MainMenu", "Main Menu", 160.0, false, func(): menu_requested.emit())

# --- builders -------------------------------------------------------------

func _make_label(parent: Node, text: String, font_size: int, color: Color, rect: Rect2, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
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

func _make_plate(parent: Node, rect: Rect2, bg: Color, border: Color, width: int, radius: int) -> Panel:
    var plate := Panel.new()
    plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
    plate.position = rect.position
    plate.size = rect.size
    plate.add_theme_stylebox_override("panel", Tokens.flat(bg, border, width, radius))
    parent.add_child(plate)
    return plate

func _nav_button(node_name: String, text: String, at: Vector2, action: Callable) -> Button:
    var button := Button.new()
    button.name = node_name
    button.text = text
    button.position = at
    button.size = Vector2(44.0, 44.0)
    button.add_theme_font_size_override("font_size", Tokens.T_NAV)
    Tokens.apply_styles(button, _secondary_styles())
    button.pressed.connect(action)
    _inspector.add_child(button)
    return button

func _action_button(node_name: String, text: String, width: float, primary: bool, action: Callable) -> Button:
    var button := Button.new()
    button.name = node_name
    button.text = text
    button.custom_minimum_size = Vector2(width, ACTIONS_H)
    button.add_theme_font_size_override("font_size", Tokens.T_ACTION)
    Tokens.apply_styles(button, _primary_styles() if primary else _secondary_styles())
    button.pressed.connect(action)
    _actions.add_child(button)
    return button

func _primary_styles() -> Dictionary:
    return {
        "normal": Tokens.flat(Tokens.SURFACE_2, Tokens.ACCENT, Tokens.STROKE_STRONG, Tokens.RADIUS_PLATE),
        "hover": Tokens.flat(Tokens.SURFACE_HI, Tokens.ACCENT, Tokens.STROKE_STRONG, Tokens.RADIUS_PLATE),
        "pressed": Tokens.flat(Tokens.SURFACE_HI, Tokens.ACCENT, Tokens.STROKE_SELECT, Tokens.RADIUS_PLATE),
        "focus": Tokens.flat(Tokens.SURFACE_2, Tokens.ACCENT, Tokens.STROKE_STRONG, Tokens.RADIUS_PLATE),
    }

func _secondary_styles() -> Dictionary:
    return {
        "normal": Tokens.flat(Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_PLATE),
        "hover": Tokens.flat(Tokens.SURFACE_2, Tokens.RULE_WARM, Tokens.STROKE, Tokens.RADIUS_PLATE),
        "pressed": Tokens.flat(Tokens.SURFACE_2, Tokens.ACCENT, Tokens.STROKE_STRONG, Tokens.RADIUS_PLATE),
        "focus": Tokens.flat(Tokens.SURFACE_1, Tokens.ACCENT, Tokens.STROKE_STRONG, Tokens.RADIUS_PLATE),
    }

# --- show / navigation API ------------------------------------------------

func show_results(rows: Array, allow_stage_change := false) -> void:
    _pages = rows if rows != null else []
    _page = 0
    _phase = 0
    _wait = WAIT_TICKS / FPS
    _reveal_done = false
    _reveal_pending = 0
    for tween in _reveal_tweens:
        if tween != null and tween.is_valid():
            tween.kill()
    _reveal_tweens.clear()
    _stage_button.visible = allow_stage_change
    # Results always uses the regular cursor (PC usability): the hand re-anchors
    # at the real pointer position (read-only, never warped) and needs genuine
    # mouse motion before the pointer drives hover on this screen again.
    if _cursor != null:
        _cursor.visible = true
        _cursor.clear_carry()
        _cursor.press_frame_enabled = true
        _cursor.reset_for_screen()
    _compute_ranks()
    _stack_panes()
    _ensure_hero()
    _apply_hero()
    _apply_panes()
    _apply_page()
    _stage_wait_frame()
    # Winner payoff pops in immediately (screen-level motion band).
    _hero_col.modulate.a = 0.45
    _hero_col.scale = Vector2(0.94, 0.94)
    banner.show()
    var pop := create_tween()
    pop.tween_property(_hero_col, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    pop.parallel().tween_property(_hero_col, "scale", Vector2.ONE, HERO_POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _select_page(index: int) -> void:
    if index < 0 or index >= _pages.size():
        return
    _page = index
    _apply_page()

func is_waiting() -> bool:
    return _phase == 0

func skip_wait() -> void:
    if _phase == 0:
        _wait = 0.0
        _enter_interactive()

func get_page_count() -> int:
    return _pages.size()

func get_page_index() -> int:
    return _page

func get_page_name() -> String:
    return str(_pages[_page]["name"]) if _page >= 0 and _page < _pages.size() else ""

func get_page_stocks() -> int:
    return int(_pages[_page]["stocks"]) if _page >= 0 and _page < _pages.size() else 0

func get_page_damage() -> int:
    return int(_pages[_page]["damage"]) if _page >= 0 and _page < _pages.size() else 0

func get_hero_id() -> String:
    # Resolved roster id of the winner hero ("" when no model can be shown).
    return _hero_id

func next_page() -> void:
    if _phase == 0:
        skip_wait()
        return
    if _pages.is_empty():
        return
    _page = (_page + 1) % _pages.size()
    _apply_page()

func prev_page() -> void:
    if _phase == 0:
        skip_wait()
        return
    if _pages.is_empty():
        return
    _page = (_page - 1 + _pages.size()) % _pages.size()
    _apply_page()

# --- phase flow -----------------------------------------------------------

func _process(delta: float) -> void:
    if _phase == 0 and _wait > 0.0:
        _wait = maxf(_wait - delta, 0.0)
        if _wait <= 0.0:
            _enter_interactive()

func _enter_interactive() -> void:
    if _phase == 1 or not is_visible_in_tree():
        return
    _phase = 1
    _hint.hide()
    _reveal_done = false
    _reveal_pending = 0
    _standings_head.show()
    _standings_rule.show()
    _inspector.show()
    _inspector.modulate.a = 0.0
    _actions.show()
    _actions.modulate.a = 0.0
    _actions.position.y = _actions_home_y + 10.0
    for i in _panes.size():
        var entry: Dictionary = _panes[i]
        var box: Button = entry["box"]
        if i >= _pages.size():
            continue
        box.show()
        box.modulate.a = 0.0
        var home: Vector2 = entry["home"]
        box.position = home + Vector2(-18.0, 0.0)
    # Staged pane reveal: 1ST lands first, then down the placements (own clocks).
    for i in _panes.size():
        if i >= _pages.size():
            continue
        var entry: Dictionary = _panes[i]
        var box: Button = entry["box"]
        var home: Vector2 = entry["home"]
        var place: int = int(_ranks.get(i, i))
        var delay: float = PANE_REVEAL_STEP * float(place)
        var pane_tween := create_tween()
        pane_tween.tween_property(box, "modulate:a", 1.0, PANE_REVEAL_SECONDS).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        pane_tween.parallel().tween_property(box, "position:x", home.x, PANE_REVEAL_SECONDS).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        pane_tween.finished.connect(_on_pane_reveal_done)
        _reveal_tweens.append(pane_tween)
        _reveal_pending += 1
    # Inspector + actions resolve right behind the panes.
    var settle := create_tween()
    settle.tween_property(_inspector, "modulate:a", 1.0, FADE_SECONDS).set_delay(0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    settle.parallel().tween_property(_actions, "modulate:a", 1.0, FADE_SECONDS).set_delay(0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    settle.parallel().tween_property(_actions, "position:y", _actions_home_y, FADE_SECONDS).set_delay(0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    # Focus lands on Rematch like the old panel did; the hand never moves on
    # focus (mouse-intent brief §5), so this only paints the button's frame.
    _rematch.grab_focus()
    if _reveal_pending == 0:
        _reveal_finished()

func _on_pane_reveal_done() -> void:
    _reveal_pending = maxi(_reveal_pending - 1, 0)
    if _reveal_pending == 0:
        _reveal_finished()

func _reveal_finished() -> void:
    _reveal_done = true
    _apply_page()

# --- data / presentation --------------------------------------------------

func _compute_ranks() -> void:
    _ranks = {}
    var order := _place_order()
    for place in order.size():
        _ranks[int(order[place])] = place

func _stack_panes() -> void:
    # Standings read top-to-bottom by placement: the winner sits on top.
    # Node identity (ResultPane{i} -> page i) is untouched, only the slot.
    for i in _panes.size():
        if i >= _pages.size():
            continue
        var entry: Dictionary = _panes[i]
        var place: int = int(_ranks.get(i, i))
        var home := Vector2(RIGHT_X, PANE_Y0 + place * PANE_STRIDE)
        entry["home"] = home
        var box: Button = entry["box"]
        box.position = home

func _place_order() -> Array:
    var order: Array = []
    for i in _pages.size():
        order.append(i)
    order.sort_custom(_is_ranked_higher)
    return order

func _is_ranked_higher(a: int, b: int) -> bool:
    # Placement ranking: stocks first, then damage taken.
    var sa: int = int(_pages[a].get("stocks", 0))
    var sb: int = int(_pages[b].get("stocks", 0))
    if sa != sb:
        return sa > sb
    return int(_pages[a].get("damage", 0)) < int(_pages[b].get("damage", 0))

func _winner_row() -> Dictionary:
    var order := _place_order()
    if order.is_empty():
        return {}
    var row: Dictionary = _pages[int(order[0])]
    # A draw (nobody left standing) keeps the text-only payoff.
    return row if int(row.get("stocks", 0)) > 0 else {}

func _color_for_row(row: Dictionary) -> Color:
    var colors: Array = Tokens.PLAYER_COLORS
    var idx := int(row.get("index", 1)) - 1
    var color: Color = colors[posmod(idx, colors.size())]
    return color

func _resolve_hero_id(row: Dictionary) -> String:
    # Rows carry the display name (not the roster id): prefer an explicit id,
    # then match the display name back to the roster. "" = no model.
    var given := str(row.get("id", ""))
    if given != "" and Roster.ids().has(given):
        return given
    var wanted := str(row.get("name", "")).strip_edges().to_upper()
    if wanted == "":
        return ""
    for candidate in Roster.ids():
        if Roster.display_name(str(candidate)).to_upper() == wanted:
            return str(candidate)
    return ""

func _ensure_hero() -> void:
    if _hero != null:
        return
    _hero = HeroRigScript.new()
    _hero.position = Vector2.ZERO
    _hero.size = Vector2(HERO_W, HERO_VIEW_H)
    _hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hero_col.add_child(_hero)
    _hero_col.move_child(_hero, 1)  # plate, model, fallback text, wording

func _apply_hero() -> void:
    var winner := _winner_row()
    _hero_id = _resolve_hero_id(winner) if not winner.is_empty() else ""
    _hero.show()
    if _hero.is_node_ready():
        _hero.set_fighter(_hero_id)
    else:
        _hero.ready.connect(_flush_hero, CONNECT_ONE_SHOT)
    var winner_name := str(winner.get("name", "")) if not winner.is_empty() else ""
    if winner.is_empty():
        _caption_bar.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE, Color(0, 0, 0, 0), 0, Tokens.RADIUS_FLAT))
        _winner_tag.hide()
        _winner_who.hide()
    else:
        var pc: Color = _color_for_row(winner)
        _caption_bar.add_theme_stylebox_override("panel", Tokens.flat(pc, Color(0, 0, 0, 0), 0, Tokens.RADIUS_FLAT))
        _winner_tag.show()
        _winner_tag.text = "WINNER"
        _winner_who.show()
        _winner_who.text = "P%d" % int(winner.get("index", 0))
        _winner_who.add_theme_color_override("font_color", pc)
    # No model resolved (unknown id / draw): keep the text hero, never crash.
    if _hero_id == "" and winner_name != "":
        _hero_text.text = winner_name
        _hero_text.show()
    else:
        _hero_text.hide()
    if str(banner.text).strip_edges() == "":
        banner.text = ("P%d %s WINS!" % [int(winner.get("index", 0)), winner_name]) if not winner.is_empty() else "DRAW"

func _flush_hero() -> void:
    if _hero != null:
        _hero.set_fighter(_hero_id)

func _stage_wait_frame() -> void:
    # Wait phase: only the title, the winner payoff and the hint are on screen.
    for entry in _panes:
        var box: Button = entry["box"]
        var home: Vector2 = entry["home"]
        box.modulate.a = 0.0
        box.position = home
        box.hide()
    _standings_head.hide()
    _standings_rule.hide()
    _inspector.hide()
    _actions.hide()
    _hint.show()

func _apply_panes() -> void:
    for i in _panes.size():
        var entry: Dictionary = _panes[i]
        var box: Button = entry["box"]
        if i >= _pages.size():
            box.hide()
            continue
        var row: Dictionary = _pages[i]
        var place: int = int(_ranks.get(i, i))
        box.show()
        var pc: Color = _color_for_row(row)
        var plate: Panel = entry["plate"]
        plate.add_theme_stylebox_override("panel", Tokens.flat(pc, Color(0, 0, 0, 0), 0, Tokens.RADIUS_FLAT))
        var rank_label: Label = entry["rank"]
        rank_label.text = ["1ST", "2ND", "3RD", "4TH"][mini(place, 3)]
        rank_label.add_theme_color_override("font_color", Tokens.ACCENT if place == 0 else Tokens.CREAM)
        var who: Label = entry["who"]
        who.text = "P%d" % int(row.get("index", i + 1))
        who.add_theme_color_override("font_color", pc)
        var pname: Label = entry["name"]
        pname.text = str(row.get("name", ""))
        var stocks := int(row.get("stocks", 0))
        var stocks_label: Label = entry["stocks"]
        stocks_label.text = "OUT" if stocks <= 0 else ("STOCKS %d" % stocks)
        var damage_label: Label = entry["damage"]
        damage_label.text = "DAMAGE %d%%" % int(row.get("damage", 0))
        _style_pane(box, place == 0)

func _style_pane(box: Button, is_winner: bool) -> void:
    var styles := Tokens.row_styles()
    if is_winner:
        styles["normal"] = Tokens.flat(Tokens.SURFACE_HI, Tokens.ACCENT, Tokens.STROKE_STRONG, Tokens.RADIUS_PLATE)
    Tokens.apply_styles(box, styles)

func _apply_page() -> void:
    if _pages.is_empty():
        return
    var row: Dictionary = _pages[_page]
    var pc: Color = _color_for_row(row)
    _insp_plate.add_theme_stylebox_override("panel", Tokens.flat(pc, Color(0, 0, 0, 0), 0, Tokens.RADIUS_FLAT))
    _name_label.text = str(row.get("name", ""))
    var stocks := int(row.get("stocks", 0))
    _stocks_label.text = "OUT" if stocks <= 0 else ("STOCKS %d" % stocks)
    _damage_label.text = "DAMAGE %d%%" % int(row.get("damage", 0))
    _page_label.text = "%d / %d" % [_page + 1, _pages.size()]
    _refresh_pane_emphasis()

func _refresh_pane_emphasis() -> void:
    # The pane being inspected stays bright; the others recede.
    if not _reveal_done:
        return
    for i in _panes.size():
        if i >= _pages.size():
            continue
        var box: Button = _panes[i]["box"]
        box.modulate.a = 1.0 if i == _page else PANE_DIM

# --- input ----------------------------------------------------------------

func _input(event: InputEvent) -> void:
    # Runs before the GUI: LEFT/RIGHT must walk the pages here, otherwise a
    # focused button eats them as focus navigation (same for the first input
    # that starts the panels early).
    # CRITICAL: guard on is_visible_in_tree(). The node's own `visible` stays
    # true while the parent panel is hidden - consuming events then would
    # swallow every GUI click in the whole game. This exact regression ate all
    # mouse clicks until it was caught in a live check.
    if not is_visible_in_tree():
        return
    if _phase == 0:
        if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_R]:
            return  # Esc (leave) and R (rematch) keep working during the wait
        if event is InputEventMouseButton and event.pressed:
            skip_wait()
            get_viewport().set_input_as_handled()
        elif event is InputEventKey and event.pressed and not event.echo:
            skip_wait()
            get_viewport().set_input_as_handled()
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_LEFT:
            prev_page()
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_RIGHT:
            next_page()
            get_viewport().set_input_as_handled()
