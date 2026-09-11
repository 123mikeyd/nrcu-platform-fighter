extends SceneTree
const F = preload("res://scripts/fighter.gd")
const OUT = "res://.verification/evidence/fighter_head_slide/"
func _initialize(): call_deferred("run")
func step():
    await physics_frame
    await process_frame
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
func run():
    var world = Node3D.new()
    root.add_child(world)
    block(world,Vector3(0,-0.5,0),Vector3(24,1,6))
    block(world,Vector3(0.95,3,0),Vector3(0.2,6,6))
    var bottom = F.new()
    bottom.character_id = "probe"
    bottom.player_index = 3
    world.add_child(bottom)
    var top = F.new()
    top.character_id = "probe"
    top.player_index = 4
    top.position = Vector3(-4,0.1,0)
    world.add_child(top)
    for i in 20: await step()
    top.reset_fighter(Vector3(0,3.5,0))
    var samples: Array = []
    var crossed = false
    for i in 180:
        await step()
        crossed = crossed or top.position.x > 0.31
        samples.append({"frame":i,"x":top.position.x,"y":top.position.y,"z":top.position.z,"grounded":top.is_grounded()})
    var ok = not crossed and top.is_grounded() and top.position.y < 0.1 and top.position.x < -1
    FileAccess.open(OUT+"head_wall_latest.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"samples":samples},"  "))
    print("PASS: blocked head-slip reverses to free side, never crosses wall" if ok else "FAIL: wall must not trap head-standing or permit tunnelling")
    world.queue_free()
    await process_frame
    quit(0 if ok else 1)
