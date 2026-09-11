extends SceneTree
func _initialize(): call_deferred("run")
func run():
    var model = load("res://assets/teknium/teknium_animations.glb").instantiate()
    root.add_child(model)
    var player = model.find_children("*", "AnimationPlayer", true, false)[0]
    for pair in [["ForcePush",34.0/24.0],["GrabStart",17.0/24.0],["GrabLoop",30.0/24.0],["GrabEnd",13.0/24.0]]:
        if not player.has_animation(pair[0]):
            print("FAIL: missing approved cut ",pair[0]); quit(1); return
        if absf(player.get_animation(pair[0]).length-pair[1])>0.001:
            print("FAIL: wrong source speed/endpoints ",pair[0]);quit(1);return
    model.queue_free()
    print("PASS: all four exact inclusive approved source cuts at 24FPS")
    quit(0)
