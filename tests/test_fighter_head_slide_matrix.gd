extends SceneTree
const F = preload("res://scripts/fighter.gd")
const OUT = "res://.verification/evidence/fighter_head_slide/"
var failures: Array = []
var cases: Array = []
class Driver extends F:
    var axis := 0
    func read_controls(_delta: float) -> Dictionary:
        return {"left":axis < 0,"right":axis > 0,"up":false,"down":false,"jump":false,"attack":false,"special":false,"shield":false}
func _initialize(): call_deferred("run")
func step():
    await physics_frame
    await process_frame
func check(ok: bool, message: String):
    if not ok:
        failures.append(message)
        print("FAIL: "+message)
func block(world, pos, size):
    var b = StaticBody3D.new()
    var c = CollisionShape3D.new()
    var s = BoxShape3D.new()
    s.size = size
    c.shape = s
    b.add_child(c)
    b.position = pos
    world.add_child(b)
    return b
func actor(world, id, pos):
    var f = Driver.new()
    f.character_id = id
    f.player_index = 3
    f.position = pos
    world.add_child(f)
    return f
func run():
    var world = Node3D.new()
    root.add_child(world)
    block(world,Vector3(0,-0.5,0),Vector3(24,1,6))
    for id in ["teknium","turbofit","doge_man","ggb","ice_mage","witcheer"]:
        for offset in [-0.2,0.2]:
            var bottom = actor(world,id,Vector3.ZERO)
            var top = actor(world,id,Vector3(4,0.1,0))
            top.team_id = 1
            bottom.team_id = 1
            for i in 15: await step()
            top.reset_fighter(Vector3(offset,3.5,0))
            top.jumps_used = 2
            top.recovery_spent = true
            top.tackle_spent = true
            top.float_remaining = 0.2
            var head_seen = false
            var false_ground = false
            var false_reset = false
            var max_vx = 0.0
            var max_z = 0.0
            var first_slip = 0.0
            var landed = -1
            for i in 130:
                await step()
                max_vx = maxf(max_vx,absf(top.velocity.x))
                max_z = maxf(max_z,absf(top.position.z))
                for j in top.get_slide_collision_count():
                    var c = top.get_slide_collision(j)
                    if c.get_collider() == bottom and c.get_normal().y > 0.7:
                        head_seen = true
                        false_ground = false_ground or top.is_grounded()
                        false_reset = false_reset or top.jumps_used != 2 or not top.recovery_spent or not top.tackle_spent or top.float_remaining > 0.2
                        if first_slip == 0 and absf(top.velocity.x) > 0.01: first_slip = signf(top.velocity.x)
                if head_seen and top.is_grounded():
                    landed = i
                    break
            var label = id+" offset "+str(offset)
            check(head_seen and not false_ground and not false_reset,label+" head is never gameplay ground/resources")
            check(landed >= 0 and top.position.y < 0.1,label+" escapes to terrain")
            check(first_slip == signf(offset),label+" slips toward nearest side")
            check(max_z < 0.001 and max_vx <= 2.0,label+" no depth drift or fling")
            check(top.jumps_used == 0 and not top.recovery_spent and not top.tackle_spent,label+" terrain restores resources")
            cases.append({"case":label,"head_seen":head_seen,"false_ground":false_ground,"false_reset":false_reset,"landed_frame":landed,"max_vx":max_vx,"max_z":max_z,"first_slip":first_slip})
            top.queue_free()
            bottom.queue_free()
            await process_frame
    # Full production movement input into another grounded capsule stays blocked.
    var bottom = actor(world,"teknium",Vector3.ZERO)
    var top = actor(world,"turbofit",Vector3(-3,0.1,0))
    for i in 20: await step()
    top.axis = 1
    var mixed = false
    for i in 75:
        await step()
        check(top.position.x < bottom.position.x-1.05,"grounded capsules cannot cross")
        if top.get_slide_collision_count() >= 2:
            mixed = mixed or top.is_grounded()
    check(mixed,"real terrain remains grounded alongside fighter side collision")
    check(absf(bottom.position.x) < 0.02,"head rule does not introduce general ground pushing")
    top.axis = 0
    top.reset_fighter(Vector3(0,3.5,0))
    for i in 35: await step()
    check(top._head_slip_direction != 0,"contact episode started before lifecycle test")
    top.controls_enabled = false
    check(top._head_slip_direction == 0 and not top.is_grounded(),"setup/winner disable clears contact state")
    top.reset_fighter(Vector3(4,4,0))
    check(top._head_slip_direction == 0 and not top.is_grounded(),"reset invalidates old contacts")
    top.lose_stock()
    check(top._head_slip_direction == 0 and not top.is_grounded(),"stock loss invalidates contacts")
    top.queue_free()
    bottom.queue_free()
    await process_frame
    # Three same-team bodies must not maintain a tower.
    var tower: Array = []
    for i in 3:
        var f = actor(world,"probe",Vector3(i*3,0.1,0))
        f.team_id = 1
        tower.append(f)
    for i in 20: await step()
    tower[1].reset_fighter(Vector3(0,2,0))
    tower[2].reset_fighter(Vector3(0,4,0))
    for i in 230: await step()
    for f in tower:
        check(f.is_grounded() and f.position.y < 0.1,"three-body stack disperses onto terrain")
    cases.append({"case":"body_blocking_mixed_floor_lifecycle_three_stack","mixed_floor":mixed})
    FileAccess.open(OUT+"head_matrix_latest.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"cases":cases},"  "))
    world.queue_free()
    await process_frame
    if failures.is_empty(): print("PASS: roster/team offsets, bounded slip, real floor, side blocking, lifecycle, three-stack")
    quit(0 if failures.is_empty() else 1)
