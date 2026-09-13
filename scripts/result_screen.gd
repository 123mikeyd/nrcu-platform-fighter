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

const FPS := 60.0
const WAIT_TICKS := 160.0
const FADE_SECONDS := 0.25

var banner: Label

var _phase := 0  # 0 = wait (x1==0), 1 = interactive (x1==3)
var _wait := 0.0
var _pages: Array = []
var _page := 0
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

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build()

func _build() -> void:
    var view: Vector2 = get_viewport_rect().size
    var title := Label.new()
    title.text = "RESULTS"
    title.position = Vector2(64.0, 44.0)
    title.add_theme_font_size_override("font_size", 30)
    add_child(title)
    banner = Label.new()
    banner.name = "WinnerBanner"
    banner.position = Vector2(0.0, 110.0)
    banner.size = Vector2(view.x, 90.0)
    banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    banner.add_theme_font_size_override("font_size", 40)
    banner.hide()
    add_child(banner)
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
    _panel.position = Vector2(view.x * 0.5 - 260.0, 258.0)
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
    _stocks_label = Label.new()
    _stocks_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _stocks_label.add_theme_font_size_override("font_size", 22)
    _panel.add_child(_stocks_label)
    _damage_label = Label.new()
    _damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _damage_label.add_theme_font_size_override("font_size", 22)
    _panel.add_child(_damage_label)
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

func show_results(rows: Array) -> void:
    _pages = rows
    _page = 0
    _phase = 0
    _wait = WAIT_TICKS / FPS
    _panel.modulate.a = 0.0
    _panel.hide()
    _hint.show()
    banner.show()
    _rebuild_tabs()
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
