extends Control
# Result screen, Melee grammar (Doc 03 5, reduced for NRCU):
#   - the winner banner is up immediately (retail: winner pose + fanfare)
#   - the stat panels and the actions phase in after 160 ticks of waiting OR
#     on the first input (gmresult x1==0: START or auto-start at 0xA0 frames)
#   - one page per player; LEFT/RIGHT walk the pages with wraparound
#     (retail: A = next page, B = prev page; here one page per player)
#   - sounds and the stick-scroll stat tables stay out of scope until audio
#     assets exist (same reason Stufe 1.3 is still open)

signal rematch_requested
signal setup_requested
signal menu_requested
signal stage_requested

const FPS := 60.0
const WAIT_TICKS := 160.0
const FADE_SECONDS := 0.25
const PLAYER_COLORS := [Color("d95a4f"), Color("4f7fd9"), Color("d9c04f"), Color("5ad94f")]
const PANE_Y := 200.0

var banner: Label

var _phase := 0  # 0 = wait (x1==0), 1 = interactive (x1==3)
var _wait := 0.0
var _pages: Array = []
var _page := 0
var _ranks: Dictionary = {}
var _panes: Array = []
var _panel: VBoxContainer
var _hint: Label
var _tabs_row: HBoxContainer
var _tabs: Array = []
var _name_label: Label
var _stocks_label: Label
var _damage_label: Label
var _page_label: Label
var _prev: Button
var _next: Button
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
    var title := Label.new()
    title.text = "RESULTS"
    title.position = Vector2(44.0, 30.0)
    title.add_theme_font_size_override("font_size", 28)
    add_child(title)
    # Winner hero: the banner plus its accent line; the reveal pops it in.
    banner = Label.new()
    banner.name = "WinnerBanner"
    banner.position = Vector2(140.0, 74.0)
    banner.size = Vector2(1000.0, 84.0)
    banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    banner.add_theme_font_size_override("font_size", 44)
    banner.pivot_offset = Vector2(500.0, 42.0)
    banner.hide()
    add_child(banner)
    var hero_line := Panel.new()
    hero_line.name = "HeroLine"
    hero_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hero_line.position = Vector2(140.0, 162.0)
    hero_line.size = Vector2(1000.0, 3.0)
    hero_line.add_theme_stylebox_override("panel", _flat(Color("e5ad69"), Color(0, 0, 0, 0), 0, 1))
    add_child(hero_line)
    # Result panes: one per player, ranking hierarchy, click = inspect.
    for i in 4:
        var pane := Button.new()
        pane.name = "ResultPane" + str(i)
        pane.position = Vector2(145.0 + i * 250.0, PANE_Y)
        pane.size = Vector2(240.0, 116.0)
        pane.add_theme_stylebox_override("normal", _flat(Color("284e50"), Color("1b3436"), 2, 10))
        pane.add_theme_stylebox_override("hover", _flat(Color("2f4f4e"), Color("e5ad69"), 2, 10))
        pane.add_theme_stylebox_override("pressed", _flat(Color("2f4f4e"), Color("e5ad69"), 3, 10))
        pane.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10))
        pane.pressed.connect(_select_page.bind(i))
        add_child(pane)
        var rank := Label.new()
        rank.position = Vector2(8.0, 4.0)
        rank.add_theme_font_size_override("font_size", 13)
        pane.add_child(rank)
        var who := Label.new()
        who.position = Vector2(0.0, 6.0)
        who.size = Vector2(240.0, 24.0)
        who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        who.add_theme_font_size_override("font_size", 18)
        pane.add_child(who)
        var pname := Label.new()
        pname.position = Vector2(4.0, 34.0)
        pname.size = Vector2(232.0, 30.0)
        pname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        pname.add_theme_font_size_override("font_size", 20)
        pane.add_child(pname)
        var pstocks := Label.new()
        pstocks.position = Vector2(4.0, 68.0)
        pstocks.size = Vector2(232.0, 22.0)
        pstocks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        pstocks.add_theme_font_size_override("font_size", 15)
        pane.add_child(pstocks)
        var pdmg := Label.new()
        pdmg.position = Vector2(4.0, 90.0)
        pdmg.size = Vector2(232.0, 22.0)
        pdmg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        pdmg.add_theme_font_size_override("font_size", 15)
        pane.add_child(pdmg)
        _panes.append({"box": pane, "rank": rank, "who": who, "name": pname, "stocks": pstocks, "damage": pdmg})
    _hint = Label.new()
    _hint.name = "WaitHint"
    _hint.text = "PRESS ANY KEY"
    _hint.position = Vector2(0.0, 208.0)
    _hint.size = Vector2(view.x, 30.0)
    _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hint.add_theme_font_size_override("font_size", 16)
    _hint.modulate = Color(1, 1, 1, 0.6)
    _hint.hide()
    add_child(_hint)
    _panel = VBoxContainer.new()
    _panel.name = "StatPanel"
    _panel.position = Vector2(view.x * 0.5 - 260.0, 352.0)
    _panel.custom_minimum_size = Vector2(520.0, 0.0)
    _panel.add_theme_constant_override("separation", 10)
    _panel.modulate.a = 0.0
    add_child(_panel)
    _tabs_row = HBoxContainer.new()
    _tabs_row.alignment = BoxContainer.ALIGNMENT_CENTER
    _tabs_row.add_theme_constant_override("separation", 14)
    _panel.add_child(_tabs_row)
    _name_label = Label.new()
    _name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _name_label.add_theme_font_size_override("font_size", 34)
    _panel.add_child(_name_label)
    var stat_line := HBoxContainer.new()
    stat_line.alignment = BoxContainer.ALIGNMENT_CENTER
    stat_line.add_theme_constant_override("separation", 44)
    _panel.add_child(stat_line)
    _stocks_label = Label.new()
    _stocks_label.add_theme_font_size_override("font_size", 22)
    stat_line.add_child(_stocks_label)
    _damage_label = Label.new()
    _damage_label.add_theme_font_size_override("font_size", 22)
    stat_line.add_child(_damage_label)
    var nav := HBoxContainer.new()
    nav.alignment = BoxContainer.ALIGNMENT_CENTER
    nav.add_theme_constant_override("separation", 16)
    _panel.add_child(nav)
    _prev = Button.new()
    _prev.name = "PrevPage"
    _prev.text = "<"
    _prev.custom_minimum_size = Vector2(70.0, 44.0)
    _prev.pressed.connect(prev_page)
    nav.add_child(_prev)
    _page_label = Label.new()
    _page_label.custom_minimum_size = Vector2(90.0, 44.0)
    _page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    nav.add_child(_page_label)
    _next = Button.new()
    _next.name = "NextPage"
    _next.text = ">"
    _next.custom_minimum_size = Vector2(70.0, 44.0)
    _next.pressed.connect(next_page)
    nav.add_child(_next)
    var actions := HBoxContainer.new()
    actions.alignment = BoxContainer.ALIGNMENT_CENTER
    actions.add_theme_constant_override("separation", 16)
    _panel.add_child(actions)
    _rematch = Button.new()
    _rematch.name = "Rematch"
    _rematch.text = "Rematch"
    _rematch.custom_minimum_size = Vector2(240.0, 52.0)
    _rematch.pressed.connect(func(): rematch_requested.emit())
    actions.add_child(_rematch)
    _setup = Button.new()
    _setup.name = "ChangeFighters"
    _setup.text = "Change Fighters"
    _setup.custom_minimum_size = Vector2(240.0, 52.0)
    _setup.pressed.connect(func(): setup_requested.emit())
    actions.add_child(_setup)
    var actions2 := HBoxContainer.new()
    actions2.alignment = BoxContainer.ALIGNMENT_CENTER
    actions2.add_theme_constant_override("separation", 16)
    _panel.add_child(actions2)
    _stage_button = Button.new()
    _stage_button.name = "ChangeStage"
    _stage_button.text = "Change Stage"
    _stage_button.custom_minimum_size = Vector2(240.0, 52.0)
    _stage_button.pressed.connect(func(): stage_requested.emit())
    actions2.add_child(_stage_button)
    _menu_button = Button.new()
    _menu_button.name = "MainMenu"
    _menu_button.text = "Main Menu"
    _menu_button.custom_minimum_size = Vector2(240.0, 52.0)
    _menu_button.pressed.connect(func(): menu_requested.emit())
    actions2.add_child(_menu_button)

