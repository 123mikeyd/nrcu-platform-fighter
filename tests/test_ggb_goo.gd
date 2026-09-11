extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func frames(n: int):
    for i in n:
        await physics_frame
        await process_frame
func run():
    var arena=load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    var slots=load("res://scripts/match_config.gd").default_slots()
    slots[0].character="ggb"
    slots[2].kind="empty";slots[3].kind="empty"
    arena.start_match(slots,false)
    arena._physics_process(arena.ready_remaining) # Advance the real Ready gate before combat fixtures.
    var f=arena.fighters[0]
    var enemy=arena.fighters[1]
    enemy.set_physics_process(false);enemy.position=Vector3(12,0,0)
    f.reset_fighter(Vector3(0,0.1,0),true)
    await frames(12)
    f.start_special(Vector2.RIGHT)
    var p=get_nodes_in_group("projectiles")[0]
    var start:Vector3=p.position
    await frames(10)
    check(is_instance_valid(p) and p.position.y>start.y,"goo arcs upward instead of horizontal stage-wide shot")
    await frames(50)
    var puddles=get_nodes_in_group("goo_puddles")
    check(puddles.size()==1,"real stage impact creates one sticky puddle")
    if puddles.size()==1:
        var pool=puddles[0]
        check(pool.position.x-start.x<4.6 and absf(pool.position.y)<0.08,"short throw lands on physical stage top")
        enemy.reset_fighter(pool.position+Vector3(0,0.1,0),true)
        enemy.control_type="keyboard";enemy.set_physics_process(true)
        await frames(12)
        if enemy.has_method("ground_speed_multiplier"):
            check(is_equal_approx(enemy.ground_speed_multiplier(),0.65),"grounded enemy slowed 35 percent")
            enemy.position.x+=4
            check(enemy.ground_speed_multiplier()==1.0,"leaving puddle clears slow immediately")
        else: check(false,"fighter exposes contact-based ground speed multiplier")
    await frames(190)
    check(get_nodes_in_group("goo_puddles").is_empty(),"puddle expires")
    arena.queue_free();await process_frame
    if failures==0: print("PASS: short arcing goo, real floor puddle, grounded slow and recovery/expiry")
    quit(1 if failures else 0)
