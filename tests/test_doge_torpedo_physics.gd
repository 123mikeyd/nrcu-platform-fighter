extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, msg: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + msg)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var stage := Node3D.new()
    root.add_child(stage)
    var floor_body := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(100, 1, 5)
    shape.shape = box
    floor_body.position.y = -0.5
    floor_body.add_child(shape)
    stage.add_child(floor_body)
    var dog = F.new()
    dog.character_id = "doge_man"
    dog.player_index = 3
    stage.add_child(dog)
    for i in 10: await physics_frame
    check(dog.is_on_floor(), "physical floor established")
    dog.start_special(Vector2.RIGHT)
    var phases: Array = []
    for i in 150:
        await physics_frame
        if dog.torpedo_phase not in phases: phases.append(dog.torpedo_phase)
        if dog.torpedo_phase == "launch":
            check(dog.tackle_spent, "ground takeoff retains spent tackle")
        if dog.torpedo_phase == "landing":
            check(dog.is_on_floor(), "landing only on actual support")
            check(dog.tackle_active == 0, "landing never damages")
            check(not dog.try_jump(), "landing recovery cannot jump cancel")
    check(phases == ["launch", "tackle", "fall", "landing", "idle"], "physical phase sequence: " + str(phases))
    check(dog.is_on_floor() and not dog.tackle_spent, "landing restores resources")
    dog.reset_fighter(Vector3(0, 7, 0), true)
    dog.start_special(Vector2.LEFT)
    for i in 60: await physics_frame
    check(dog.torpedo_phase == "fall" and not dog.is_on_floor(), "high-air dive waits for collision, not clip end")
    stage.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge torpedo physics")
    quit(1 if failures else 0)
