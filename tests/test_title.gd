extends SceneTree
# Focused check for the frontend brief §3 boot route: BOOT -> TITLE -> MAIN MENU.
# The title card must be a pure Control scene over the shelf texture, exposing
# begin() as the one transition path (key / click / pad buttons all go through
# it, behind a short entry lock).
const Tokens = preload("res://scripts/ui_tokens.gd")

func _initialize(): call_deferred("run")

func fail(message: String) -> void:
    print("FAIL: " + message)
    quit(1)

func label_containing(node: Node, needle: String) -> Label:
    for child in node.find_children("*", "Label", true, false):
        if str(child.text).find(needle) != -1:
            return child
    return null

func start_event() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_F
    event.pressed = true
    return event

# The menu must arrive as a NEW "Home" instance (a repeat scene change swaps
# the previous one out), so compare against the instance seen before.
func route_to_menu(previous) -> bool:
    for i in 300:
        await process_frame
        var current = root.get_node_or_null("Home")
        if current != null and current != previous:
            return true
    return false

func run():
    if not ResourceLoader.exists("res://scenes/title.tscn"):
        fail("static title scene missing"); return
    var title = load("res://scenes/title.tscn").instantiate()
    root.add_child(title)
    for i in 3: await process_frame
    if title.find_children("*", "Node3D", true, false).size() != 0:
        fail("title must be a pure Control card, no 3D nodes"); return
    var background = title.find_child("ShelfBackground", true, false)
    if background == null or not (background is TextureRect) or background.texture == null:
        fail("title background must be the room texture"); return
    var wordmark = label_containing(title, "NRCU")
    if wordmark == null or wordmark.get_theme_font_size("font_size") < Tokens.T_HERO:
        fail("hero NRCU wordmark missing or below hero scale"); return
    if title.find_child("Prompt", true, false) == null:
        fail("start prompt missing"); return
    if not title.has_method("begin"):
        fail("title must expose begin()"); return
    # begin() is the callable the key/click/pad path uses: no error, and it
    # reaches the main menu.
    title.begin()
    var routed: bool = await route_to_menu(null)
    if not routed:
        fail("begin() did not route to the main menu"); return
    # Any key must also route — but never inside the entry lock.
    var locked = load("res://scenes/title.tscn").instantiate()
    root.add_child(locked)
    await process_frame
    locked._unhandled_input(start_event())
    if locked._leaving:
        fail("title skipped instantly, entry lock is not armed"); return
    await create_timer(0.5).timeout
    var menu = root.get_node_or_null("Home")
    locked._unhandled_input(start_event())
    routed = await route_to_menu(menu)
    if not routed:
        fail("key input did not route to the main menu"); return
    print("PASS title card and BOOT -> TITLE -> MENU route")
    for child in root.get_children():
        if child.name == "Home":
            child.queue_free()
    locked.queue_free()
    title.queue_free()
    await process_frame
    quit(0)
