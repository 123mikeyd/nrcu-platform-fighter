extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)
func key(code: int, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = pressed
    Input.parse_input_event(event)
    Input.flush_buffered_events()
func _init() -> void:
    call_deferred("run")
func run() -> void:
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    var slots = load("res://scripts/match_config.gd").default_slots()
    slots[1].kind = "human"
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    arena.start_match(slots, false)
    var f = arena.player_one
    var other = arena.player_two
    other.position = Vector3(8, 0.1, 0)
    f.position = Vector3(-5.2, 1.0, 0)
    f.velocity = Vector3(0, 12, 0)
    var crossed := false
    for i in range(90):
        await physics_frame
        crossed = crossed or f.position.y > 3.225
    check(crossed, "jump physically crosses platform underside")
    check(f.is_on_floor() and absf(f.position.y - 3.225) < 0.12, "descending fighter lands on upper surface")
    key(KEY_S, true)
    key(KEY_F, true)
    for i in range(3):
        await physics_frame
    check(f.is_on_floor() and f.last_move == "LOW SWEEP", "down attack stays on platform")
    key(KEY_S, false)
    key(KEY_F, false)
    for i in range(30):
        await physics_frame
    key(KEY_S, true)
    for i in range(12):
        await physics_frame
    key(KEY_S, false)
    check(f.position.y < 3.0, "tap down physically drops through upper platform")
    for i in range(60):
        await physics_frame
    check(f.is_on_floor() and f.position.y < 0.1, "solid main floor catches falling fighter")
    key(KEY_S, true)
    for i in range(10):
        await physics_frame
    key(KEY_S, false)
    check(f.is_on_floor() and f.position.y > -0.2, "down cannot pass through main floor")
    arena.queue_free()
    await process_frame
    if not failures:
        print("PASS: real one-way jump, landing, down attack priority, drop and solid floor")
    quit(1 if failures else 0)
