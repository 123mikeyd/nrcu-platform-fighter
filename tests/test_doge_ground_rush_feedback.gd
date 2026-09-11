extends "res://tests/test_doge_ground_rush_safety.gd"
const OUT="res://.verification/evidence/doge_ground_rush/"
func key(code:int, down:bool) -> void:
    var e:=InputEventKey.new()
    e.keycode=code
    e.pressed=down
    Input.parse_input_event(e)
    Input.flush_buffered_events()
func bones() -> Array:
    var v=f.get_node("VisualRoot/DogeVisual")
    var sk:Skeleton3D=v.model.find_children("*","Skeleton3D",true,false)[0]
    sk.force_update_all_bone_transforms()
    var result:Array=[]
    for i in sk.get_bone_count():result.append(sk.get_bone_global_pose(i).origin)
    return result
func run() -> void:
    stage=Node3D.new()
    root.add_child(stage)
    floor_at(Vector3(0,-0.5,0),Vector3(30,1,4))
    f=F.new()
    target=F.new()
    stage.add_child(f)
    stage.add_child(target)
    await reset(Vector3(-9,0,0),1,Vector3(12,0,0))
    f.player_index=1
    key(KEY_S,true)
    key(KEY_G,true)
    await step(160)
    var a:=bones()
    await step(20)
    var b:=bones()
    var change:=0.0
    for i in a.size():change=maxf(change,a[i].distance_to(b[i]))
    check(change>0.01,"charge animation continues after capped 100 percent")
    check(f.charging and f.charge_time==2.25,"meter cap holds without auto-release")
    var clock:float=f.doge_ground_rush.elapsed
    var view=f.get_node("VisualRoot/DogeVisual")
    f.doge_ground_rush.elapsed=4.5
    f.doge_ground_rush.present(view,0)
    var seam:=bones()
    f.doge_ground_rush.elapsed=13.5
    f.doge_ground_rush.present(view,0)
    var repeat:=bones()
    for i in seam.size():check(seam[i].distance_to(repeat[i])<0.00001,"three charge cycles no skeletal/root drift")
    f.doge_ground_rush.elapsed=2.249
    f.doge_ground_rush.present(view,0)
    var turn_a:=bones()
    f.doge_ground_rush.elapsed=2.251
    f.doge_ground_rush.present(view,0)
    var turn_b:=bones()
    for i in turn_a.size():check(turn_a[i].distance_to(turn_b[i])<0.00001,"charge loop smooth source-pose turnaround")
    f.doge_ground_rush.elapsed=clock
    key(KEY_G,false)
    key(KEY_S,false)
    var runs:Array=[]
    for power in [0.0,0.5,1.0]:
        await reset(Vector3(-9,0,0),1,Vector3(12,0,0))
        var start_x:float=f.position.x
        launch(power)
        var peak:=0.0
        var rush_ticks:=0
        var brake_speeds:Array=[]
        var trace:Array=[]
        for i in 100:
            await step(1)
            var phase:String=f.doge_ground_rush.phase
            peak=maxf(peak,absf(f.velocity.x))
            if phase=="rush":rush_ticks+=1
            if phase=="recovery":brake_speeds.append(absf(f.velocity.x))
            trace.append({"tick":i,"phase":phase,"x":f.position.x,"speed":absf(f.velocity.x)})
            if phase=="idle":break
        check(brake_speeds.size()>5 and brake_speeds[0]>1,"rush enters moving brake, not instantaneous stop")
        if brake_speeds.size()>1:
            check(brake_speeds[-1]<brake_speeds[0]*0.2,"brake decelerates near zero")
            for i in range(1,brake_speeds.size()):check(brake_speeds[i]<=brake_speeds[i-1]+0.001,"monotonic smooth brake")
        for i in range(1,trace.size()):
            check(trace[i-1].speed-trace[i].speed<=peak*0.12+0.01,"no partial-frame velocity snap at rush/brake boundary")
        runs.append({"power":power,"distance":f.position.x-start_x,"peak":peak,"rush_ticks":rush_ticks,"trace":trace})
    for i in range(1,3):
        check(runs[i].distance>runs[i-1].distance+2,"charge meaningfully scales distance")
        check(runs[i].peak>runs[i-1].peak+3,"charge meaningfully scales speed")
        check(runs[i].rush_ticks>runs[i-1].rush_ticks,"charge also scales rush duration")
    check(runs[2].distance>10,"full charge substantially farther than previous six units")
    await reset(Vector3(-9,0,0),1,Vector3(-1.32,0,0))
    target.set_physics_process(false)
    launch(0.5)
    await step(70)
    check(target.damage_percent==0,"fractional final rush tick cannot extend damage into brake travel")
    var file:=FileAccess.open(OUT+"feedback_physics.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"pose_change_after_cap":change,"runs":runs,"failures":failures},"  "))
    print("FEEDBACK_RUNS ",runs.map(func(r):return [r.power,r.distance,r.peak,r.rush_ticks]))
    stage.queue_free()
    await process_frame
    if not failures:print("PASS ongoing charge animation / low mid full speed and distance / smooth brake")
    quit(1 if failures else 0)
