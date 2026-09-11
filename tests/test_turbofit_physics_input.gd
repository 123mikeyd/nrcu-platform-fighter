extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok: failures += 1; printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func key(code: int, down: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()
func run() -> void:
    var stage := Node3D.new()
    root.add_child(stage)
    var platform := StaticBody3D.new()
    platform.collision_layer = 2
    platform.position.y = 3
    platform.add_to_group("pass_through_platforms")
    platform.set_meta("top_y", 3.25)
    platform.set_meta("half_width", 30.0)
    var collision := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(60,0.5,4)
    collision.shape = box
    platform.add_child(collision)
    stage.add_child(platform)
    var turbo = F.new()
    turbo.character_id = "turbofit"
    turbo.position = Vector3(0,6,0)
    stage.add_child(turbo)
    var v = turbo.get_node("VisualRoot/TurboFitVisual")
    var fell := false
    var landed := false
    for i in range(120):
        await physics_frame
        if v.current_clip == "FallLoop": fell = true; check(not turbo.is_on_floor(), "fall only in air")
        if v.current_clip == "Landing":
            landed = true
            check(turbo.is_on_floor() and absf(turbo.position.y - 3.25) < 0.03, "Landing requires actual upper-platform contact")
    check(fell and landed and v.current_clip == "Idle", "real drop completes fall-land-idle")
    key(KEY_D,true)
    var walked := false
    for i in range(22):
        await physics_frame
        if v.current_clip == "Walk": walked = true
    check(walked and v.current_clip == "Run" and turbo.position.x > 1, "keyboard acceleration drives Walk then Run")
    key(KEY_D,false)
    for i in range(25): await physics_frame
    key(KEY_F,true)
    for i in range(3): await physics_frame
    check(turbo.turbofit_attack_clip.is_empty() and v.current_clip == "MeleeHorizontal", "actual grounded F retains horizontal guitar")
    key(KEY_F,false)
    for i in range(55): await physics_frame
    key(KEY_S,true)
    key(KEY_F,true)
    for i in range(3): await physics_frame
    check(turbo.is_on_floor() and turbo.turbofit_attack_clip == "GoalkeeperKick" and v.current_clip == "GoalkeeperKick", "actual grounded S+F starts kick without platform drop")
    key(KEY_F,false)
    key(KEY_S,false)
    for i in range(70): await physics_frame
    key(KEY_W,true)
    key(KEY_F,true)
    for i in range(3): await physics_frame
    check(turbo.turbofit_attack_clip.is_empty() and turbo.last_move == "GUITAR SWING" and turbo.is_on_floor(), "up basic retains old guitar attack; rejected knee not mapped")
    key(KEY_F,false)
    key(KEY_W,false)
    for i in range(50): await physics_frame
    key(KEY_SPACE,true)
    for i in range(3): await physics_frame
    key(KEY_SPACE,false)
    check(v.current_clip == "Jump" and not turbo.is_on_floor(), "space still starts real upward Jump")
    key(KEY_S,true)
    key(KEY_F,true)
    for i in range(3): await physics_frame
    check(not turbo.is_on_floor() and turbo.turbofit_attack_clip == "AirDownKick" and v.current_clip == "AirDownKick", "actual airborne S+F uses approved down kick")
    key(KEY_F,false)
    key(KEY_S,false)
    fell = false
    landed = false
    for i in range(120):
        await physics_frame
        if v.current_clip == "FallLoop": fell = true
        if v.current_clip == "Landing": landed = true; check(turbo.is_on_floor(), "jump landing never occurs in air")
    check(landed and turbo.turbofit_attack_clip.is_empty(), "committed air down kick cancels into actual platform Landing; ordinary FallLoop already tested above")
    stage.queue_free()
    await process_frame
    if failures == 0: print("PASS TurboFit real keyboard Walk/Run, grounded F guitar, grounded S+F kick, airborne S+F AirDownKick, unchanged up guitar, jump, airborne loop and pass-through-platform landing")
    quit(1 if failures else 0)
