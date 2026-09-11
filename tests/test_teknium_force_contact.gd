extends SceneTree
var failures:=0
func check(ok,message):
    if not ok:failures+=1;print("FAIL: ",message)
func _initialize():call_deferred("run")
func make_fighter(pos:Vector3):
    var f=load("res://scripts/fighter.gd").new();root.add_child(f);f.set_physics_process(false);f.position=pos;return f
func run():
    for direction in [1.0,-1.0]:
        var f=make_fighter(Vector3.ZERO);var v=make_fighter(Vector3(direction*3,0,0))
        await physics_frame;await process_frame
        f.start_special(Vector2(direction,0));f.teknium_magic.tick(0.25)
        var shots=get_nodes_in_group("projectiles");var shot=shots[0];shot.set_physics_process(false)
        check(v.damage_percent==0,"no spawn damage")
        for i in 15:
            shot._physics_process(1.0/120.0)
            if shot.is_queued_for_deletion():break
        check(v.damage_percent==8,"real capsule contact both facing "+str(direction))
        check(shot.is_queued_for_deletion(),"consumed on subsequent real contact")
        f.queue_free();v.queue_free();shot.queue_free();await process_frame
    if failures==0:print("PASS: real force hand origin to hurtcapsules both facings")
    quit(0 if failures==0 else 1)
