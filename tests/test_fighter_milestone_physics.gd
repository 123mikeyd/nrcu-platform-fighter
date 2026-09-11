extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, msg: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + msg)
func _initialize() -> void: call_deferred("run")
func key(code: Key, pressed: bool) -> void:
    var e := InputEventKey.new()
    e.keycode = code
    e.pressed = pressed
    Input.parse_input_event(e)
    Input.flush_buffered_events()
func run() -> void:
    var stage := Node3D.new()
    root.add_child(stage)
    var platform := StaticBody3D.new()
    platform.collision_layer = 2
    platform.add_to_group("pass_through_platforms")
    platform.set_meta("top_y", 3.0)
    platform.set_meta("half_width", 3.0)
    platform.position.y = 2.8
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(6, 0.4, 3)
    shape.shape = box
    platform.add_child(shape)
    stage.add_child(platform)
    var f = F.new()
    f.player_index = 1
    f.position = Vector3(0, 0.2, 0)
    stage.add_child(f)
    f.velocity.y = 14
    var peak := 0.0
    for i in 100:
        await physics_frame
        peak = maxf(peak, f.position.y)
    check(peak > 3.2, "passes upward through platform")
    check(f.is_on_floor() and absf(f.position.y - 3) < 0.1, "lands on upper platform")
    key(KEY_S, true)
    key(KEY_F, true)
    await physics_frame
    await physics_frame
    check(f.is_on_floor(), "down attack does not drop through")
    key(KEY_S, false)
    key(KEY_F, false)
    for i in 30: await physics_frame
    key(KEY_S, true)
    for i in 15: await physics_frame
    check(f.position.y < 2.5, "down tap drops from support")
    key(KEY_S, false)
    f.reset_fighter(Vector3(0, 5, 0), true)
    f.character_id = "ggb"
    f.velocity.y = -4
    f._jump_was_down = true
    key(KEY_SPACE, true)
    for i in 20: await physics_frame
    check(f.float_remaining < 1.1 and f.velocity.y >= -1.6, "hold jump slows fall with budget")
    key(KEY_SPACE, false)
    f.reset_fighter(Vector3(0, 3.1, 0), true)
    f.character_id = "turbofit"
    for i in 15: await physics_frame
    f.start_special(Vector2.DOWN)
    check(f.last_move == "SOUND ORB" and f.sound_orb_time > 0.0 and not f.drop_committed, "Turbo has utility Sound Orb, not a ground-only stomp")
    f.reset_fighter(Vector3(0, 5, 0), true)
    f.character_id = "doge_man"
    f.start_special(Vector2.RIGHT)
    key(KEY_A, true)
    for i in 4: await physics_frame
    check(f.facing > 0 and f.velocity.x > 0, "tackle commits forward despite reverse input")
    key(KEY_A, false)
    f.set_physics_process(false)
    f.stocks = 1
    f._handle_blast_zone()
    check(f.collision_layer == 0 and f.collision_mask == 0, "eliminated body cannot block players")
    f.reset_fighter(Vector3(0, 5, 0), true)
    check(f.collision_layer != 0 and f.collision_mask & 3 == 3, "restart restores collision")
    stage.queue_free()
    await process_frame
    if failures == 0: print("PASS milestone physics")
    quit(1 if failures else 0)
