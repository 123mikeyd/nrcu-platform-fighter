extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
var checks := 0
var stage: Node3D
var f
var target
func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAIL " + message)
func _initialize() -> void: call_deferred("run")
func step(count: int) -> void:
    for i in count:
        await physics_frame
        await process_frame
func floor_at(center: Vector3, size: Vector3, pass_through := false) -> StaticBody3D:
    var floor := StaticBody3D.new()
    floor.collision_layer = 2
    var collision := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    collision.shape = box
    floor.position = center
    floor.add_child(collision)
    stage.add_child(floor)
    if pass_through:
        floor.add_to_group("pass_through_platforms")
        floor.set_meta("top_y",center.y+size.y/2)
        floor.set_meta("half_width",size.x/2)
    return floor
func reset(pos: Vector3, face: float, other: Vector3) -> void:
    # Fresh bodies prevent prior fighter-floor platform velocity from a reset
    # teleport contaminating an independent terrain scenario.
    f.queue_free()
    target.queue_free()
    await process_frame
    f = F.new()
    f.character_id = "doge_man"
    f.player_index = 3
    f.position = pos
    stage.add_child(f)
    target = F.new()
    target.character_id = "doge_man"
    target.player_index = 4
    target.position = other
    stage.add_child(target)
    f.facing = face
    await step(10)
func launch(power := 1.0) -> void:
    f.start_special(Vector2.DOWN)
    f.advance_charge(2.25*power)
    f.release_special()
func run() -> void:
    stage = Node3D.new()
    root.add_child(stage)
    floor_at(Vector3(0,-0.5,0),Vector3(16,1,4))
    floor_at(Vector3(0,2.75,0),Vector3(4,0.5,4),true)
    f = F.new()
    f.character_id = "doge_man"
    f.player_index = 3
    stage.add_child(f)
    target = F.new()
    target.character_id = "doge_man"
    target.player_index = 4
    stage.add_child(target)
    for face in [1,-1]:
        await reset(Vector3(-2*face,0,0),face,Vector3(0,0,0))
        launch()
        var hit := false
        for i in 55:
            await step(1)
            if target.damage_percent>0 and not hit:
                hit = true
                check(target.velocity.y>absf(target.velocity.x)*3,"mostly upward actual capsule contact")
        check(target.damage_percent==14,"one 14 damage packet in rush face "+str(face))
        for y in [0,3]:
            await reset(Vector3(6*face if y==0 else 0,y,0),face,Vector3(-6*face,0,0))
            launch()
            for i in 55:
                await step(1)
                check(f.is_grounded(),"edge retains terrain floor y "+str(y))
                check(absf(f.position.x) <= (1.431 if y==3 else 7.431),"whole capsule edge margin: actual .55 radius + .02")
            check(f.doge_ground_rush.phase=="idle","bounded recovery after edge")
    for face in [1,-1]:
        var wall := floor_at(Vector3(2*face,1.5,0),Vector3(0.2,3,4))
        await reset(Vector3.ZERO,face,Vector3(2.6*face,0,0))
        launch()
        await step(70)
        check(f.position.x*face<1.6,"wall blocks rush in both facings")
        check(target.damage_percent==0,"no hit through terrain wall")
        wall.queue_free()
        await process_frame
    print("GROUND_RUSH_SAFETY_CHECKS ",checks," failures ",failures)
    stage.queue_free()
    await process_frame
    if not failures: print("PASS grounded rush capsules upward once edges platforms walls")
    quit(1 if failures else 0)
