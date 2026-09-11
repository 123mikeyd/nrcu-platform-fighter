extends SceneTree
const FighterScript = preload("res://scripts/fighter.gd")
const OUT = "res://.verification/evidence/fighter_head_slide/"
var failures: Array = []
var samples: Array = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures.append(message)
        print("FAIL: " + message)
func step():
    await physics_frame
    await process_frame
func run():
    DirAccess.make_dir_recursive_absolute(OUT)
    var world = Node3D.new()
    root.add_child(world)
    var floor_body = StaticBody3D.new()
    var shape = CollisionShape3D.new()
    var box = BoxShape3D.new()
    box.size = Vector3(24, 1, 6)
    shape.shape = box
    floor_body.add_child(shape)
    floor_body.position.y = -0.5
    world.add_child(floor_body)
    var bottom = FighterScript.new()
    bottom.character_id = "probe"
    bottom.player_index = 3
    world.add_child(bottom)
    var top = FighterScript.new()
    top.character_id = "probe"
    top.player_index = 4
    top.position = Vector3(4, 0.1, 0)
    world.add_child(top)
    for i in 30: await step()
    top.reset_fighter(Vector3(0, 3.5, 0))
    top.jumps_used = 2
    top.recovery_spent = true
    top.tackle_spent = true
    top.float_remaining = 0.2
    var head_seen = false
    var false_reset = false
    for i in 150:
        await step()
        var normals: Array = []
        for j in top.get_slide_collision_count():
            var c = top.get_slide_collision(j)
            if c.get_collider() == bottom:
                normals.append([c.get_normal().x, c.get_normal().y, c.get_normal().z])
                if c.get_normal().y > 0.7:
                    head_seen = true
                    false_reset = false_reset or top.jumps_used != 2 or not top.recovery_spent or not top.tackle_spent or top.float_remaining > 0.2
        samples.append({"frame":i,"x":top.position.x,"y":top.position.y,"z":top.position.z,"vx":top.velocity.x,"native_floor":top.is_on_floor(),"grounded":top.is_grounded(),"normals":normals,"jumps":top.jumps_used})
    check(head_seen, "physical capsule-top contact reproduced")
    check(not false_reset, "fighter head must not restore airborne resources")
    check(top.position.y < 0.1 and absf(top.position.x-bottom.position.x) > 1.0, "exact-center landing gently escapes head and reaches real floor")
    check(top.position.x > bottom.position.x, "exact-center tie deterministically escapes world +X")
    var report = {"failures":failures,"samples":samples}
    FileAccess.open(OUT + "head_slide_latest.json", FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
    world.queue_free()
    await process_frame
    if failures.is_empty(): print("PASS: fighter head slip and no resource reset")
    quit(0 if failures.is_empty() else 1)
