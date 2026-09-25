extends Panel
signal resume_requested
signal setup_requested
signal home_requested
const Style = preload("res://scripts/demo_style.gd")
func _ready():
    name = "CandidatePause"
    process_mode = Node.PROCESS_MODE_ALWAYS
    theme = Style.make()
    position = Vector2(360,135)
    size = Vector2(560,450)
    add_theme_stylebox_override("panel",Style.box(Color("0b1c2b"),Color("568996"),2))
    var title := Label.new()
    title.text = "NRCU  /  SIGNAL HELD\nPAUSED"
    title.position = Vector2(34,24)
    title.add_theme_font_size_override("font_size",30)
    add_child(title)
    for i in 4:
        var b := Button.new()
        b.text = ["Resume", "Controls / Moves", "Match Setup", "Main Menu"][i]
        b.position = Vector2(34,130+i*70)
        b.size = Vector2(492,54)
        add_child(b)
        if i == 0: b.pressed.connect(func(): resume_requested.emit())
        elif i == 1: b.pressed.connect(func(): Style.help(get_parent(),func(): b.grab_focus()).process_mode = Node.PROCESS_MODE_ALWAYS)
        elif i == 2: b.pressed.connect(func(): setup_requested.emit())
        else: b.pressed.connect(func(): home_requested.emit())
    hide()
func _unhandled_key_input(event):
    if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        resume_requested.emit()