func show_results(rows: Array, allow_stage_change := false) -> void:
    _pages = rows
    _page = 0
    _phase = 0
    _wait = WAIT_TICKS / FPS
    _stage_button.visible = allow_stage_change
    # Results always uses the regular cursor (PC usability): the glove comes
    # back and any carried token state from the previous screen is cleared.
    if _cursor != null:
        _cursor.visible = true
        _cursor.clear_carry()
        _cursor.press_frame_enabled = true
    _panel.modulate.a = 0.0
    _panel.hide()
    _hint.show()
    banner.show()
    # Placement ranking: stocks first, then damage taken.
    var order: Array = []
    for i in _pages.size():
        order.append(i)
    order.sort_custom(func(a, b):
        var sa: int = int(_pages[a]["stocks"])
        var sb: int = int(_pages[b]["stocks"])
        if sa != sb:
            return sa > sb
        return int(_pages[a]["damage"]) < int(_pages[b]["damage"]))
    _ranks = {}
    for place in order.size():
        _ranks[order[place]] = place
    # Hero pop + panes staged (the panels themselves phase in after the wait).
    banner.scale = Vector2(0.86, 0.86)
    var hero := create_tween()
    hero.tween_property(banner, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _apply_panes()
    _rebuild_tabs()
    _apply_page()
    # Reset the panes AFTER the page pass so the staged reveal starts hidden.
    for pane in _panes:
        pane["box"].modulate.a = 0.0
        pane["box"].position.y = PANE_Y + 14.0

func _select_page(index: int) -> void:
    if index < 0 or index >= _pages.size():
        return
    _page = index
    _apply_page()

func _apply_panes() -> void:
    for i in _panes.size():
        var pane: Dictionary = _panes[i]
        if i >= _pages.size():
            pane["box"].visible = false
            continue
        var row: Dictionary = _pages[i]
        var place: int = int(_ranks.get(i, i))
        pane["box"].visible = true
        var pc: Color = PLAYER_COLORS[i]
        pane["rank"].text = ["1ST", "2ND", "3RD", "4TH"][mini(place, 3)]
        pane["who"].text = "P%d" % int(row["index"])
        pane["who"].add_theme_color_override("font_color", pc)
        pane["name"].text = str(row["name"])
        var stocks := int(row["stocks"])
        pane["stocks"].text = "OUT" if stocks <= 0 else ("STOCKS %d" % stocks)
        pane["damage"].text = "DAMAGE %d%%" % int(row["damage"])
        var is_winner: bool = place == 0
        pane["box"].add_theme_stylebox_override("normal", _flat(Color("35595a") if is_winner else Color("284e50"), Color("e5ad69") if is_winner else pc, 3 if is_winner else 2, 10))

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
    _panel.show()
    var tween := create_tween()
    tween.tween_property(_panel, "modulate:a", 1.0, FADE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    # Staged pane reveal (their own clocks, offset per placement).
    for i in _panes.size():
        var pane_box: Button = _panes[i]["box"]
        if not pane_box.visible:
            continue
        var pane_tween := create_tween()
        pane_tween.tween_property(pane_box, "modulate:a", 1.0, 0.22).set_delay(i * 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        pane_tween.parallel().tween_property(pane_box, "position:y", PANE_Y, 0.22).set_delay(i * 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    # Focus lands on Rematch like the old panel did - attract suppressed so the
    # hand never moves on its own (real mouse / real tab navigation only).
    var root = get_node_or_null("/root/Cursor")
    if root != null and root.hand != null:
        root.hand.attract_enabled = false
        _rematch.grab_focus()
        root.hand.attract_enabled = true
    else:
        _rematch.grab_focus()

func _rebuild_tabs() -> void:
    for tab in _tabs:
        tab.queue_free()
    _tabs.clear()
    for i in _pages.size():
        var tab := Label.new()
        tab.text = "P%d" % int(_pages[i]["index"])
        tab.add_theme_font_size_override("font_size", 18)
        _tabs_row.add_child(tab)
        _tabs.append(tab)

func _apply_page() -> void:
    if _pages.is_empty():
        return
    var row: Dictionary = _pages[_page]
    _name_label.text = str(row["name"])
    var stocks := int(row["stocks"])
    _stocks_label.text = "OUT" if stocks <= 0 else ("STOCKS %d" % stocks)
    _damage_label.text = "DAMAGE %d%%" % int(row["damage"])
    _page_label.text = "%d / %d" % [_page + 1, _pages.size()]
    for i in _tabs.size():
        _tabs[i].modulate = Color(1, 1, 1, 1.0) if i == _page else Color(1, 1, 1, 0.45)
    # The pane being inspected stays bright; the others recede.
    for i in _panes.size():
        if i < _pages.size():
            _panes[i]["box"].modulate.a = 1.0 if i == _page else 0.72

func _flat(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = border
    style.set_border_width_all(width)
    style.set_corner_radius_all(radius)
    return style

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
