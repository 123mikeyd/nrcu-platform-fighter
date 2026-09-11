extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, msg: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + msg)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var f = F.new()
    root.add_child(f)
    f.set_physics_process(false)
    check(f.has_method("read_controls"), "shared device input")
    if f.has_method("read_controls"):
        f.player_index = 4
        f.input_device = 2
        var event := InputEventJoypadMotion.new()
        event.device = 2
        event.axis = JOY_AXIS_LEFT_X
        event.axis_value = 1
        Input.parse_input_event(event)
        Input.flush_buffered_events()
        check(f.read_controls(0.016).right, "P4 reads selected pad")
        f.input_device = -1
        check(not f.read_controls(0.016).right, "P4 does not steal P2 keyboard")
        f.control_type = "bot"
        f.position = Vector3(11, -2, 0)
        var intent: Dictionary = f.read_controls(1)
        check(intent.left and (intent.jump or intent.special), "bot steers inward and recovers")
    var platform := StaticBody3D.new()
    platform.collision_layer = 2
    platform.add_to_group("pass_through_platforms")
    platform.set_meta("top_y", 3.0)
    platform.set_meta("half_width", 2.0)
    root.add_child(platform)
    check(f.has_method("_update_platform_collisions"), "per-fighter one-way platforms")
    if f.has_method("_update_platform_collisions"):
        f.position = Vector3(0, 2, 0)
        f.velocity.y = 5
        f._update_platform_collisions(0.016)
        check(platform in f.get_collision_exceptions(), "passes upward from below")
        f.position.y = 3
        f.velocity.y = -1
        f._update_platform_collisions(0.016)
        check(platform not in f.get_collision_exceptions(), "lands from above")
        check(not f.try_drop_through(), "cannot drop unless supported")
        f.reset_fighter(Vector3.ZERO)
        check(f.get_collision_exceptions().is_empty(), "reset clears platform exceptions")
    f.queue_free()
    platform.queue_free()
    await process_frame
    if failures == 0: print("PASS devices and platforms")
    quit(1 if failures else 0)
