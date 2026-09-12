extends Control
const Style = preload("res://scripts/demo_style.gd")
var buttons: Dictionary = {}
var page: Control
var state := "home"
var _page_lock := 0.0
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
        add_button("Play", "play", 354, func(): _nav(func():
            get_tree().auto_accept_quit = true
            get_tree().change_scene_to_file("res://scenes/main.tscn")))
        add_button("How to Play", "help", 434, func(): _nav(func(): show_page("help")))
        add_button("Quit", "quit", 514, func(): _nav(func(): show_page("quit")))
    else:
        add_button("Stay here", "home", 354, func(): _nav(func(): show_page("home")))
        add_button("Quit", "exit", 434, func(): _nav(func(): get_tree().quit()))
    var values = buttons.values()
    for i in values.size():
        values[i].focus_neighbor_bottom = values[(i+1)%values.size()].get_path()
        values[i].focus_neighbor_top = values[(i-1+values.size())%values.size()].get_path()
    values[0].grab_focus()
    _animate_page()
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
func _unhandled_key_input(event):
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        show_page("quit" if state == "home" else "home")
        get_viewport().set_input_as_handled()
