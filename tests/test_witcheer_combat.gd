extends SceneTree
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func check(ok: bool,msg: String):
    checks+=1
    if not ok:failures+=1;printerr("FAIL: "+msg)
func run():
    var f=load("res://scripts/fighter.gd").new();f.character_id="witcheer"
    var v=load("res://scripts/fighter.gd").new();v.character_id="witcheer"
    root.add_child(f);root.add_child(v);f.set_physics_process(false);v.set_physics_process(false)
    var visual=f.get_node("VisualRoot/WitcheerVisual")
    var sk: Skeleton3D=visual.model.find_children("*","Skeleton3D",true,false)[0]
    for clip in f.witcheer_moves:
        var duration: float=f.witcheer_moves[clip].duration
        var first:=Vector3.ZERO
        for i in 11:
            visual.show_move(clip,duration*i/10.0,-1)
            sk.force_update_all_bone_transforms()
            var hips: Vector3=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("Hips")).origin
            if i==0:first=hips
            check(Vector2(hips.x,hips.z).distance_to(Vector2(first.x,first.z))<0.00001,"world root horizontally anchored "+clip)
            if clip in ["AirSwim","SpinRise","JumpPunch"]:check(absf(hips.y-first.y)<0.00001,"controller owns vertical travel "+clip)
    f.reset_fighter(Vector3.ZERO,true);v.reset_fighter(Vector3(5,0,0),true)
    f.basic_attack(Vector2.ZERO,false);f._tick_witcheer(float(f.witcheer_moves.HighKick.contact_time))
    check(visual.accent.visible,"contact accent exists before freeze")
    f.apply_freeze(v)
    check(not visual.accent.visible,"freeze clears contact accent immediately")
    for clip in f.witcheer_moves:
        f.reset_fighter(Vector3.ZERO,true);v.reset_fighter(Vector3(1.4,0,0),true)
        f._start_witcheer(clip);f.recovery_spent=true
        f.receive_hit(2,Vector3.RIGHT,1)
        check(f.witcheer_clip.is_empty() and f.recovery_spent,"hit cancel never refunds recovery "+clip)
        f._tick_witcheer(3)
        check(v.damage_percent==0 and get_nodes_in_group("projectiles").is_empty(),"no pending hit/spawn after cancel "+clip)
    for status in ["freeze","grab","hit","setup"]:
        f.reset_fighter(Vector3.ZERO,true);v.reset_fighter(Vector3(1.4,0,0),true)
        match status:
            "freeze":f.apply_freeze(v)
            "grab":f.caught_by=v
            "hit":f.hitstun=1
            "setup":f.controls_enabled=false
        f.basic_attack(Vector2.ZERO,false);f.start_special(Vector2.ZERO)
        check(f.witcheer_clip.is_empty(),"direct attack APIs blocked by "+status)
        f.caught_by=null
    f.reset_fighter(Vector3.ZERO,true);v.reset_fighter(Vector3(1.4,2,0),true)
    f.basic_attack(Vector2.DOWN,false);f._tick_witcheer(0.5)
    check(v.damage_percent==0,"low sweep intentionally misses above")
    f.reset_fighter(Vector3.ZERO,true);f.recovery_spent=true
    f.start_special(Vector2.UP);check(f.witcheer_clip.is_empty(),"spent recovery blocked")
    f.start_special(Vector2.RIGHT);check(f.witcheer_clip=="Toss","toss allowed after spent swim without restoring resource")
    check(f.recovery_spent,"toss does not refund swim")
    f.reset_fighter(Vector3.ZERO,true);f.tackle_spent=true;f.start_special(Vector2.UP)
    check(f.witcheer_clip=="AirSwim","swim uses recovery budget, not former side-special budget")
    f.reset_fighter(Vector3.ZERO,true)
    check(not f.recovery_spent and not f.tackle_spent and f.witcheer_clip.is_empty(),"reset restores complete kit")
    check(f.teknium_magic==null and f.sound_orb_time==0 and f.torpedo_phase=="idle" and not f.drop_committed,"other unique kits not borrowed")
    f.queue_free();v.queue_free();await process_frame
    print(("PASS " if failures==0 else "FAIL ")+"WITCHEER COMBAT CONTRACT: %d checks, %d failures"%[checks,failures])
    quit(0 if failures==0 else 1)
