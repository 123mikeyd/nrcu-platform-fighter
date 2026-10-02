extends Control
const Style = preload("res://scripts/demo_style.gd")
const Unlocks = preload("res://scripts/unlocks.gd")
var buttons: Dictionary = {}
var page: Control
var state := "opening"
var room: Control
func _ready():
    get_window().title = "NRCU — v0.6"
    if not OS.has_feature("web"): get_window().min_size = Vector2i(800,450)
    theme = Style.make()
    room = preload("res://scripts/candidate_room.gd").new()
    room.warm = Unlocks.story_clears() > 0
    add_child(room)
    get_tree().auto_accept_quit = false
    get_window().close_requested.connect(func(): show_page("quit"))
    show_page("home" if get_tree().has_meta("candidate_opened") else "opening")
func text(value: String, pos: Vector2, font_size: int, color := Color("dbe7e6")):
    var label := Label.new()
    label.text = value
    label.position = pos
    label.add_theme_font_size_override("font_size",font_size)
    label.add_theme_color_override("font_color",color)
    page.add_child(label)
    return label
func show_page(next: String):
    state = next
    buttons.clear()
    if is_instance_valid(page):
        remove_child(page)
        page.queue_free()
    page = Control.new()
    page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(page)
    var panel := Panel.new()
    panel.position = Vector2(28,28)
    panel.size = Vector2(550,664)
    panel.add_theme_stylebox_override("panel", Style.box(Color(0.025,0.065,0.10,0.95),Color("395768"),1))
    page.add_child(panel)
    text("N / R   •   UNDERGROUND TRANSMISSION",Vector2(58,54),16,Color("76afba"))
    text("v0.6 / UNFINISHED ALPHA",Vector2(58,654),14,Color("9aafb7"))
    text("SECTOR 07\nPRESSURE CHAMBER\n\nSYSTEMS  /  STABLE",Vector2(920,65),18,Color("a9c5cb"))
    if next == "help":
        Style.help(page,func(): show_page("home"))
        return
    if next == "opening":
        text("NRCU\nPresents",Vector2(58,200),64)
        text("An underground transmission.",Vector2(58,405),19)
        add_button("Continue", "continue", 526, func(): show_page("title"))
    elif next == "title":
        text("NRCU",Vector2(58,166),110)
        text("THE FORTRESS BELOW",Vector2(62,315),25,Color("80bbc9"))
        text("Seven encounters. Current combat kits.\nA place for the crew.",Vector2(62,383),18)
        add_button("Press Start", "start", 526, func():
            get_tree().set_meta("candidate_opened",true)
            show_page("home"))
    elif next == "home":
        var cleared := Unlocks.story_clears() > 0
        text("NRCU",Vector2(58,99),76)
        text("CREW WORKSHOP" if cleared else "FORTRESS / OPERATIONS",Vector2(62,205),24,Color("d5ac7a") if cleared else Color("80bbc9"))
        add_button("Story Mode", "story", 280, func(): enter_game("story"))
        add_button("Local Match", "play", 346, func(): enter_game("freeplay"))
        add_button("Heavy Bag", "bag", 412, func(): enter_game("heavy_bag"))
        add_button("Controls / Moves", "help", 478, func(): show_page("help"))
        add_button("Quit", "quit", 544, func(): show_page("quit"))
        text(_roster_line(),Vector2(62,620),14,Color("a1afb6"))
    else:
        text("End this\ntransmission?",Vector2(58,170),44)
        add_button("Stay here", "home", 450, func(): show_page("home"))
        add_button("Quit", "exit", 526, func(): get_tree().quit())
    var values = buttons.values().filter(func(b): return not b.disabled)
    for i in values.size():
        values[i].focus_neighbor_bottom = values[(i+1)%values.size()].get_path()
        values[i].focus_neighbor_top = values[(i-1+values.size())%values.size()].get_path()
    if not values.is_empty(): values[0].grab_focus()
func enter_game(entry: String):
    get_tree().auto_accept_quit = true
    if entry != "freeplay": get_tree().set_meta("nrcu_entry",entry)
    get_tree().change_scene_to_file("res://scenes/main.tscn")
func _roster_line() -> String:
    var ids: Array = load("res://scripts/roster.gd").ids()
    var total := 0
    var open := 0
    for id in ids:
        if id in Unlocks.NEVER_PLAYABLE: continue
        total += 1
        if Unlocks.is_playable(id): open += 1
    return "FIGHTERS UNLOCKED  %d / %d  ·  NEW CHALLENGERS MAY APPEAR" % [open, total] if open < total else "FULL CREW ASSEMBLED  %d / %d" % [open, total]
func add_button(label: String, id: String, y: float, action: Callable):
    var b := Button.new()
    b.name = id; b.text = label; b.position = Vector2(58,y); b.size = Vector2(490,54)
    b.add_theme_font_size_override("font_size",23)
    page.add_child(b); b.pressed.connect(action); buttons[id] = b
func _unhandled_key_input(event):
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        show_page("quit" if state == "home" else "home")
        get_viewport().set_input_as_handled()
