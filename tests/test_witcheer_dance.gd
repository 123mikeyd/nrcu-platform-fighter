extends SceneTree
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,msg:String):
    if not ok:failures+=1;printerr("FAIL: "+msg)
func run():
    var f=load("res://scripts/fighter.gd").new();f.character_id="witcheer";root.add_child(f);f.set_physics_process(false)
    var enemy=load("res://scripts/fighter.gd").new();root.add_child(enemy);enemy.set_physics_process(false);enemy.position=Vector3(3,0,0)
    f.damage_percent=30;f.start_special(Vector2.DOWN)
    check(f.witcheer_clip=="Celebration","S+G finite celebration route")
    if f.witcheer_clip=="Celebration":
        var shot=load("res://scripts/projectile.gd").new();shot.source=enemy;root.add_child(shot);shot.set_physics_process(false)
        f._tick_witcheer(0.5);shot._hit_target(f)
        check(f.damage_percent==19,"active enemy bolt heals actual 11 damage")
        check(shot.is_queued_for_deletion(),"consumed projectile deleted immediately")
        shot._hit_target(f);check(f.damage_percent==19,"cannot double heal consumed bolt")
        f._tick_witcheer(2);check(f.witcheer_clip.is_empty(),"dance ends")
        f.reset_fighter(Vector3.ZERO,true);f.damage_percent=30;f.start_special(Vector2.ZERO);f._tick_witcheer(0.5)
        check(f.witcheer_clip=="Celebration","plain G shares source celebration")
        var plain=load("res://scripts/projectile.gd").new();plain.source=enemy;root.add_child(plain);plain.set_physics_process(false);plain._hit_target(f)
        check(f.damage_percent==41,"plain G does not absorb")
        check(enemy.damage_percent==0,"celebration never damages enemies")
        plain.queue_free()
    f.queue_free();enemy.queue_free();await process_frame
    print("PASS dance contact" if failures==0 else "dance failures %d"%failures);quit(0 if failures==0 else 1)
