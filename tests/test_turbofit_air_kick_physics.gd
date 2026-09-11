extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
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
    var floor := StaticBody3D.new()
    floor.collision_layer = 2
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(20, 1, 4)
    shape.shape = box
    floor.position.y = -0.5
    floor.add_child(shape)
    stage.add_child(floor)
    var f = F.new()
    f.character_id = "turbofit"
    f.position = Vector3(0, 4, 0)
    stage.add_child(f)
    var v = f.get_node("VisualRoot/TurboFitVisual")
    for direction in [0, KEY_A, KEY_D]:
        f.reset_fighter(Vector3(0, 4, 0), true)
        for i in range(2): await physics_frame
        if direction: key(direction, true)
        key(KEY_F, true)
        for i in range(3): await physics_frame
        check(not f.is_on_floor() and f.turbofit_attack_clip == "AirSideKick" and v.current_clip == "AirSideKick", "real airborne F/A+F/D+F route to side kick")
        var elapsed: float = f.turbofit_attack_elapsed
        for i in range(3): await physics_frame
        check(f.turbofit_attack_elapsed > elapsed, "held F does not restart clip")
        key(KEY_F, false)
        if direction: key(direction, false)
    # Start late in a real descent; contact before frame42 must abort the hit,
    # restore the original Landing animation, and not leave an aerial cooldown.
    f.reset_fighter(Vector3(0, 0.22, 0), true)
    f.velocity = Vector3(0, -2, 0)
    for i in range(2): await physics_frame
    key(KEY_F, true)
    var saw_kick := false
    var saw_landing := false
    for i in range(20):
        await physics_frame
        if f.turbofit_attack_clip == "AirSideKick": saw_kick = true
        if f.is_on_floor():
            saw_landing = saw_landing or v.current_clip == "Landing"
            check(f.turbofit_attack_clip.is_empty(), "real floor contact cancels airborne-only clip")
    key(KEY_F, false)
    check(saw_kick and saw_landing, "late air kick returns to existing floor-contact Landing")
    stage.queue_free()
    await process_frame
    if failures == 0: print("PASS TurboFit real F/A+F/D+F airborne input, held-edge behavior and contact-cancel Landing")
    quit(1 if failures else 0)
