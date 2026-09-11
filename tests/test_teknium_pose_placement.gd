extends SceneTree
const Bounds=preload("res://tests/posed_character_bounds.gd")
func _initialize():call_deferred("run")
func run():
    var f=load("res://scripts/fighter.gd").new();root.add_child(f);f.set_physics_process(false)
    var v=f.get_node("VisualRoot/TekniumVisual");var failed=false
    var cases={"Idle":[Vector3.ZERO,false,false,""],"Walk":[Vector3(2,0,0),false,false,""],"Run":[Vector3(5,0,0),false,false,""],"Block":[Vector3.ZERO,false,true,""],"Punch":[Vector3.ZERO,false,false,"SIDE STRIKE"],"Kick":[Vector3.ZERO,false,false,"LOW SWEEP"],"Hit":[Vector3.ZERO,true,false,""]}
    for clip in cases:
        var c=cases[clip];var lo=INF;var hi=-INF
        for i in 61:
            v.sync_pose(true,c[0],c[1],c[2],c[3],1,0)
            var ap=v.animation_player;ap.play(clip,0);ap.seek(ap.get_animation(clip).length*i/60.0,true);ap.pause()
            for sk in v.find_children("*","Skeleton3D",true,false):sk.force_update_all_bone_transforms()
            var y=Bounds.new().bounds(v).values()[0].min[1];lo=minf(lo,y);hi=maxf(hi,y)
        var ok=lo>=-0.003 and lo<0.01 and hi<(0.18 if clip=="Run" else 0.05)
        print(("PASS: " if ok else "FAIL: "),clip," posed floor range ",lo," .. ",hi)
        failed=failed or not ok
    # No grounding system may follow the floor in the air or relocate magic hands.
    v.begin_jump();v.sync_pose(false,Vector3(0,5,0),false,false,"",1,0.2)
    if v.position.y!=0:failed=true;print("FAIL: airborne authored placement changed")
    v.magic_pose("ForcePush",0.2,1)
    if v.position.y!=0:failed=true;print("FAIL: approved magic origin changed")
    f.queue_free();await process_frame
    quit(1 if failed else 0)
