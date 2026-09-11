extends SceneTree
const Bounds=preload("res://tests/posed_character_bounds.gd")
var fails=[]
func _initialize():call_deferred("run")
func span(v):
    var b=Bounds.new().bounds(v);var lo=INF;var hi=-INF
    for entry in b.values():lo=minf(lo,entry.min[1]);hi=maxf(hi,entry.max[1])
    return Vector2(lo,hi)
func check(ok,label):
    print(("PASS: " if ok else "FAIL: ")+label)
    if not ok:fails.append(label)
func run():
    var actors={};var heights={}
    for id in ["teknium","doge_man","ggb","turbofit","witcheer"]:
        var f=load("res://scripts/fighter.gd").new();f.character_id=id;root.add_child(f);f.set_physics_process(false);actors[id]=f
        var v=f.get_node("VisualRoot").get_child(0)
        for ap in v.find_children("*","AnimationPlayer",true,false):
            ap.play("Run" if id=="witcheer" else "Idle",0);ap.seek(0,true);ap.pause()
        for sk in v.find_children("*","Skeleton3D",true,false):sk.force_update_all_bone_transforms()
        var b=span(v);heights[id]=b.y-b.x
        print("HEIGHT ",id," ",heights[id]," sole=",b.x)
    var tek=actors.teknium.get_node("VisualRoot/TekniumVisual")
    for i in 9:
        tek.sync_pose(true,Vector3.ZERO,false,false,"",1.0,0)
        tek.animation_player.play("Idle",0);tek.animation_player.seek(tek.animation_player.get_animation("Idle").length*i/9.0,true);tek.animation_player.pause()
        for sk in tek.find_children("*","Skeleton3D",true,false):sk.force_update_all_bone_transforms()
        var b=span(tek)
        check(b.x>=-0.003 and b.x<0.01,"Teknium posed idle sole touches floor "+str(i)+" gap="+str(b.x))
    tek.sync_pose(true,Vector3.ZERO,false,false,"",1.0,1.0/60.0)
    check(span(tek).x<0.01,"first advancing Idle frame must not revert a frozen grounded placement")
    var shortest=INF
    for id in heights:
        if id!="ggb":shortest=minf(shortest,heights[id])
    # Latest Desktop/3D Stuff/Roots.blend explicit GGB and Tek evaluated heights:
    # 0.9131460189819336 / 1.8995859622955322. Supersedes the older attachment.
    check(absf(heights.ggb/heights.teknium-0.48070792115059274)<0.001,"GGB full silhouette matches latest named Roots.blend relative size")
    for f in actors.values():f.queue_free()
    await process_frame
    quit(1 if not fails.is_empty() else 0)
