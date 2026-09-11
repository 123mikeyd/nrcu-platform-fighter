extends SceneTree
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,message:String):
    if not ok:
        failures+=1
        printerr("FAIL: "+message)
func run():
    var f=load("res://scripts/fighter.gd").new()
    f.character_id="ice_mage"
    root.add_child(f)
    f.set_physics_process(false)
    var target=load("res://scripts/fighter.gd").new()
    target.character_id="ggb"
    root.add_child(target)
    target.set_physics_process(false)
    for case in [[Vector2.RIGHT,false,Vector3(1.3,0,0),"SIDE STRIKE"],[Vector2.LEFT,false,Vector3(-1.3,0,0),"SIDE STRIKE"],[Vector2.UP,false,Vector3(0,1.3,0),"UPPERCUT"],[Vector2.DOWN,false,Vector3(1.3,0,0),"LOW SWEEP"],[Vector2.DOWN,true,Vector3(0,-1.3,0),"DOWN STRIKE"],[Vector2.UP,true,Vector3(0,1.3,0),"UP AIR"]]:
        f.reset_fighter(Vector3.ZERO)
        f.facing=1
        target.reset_fighter(case[2])
        f.basic_attack(case[0],case[1])
        check(f.last_move==case[3] and f.ice_attack_clip=="IceStrike","preserved directional route "+case[3])
        f._tick_character_move(0.19)
        check(target.damage_percent==0,"directional strike windup")
        f._tick_character_move(0.01)
        check(target.damage_percent==8,"directional strike connects "+case[3])
        f._tick_character_move(0.2)
        check(target.damage_percent==8,"single impact, no repeated damage")
    f.reset_fighter(Vector3.ZERO)
    f.start_special(Vector2.UP)
    check(f.last_move=="FROST RISE" and f.recovery_spent and f.velocity.y==13.5,"up G retains once-airtime rising recovery")
    f._tick_character_move(0.2)
    check(get_nodes_in_group("projectiles").is_empty(),"up recovery does not also fire bolt")
    for aim in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.DOWN]:
        f.reset_fighter(Vector3.ZERO)
        f.start_special(aim)
        check(f.last_move=="FROST BOLT" and f.ice_attack_clip=="IceCast","neutral/side/down G consistently casts")
        f.receive_hit(1,Vector3.LEFT,1)
        f._tick_character_move(0.5)
        check(get_nodes_in_group("projectiles").is_empty(),"interrupted windup cannot spawn delayed bolt")
    f.reset_fighter(Vector3.ZERO)
    f.start_special(Vector2.ZERO)
    f.apply_freeze(target)
    f._tick_character_move(0.5)
    check(f.ice_attack_clip.is_empty() and get_nodes_in_group("projectiles").is_empty(),"freeze cancels pending own cast")
    f.queue_free()
    target.queue_free()
    await process_frame
    if failures==0:print("PASS: left/right/up/low/aerial-down single-impact strikes, rising recovery, neutral/side/down casting, damage/freeze windup cancellation")
    quit(1 if failures else 0)
