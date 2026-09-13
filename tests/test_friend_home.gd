extends SceneTree
func _initialize(): call_deferred("run")
func run():
    if not ResourceLoader.exists("res://scenes/home.tscn"):
        print("FAIL: static home scene missing"); quit(1); return
    var home = load("res://scenes/home.tscn").instantiate()
    root.add_child(home)
    await process_frame
    if home.find_children("*", "Node3D", true, false).size() != 0 or home.find_child("ShelfBackground", true, false) == null:
        print("FAIL: home must use texture, no 3D nodes"); quit(1); return
    if home.buttons.keys() != ["play", "story", "debug", "help", "quit"]:
        print("FAIL: home live actions missing"); quit(1); return
    home.show_page("help")
    if not home.buttons.has("home"):
        print("FAIL: help back navigation"); quit(1); return
    print("PASS static home and live navigation")
    home.queue_free()
    await process_frame
    quit(0)
