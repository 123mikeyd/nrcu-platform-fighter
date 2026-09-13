extends Control
const Style = preload("res://scripts/demo_style.gd")
const AppStateScript = preload("res://scripts/app_state.gd")
var buttons: Dictionary = {}
var page: Control
var state := "home"
var _page_lock := 0.0
var _rows: Array = []
var _board: Panel
var _context_label: Label
var _ambient := 0.0
func _ready():
    get_window().title = "NRCU — Friend Demo"
    get_window().min_size = Vector2i(800,450)
    theme = Style.make()
    var background := TextureRect.new()
    background.name = "ShelfBackground"
    background.texture = load("res://assets/menu/shelf_background.png")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    get_tree().auto_accept_quit = false
    get_window().close_requested.connect(func(): show_page("quit"))
    show_page("home")
func _process(delta: float) -> void:
    if _page_lock > 0.0:
        _page_lock = maxf(_page_lock - delta, 0.0)
    # Ambient: the board breathes on its own clock, independent of selection.
    if _board != null and is_instance_valid(_board):
        _ambient += delta
        _board.modulate = Color(1, 1, 1, 0.94 + 0.06 * (0.5 + 0.5 * sin(TAU * _ambient / 3.4)))

func _flat(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = border
    style.set_border_width_all(width)
    style.set_corner_radius_all(radius)
    return style

func _nav(action: Callable) -> void:
    # Input hygiene (Doc 01 §3.1): swallow page changes within a short window.
    if _page_lock > 0.0:
        return
    _page_lock = 0.1
    action.call()

func _animate_page() -> void:
    # 20F one-shot page enter (Doc 01 §4.1).
    if page == null:
        return
    page.pivot_offset = Vector2.ZERO
    page.modulate.a = 0.0
    page.scale = Vector2(0.97, 0.95)
    var tween := create_tween().set_parallel()
    tween.tween_property(page, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_property(page, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func show_page(next: String):
    state = next
    buttons.clear()
    _board = null
    _rows.clear()
    _context_label = null
    if is_instance_valid(page):
        remove_child(page)
        page.queue_free()
    page = Control.new()
    page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(page)
    if next == "help":
        var help = Style.help(page, func(): show_page("home"))
        buttons["home"] = help.find_child("HelpBack",true,false)
        _animate_page()
        return
    var title := Label.new()
    title.text = "NRCU" if next == "home" else "Leave the room?"
    title.position = Vector2(36,105)
    title.add_theme_font_size_override("font_size",102 if next == "home" else 30)
    page.add_child(title)
    if next == "home":
        _build_menu_board()
    else:
        add_button("Stay here", "home", 354, func(): _nav(func(): show_page("home")))
        add_button("Quit", "exit", 434, func(): _nav(func(): get_tree().quit()))
    var values = buttons.values().filter(func(b): return b.visible)
    for i in values.size():
        values[i].focus_neighbor_bottom = values[(i+1)%values.size()].get_path()
        values[i].focus_neighbor_top = values[(i-1+values.size())%values.size()].get_path()
    values[0].grab_focus()
    _animate_page()
func _build_menu_board() -> void:
    # Composed menu scene instead of a plain button stack: one board with rows
    # (accent strip + label), a context region and its own ambient clock.
    var board := Panel.new()
    board.name = "MenuBoard"
    board.position = Vector2(36.0, 158.0)
    board.size = Vector2(440.0, 356.0)
    board.add_theme_stylebox_override("panel", _flat(Color("233330"), Color("8a5a2b"), 2, 14))
    page.add_child(board)
    _board = board
    var options: Array = [
        {"label": "Play", "id": "play", "action": func(): _nav(func(): _enter("vs")), "context": "Pick fighters and a stage, then fight."},
        {"label": "Story Mode", "id": "story", "action": func(): _nav(func(): _enter("story")), "context": "One encounter: you against Bobo."},
        {"label": "How to Play", "id": "help", "action": func(): _nav(func(): show_page("help")), "context": "Moves, rules and controls."},
        {"label": "Quit", "id": "quit", "action": func(): _nav(func(): show_page("quit")), "context": "Leave the room."},
    ]
    for i in options.size():
        var option: Dictionary = options[i]
        var row := Button.new()
        row.name = str(option["id"])
        row.position = Vector2(16.0, 18.0 + i * 84.0)
        row.size = Vector2(408.0, 64.0)
        row.add_theme_stylebox_override("normal", _flat(Color("284e50"), Color("1b3436"), 2, 10))
        row.add_theme_stylebox_override("hover", _flat(Color("35595a"), Color("e5ad69"), 2, 10))
        row.add_theme_stylebox_override("pressed", _flat(Color("2f4f4e"), Color("e5ad69"), 3, 10))
        row.add_theme_stylebox_override("focus", _flat(Color("35595a"), Color("e5ad69"), 2, 10))
        var accent := Panel.new()
        accent.name = "Accent"
        accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
        accent.position = Vector2(6.0, 8.0)
        accent.size = Vector2(6.0, 48.0)
        accent.add_theme_stylebox_override("panel", _flat(Color("1b3436"), Color(0, 0, 0, 0), 0, 3))
        row.add_child(accent)
        var label := Label.new()
        label.text = str(option["label"])
        label.position = Vector2(30.0, 0.0)
        label.size = Vector2(360.0, 64.0)
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.add_theme_font_size_override("font_size", 25)
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(label)
        row.pressed.connect(option["action"])
        row.focus_entered.connect(_on_row_selected.bind(i))
        row.mouse_entered.connect(_on_row_selected.bind(i))
        board.add_child(row)
        buttons[str(option["id"])] = row
        _rows.append({"button": row, "accent": accent, "context": str(option["context"])})
        var cursor = get_node_or_null("/root/Cursor")
        if cursor != null and cursor.hand != null:
            cursor.hand.add_target(row)
    _context_label = Label.new()
    _context_label.name = "ContextLine"
    _context_label.position = Vector2(36.0, 530.0)
    _context_label.size = Vector2(440.0, 44.0)
    _context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _context_label.add_theme_font_size_override("font_size", 15)
    _context_label.modulate = Color(1, 1, 1, 0.75)
    page.add_child(_context_label)

func _on_row_selected(index: int) -> void:
    for i in _rows.size():
        var selected: bool = i == index
        var accent: Panel = _rows[i]["accent"]
        accent.add_theme_stylebox_override("panel", _flat(Color("e5ad69") if selected else Color("1b3436"), Color(0, 0, 0, 0), 0, 3))
        var row_button: Button = _rows[i]["button"]
        row_button.position.x = 24.0 if selected else 16.0
    if _context_label != null and is_instance_valid(_context_label) and index >= 0 and index < _rows.size():
        _context_label.text = str(_rows[index]["context"])

func add_button(label: String, id: String, y: float, action: Callable):
    var b := Button.new()
    b.name = id
    b.text = label
    b.position = Vector2(42,y)
    b.size = Vector2(290,62)
    b.add_theme_font_size_override("font_size",25)
    page.add_child(b)
    b.pressed.connect(action)
    buttons[id] = b
    var cursor = get_node_or_null("/root/Cursor")
    if cursor != null and cursor.hand != null:
        cursor.hand.add_target(b)
func _enter(mode: String) -> void:
    # Authored transition: the board eases out before the scene change.
    _animate_out_then(func():
        AppStateScript.enter_mode = mode
        get_tree().auto_accept_quit = true
        get_tree().change_scene_to_file("res://scenes/main.tscn"))

func _animate_out_then(action: Callable) -> void:
    if page == null:
        action.call()
        return
    var tween := create_tween().set_parallel()
    tween.tween_property(page, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    tween.tween_property(page, "scale", Vector2(0.98, 0.97), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    tween.chain().tween_callback(action)

func _unhandled_key_input(event):
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        show_page("quit" if state == "home" else "home")
        get_viewport().set_input_as_handled()
    elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10 and OS.is_debug_build() and state == "home":
        # Developer route: the old monolithic setup as a debug launcher,
        # deliberately not part of the normal player menu.
        _nav(func(): _enter("debug"))
        get_viewport().set_input_as_handled()
