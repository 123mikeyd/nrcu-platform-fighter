extends SceneTree
func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> bool:
    if not ok: printerr("FAIL: "+message); quit(1)
    return ok
func run():
    var path = "res://assets/witcheer/witcheer_run.glb"
    if not check(ResourceLoader.exists(path), "approved Witcheer Run asset missing"): return
    var model = load(path).instantiate()
    root.add_child(model)
    var players = model.find_children("*", "AnimationPlayer", true, false)
    if not check(players.size()==1,"one animation player"): return
    var player = players[0]
    var clips = Array(player.get_animation_list())
    clips.erase("RESET")
    if not check(clips==["AirSwim","CaneSweep","Celebration","Electrocution","HighKick","JumpPunch","Run","SpinRise","Toss"], "unchanged eight clips plus shared Electrocution reaction"): return
    if not check(absf(player.get_animation("Electrocution").length-57.0/24.0)<0.0001,"exact shared reaction source duration"): return
    var timings=JSON.parse_string(FileAccess.get_file_as_string("res://assets/witcheer/move_manifest.json")).moves
    for clip in timings:
        if not check(absf(player.get_animation(clip).length-float(timings[clip].duration))<0.0001,"exact clip duration "+clip):return
    if not check(absf(player.get_animation("Run").length - 15.2/24.0)<0.0001,"fractional endpoints and source speed"): return
    var skeleton = model.find_children("*","Skeleton3D",true,false)[0]
    if not check(skeleton.get_bone_count()==24,"source skeleton preserved"): return
    var meshes=model.find_children("*","MeshInstance3D",true,false)
    if not check(meshes.size()==1,"single approved duck mesh"): return
    var mat=meshes[0].get_active_material(0)
    if not check(mat.albedo_texture!=null and mat.albedo_texture.get_size()==Vector2(4096,4096),"packed original paint"): return
    player.play("Run");player.seek(0,true)
    var bone=skeleton.find_bone("LeftLeg")
    var first=skeleton.get_bone_pose_rotation(bone)
    player.seek(0.2,true)
    if not check(first.angle_to(skeleton.get_bone_pose_rotation(bone))>0.1,"Run genuinely moves source bones"): return
    model.queue_free()
    await process_frame
    print("PASS: Witcheer source-backed move asset, 24 bones, 4096 paint, exact 0.633333s source clock and animated skeleton")
    quit()
