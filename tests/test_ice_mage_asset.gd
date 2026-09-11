extends SceneTree
func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> bool:
    if not ok:
        push_error("FAIL: " + message)
        quit(1)
    return ok
func run():
    var path = "res://assets/ice_mage/ice_mage_animations.glb"
    if not check(ResourceLoader.exists(path), "Ice Mage animated asset missing"): return
    var model = load(path).instantiate()
    root.add_child(model)
    var players = model.find_children("*","AnimationPlayer",true,false)
    var rigs = model.find_children("*","Skeleton3D",true,false)
    var meshes = model.find_children("*","MeshInstance3D",true,false)
    if not check(players.size()==1 and rigs.size()==1 and meshes.size()==1,"one mesh, rig and player"): return
    var rig: Skeleton3D = rigs[0]
    var player: AnimationPlayer = players[0]
    if not check(rig.get_bone_count()==24,"24-bone Meshy rig"): return
    var triangles = 0
    for mesh in meshes:
        for surface in mesh.mesh.get_surface_count():
            var arrays = mesh.mesh.surface_get_arrays(surface)
            triangles += arrays[Mesh.ARRAY_INDEX].size()/3
            var material = mesh.get_active_material(surface)
            if not check(material.albedo_texture != null and material.albedo_texture.get_size()==Vector2(4096,4096),"approved 4k skin texture"): return
    if not check(triangles>=20000 and triangles<=40000,"20–40k triangle budget"): return
    for clip in ["Idle","Walk","Run"]:
        if not check(player.has_animation(clip),"real "+clip+" available"): return
        var anim = player.get_animation(clip)
        if not check(anim.length>0.5,"nontrivial duration "+clip): return
        player.play(clip)
        player.seek(0.0,true)
        var before = []
        for b in rig.get_bone_count(): before.append(rig.get_bone_pose_rotation(b))
        player.seek(anim.length*0.43,true)
        var changed = 0
        for b in rig.get_bone_count():
            if before[b].angle_to(rig.get_bone_pose_rotation(b))>0.01: changed+=1
        if not check(changed>=4,"multiple bones actually move in "+clip): return
        var hip = rig.find_bone("Hips")
        var positions=[]
        for sample in [0.0,0.25,0.5,0.75,1.0]:
            player.seek(anim.length*sample,true)
            rig.force_update_all_bone_transforms()
            positions.append(rig.global_transform * rig.get_bone_global_pose(hip).origin)
        for pos in positions:
            if not check(Vector2(pos.x,pos.z).distance_to(Vector2(positions[0].x,positions[0].z))<0.001,"controller-owned horizontal motion "+clip): return
    model.queue_free()
    print("PASS: Ice Mage 24-bone rig, one 20–40k mesh, 4k texture, true Idle Walk Run and in-place world root")
    quit(0)
