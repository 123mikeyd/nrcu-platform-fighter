extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL " + message)
func _initialize() -> void: call_deferred("run")
func key(code: int, down: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()
func step(count: int) -> void:
    for i in count:
        await physics_frame
        await process_frame
func run() -> void:
    var stage := Node3D.new()
    root.add_child(stage)
    var floor := StaticBody3D.new()
    floor.collision_layer = 2
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(20,1,4)
    shape.shape = box
    floor.position.y = -0.5
    floor.add_child(shape)
    stage.add_child(floor)
    var f = F.new()
    f.character_id = "doge_man"
    stage.add_child(f)
    await step(10)
    check(f.is_grounded(),"fixture terrain grounded")
    key(KEY_S,true)
    key(KEY_G,true)
    await step(5)
    check(f.charging,"ground Down+G charges rather than doing nothing")
    check(absf(f.position.x)<0.001,"charge plants controller")
    key(KEY_S,false)
    await step(2)
    check(f.charging,"Down release does not release latched charge")
    key(KEY_G,false)
    await step(2)
    check(f.last_move == "CHARGING OF THE BULL" and f.velocity.x>0,"G release rushes on latched down route")
    await step(80)
    check(f.torpedo_phase == "idle" and f.is_grounded(),"ground rush never becomes flying tackle")
    stage.queue_free()
    await process_frame
    if not failures: print("PASS Doge grounded charged rush real input routing")
    quit(1 if failures else 0)
