extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        print("FAIL: ", message)
func _init() -> void: call_deferred("run")
func key(code: Key) -> void:
    var event := InputEventKey.new()
    event.physical_keycode = code
    event.pressed = true
    root.push_input(event, true)
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    await process_frame
    check(lab.has_method("set_collision_shapes_visible"), "collision visualization toggle API exists")
    if not lab.has_method("set_collision_shapes_visible"):
        lab.free()
        quit(1)
        return
    var button = lab.find_child("CollisionShapes", true, false)
    check(button != null and button.text == "Collision shapes", "named exact toggle label")
    check(not lab.collision_debug.visible and not button.button_pressed, "off by default")
    key(KEY_F4)
    check(lab.collision_debug.visible and button.button_pressed, "F4 synchronizes toggle")
    check(button.focus_mode == Control.FOCUS_NONE, "click cannot steal jump keys")
    key(KEY_F1)
    check(lab.paused, "F1 unchanged")
    key(KEY_F2)
    check(lab.pending_steps == 1, "F2 unchanged")
    key(KEY_F3)
    check(lab.pending_steps == 0 and lab.collision_debug.visible, "reset retains visualization")
    key(KEY_F4)
    check(not lab.collision_debug.visible, "F4 turns off")
    lab.free()
    if failures == 0: print("PASS: collision debug toggle interface")
    quit(1 if failures else 0)
