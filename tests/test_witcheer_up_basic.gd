extends SceneTree
var fails:=0
func _initialize():call_deferred("run")
func ck(ok:bool,msg:String):
    if not ok:fails+=1;printerr("FAIL: "+msg)
func run():
    var f=load("res://scripts/fighter.gd").new();f.character_id="witcheer";root.add_child(f);f.set_physics_process(false)
    var t=load("res://scripts/fighter.gd").new();root.add_child(t);t.set_physics_process(false)
    f.position=Vector3(0,4,0);t.position=Vector3(0.4,5.4,0);f.velocity.y=-2;f.jumps_used=1
    f.basic_attack(Vector2.UP,true);ck(f.witcheer_clip=="SpinRise","air W+F upward SpinRise basic")
    ck(f.velocity.y==-2 and f.jumps_used==1 and not f.recovery_spent,"up basic no lift/no recovery resource change")
    if f.witcheer_clip=="SpinRise":
        f._tick_witcheer(12.8/24-0.001);ck(t.damage_percent==0,"no pre-source-event upward hit")
        f._tick_witcheer(0.001);ck(t.damage_percent==11,"upward target hit at source27.2")
        f._tick_witcheer(0.1);ck(t.damage_percent==11,"one upward strike")
    f.reset_fighter(Vector3(0,4,0),true);t.reset_fighter(Vector3(0,2.5,0),true)
    f.basic_attack(Vector2.UP,true);f._tick_witcheer(0.54);ck(t.damage_percent==0,"up basic excludes target below")
    f.reset_fighter(Vector3.ZERO,true);f.basic_attack(Vector2.DOWN,false);ck(f.witcheer_clip=="CaneSweep","ground S+F preserved")
    f.reset_fighter(Vector3.ZERO,true);f.basic_attack(Vector2.UP,false);ck(f.witcheer_clip=="HighKick","ground W+F preserved")
    f.reset_fighter(Vector3.ZERO,true);f.basic_attack(Vector2.DOWN,true);ck(f.witcheer_clip=="JumpPunch","air S+F preserved")
    f.queue_free();t.queue_free();await process_frame
    print("PASS up basic revision" if fails==0 else "up failures %d"%fails);quit(0 if fails==0 else 1)
