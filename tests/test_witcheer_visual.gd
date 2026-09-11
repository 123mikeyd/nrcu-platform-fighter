extends SceneTree
func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> bool:
    if not ok: printerr("FAIL: "+message); quit(1)
    return ok
func run():
    var fighter=load("res://scripts/fighter.gd").new()
    fighter.character_id="witcheer"
    root.add_child(fighter);fighter.set_physics_process(false)
    var visual=fighter.get_node_or_null("VisualRoot/WitcheerVisual")
    if not check(visual!=null,"real Witcheer replaces placeholders"): return
    if not check(fighter._visual_root.get_child_count()==1,"no duplicate body or props"): return
    visual.sync_pose(true,Vector3(7,0,0),false,false,1.0)
    if not check(visual.animation_player.is_playing() and visual.current_clip=="Run","grounded travel runs"): return
    for state in [[true,Vector3.ZERO,false,false],[false,Vector3(7,2,0),false,false],[true,Vector3(7,0,0),true,false],[true,Vector3(7,0,0),false,true]]:
        visual.sync_pose(state[0],state[1],state[2],state[3],-1.0)
        if not check(not visual.animation_player.is_playing() and visual.fallback_label=="Held Run pose (no dedicated Idle/fall)","honest non-run pose"): return
    visual.sync_pose(true,Vector3(7,0,0),false,false,-1.0)
    if not check(visual.animation_player.is_playing(),"Run resumes from held pose"): return
    fighter._visual_root.scale.x=-1
    fighter.facing=-1
    fighter._update_move_visuals()
    if not check(fighter._visual_root.scale==Vector3.ONE and visual.model.rotation.y<0,"yaw not mirror"): return
    var other=load("res://scripts/witcheer_visual.gd").new();root.add_child(other)
    var m1=visual.model.find_children("*","MeshInstance3D",true,false)[0].get_active_material(0)
    var m2=other.model.find_children("*","MeshInstance3D",true,false)[0].get_active_material(0)
    if not check(m1!=m2 and m1.albedo_texture==m2.albedo_texture and not m1.emission_enabled,"isolated materials preserve paint, no glow"): return
    if not check(visual.animation_player.get_animation("Run")!=other.animation_player.get_animation("Run"),"isolated animation resources"): return
    fighter.queue_free();other.queue_free();await process_frame
    print("PASS: Witcheer Run locomotion, honest held poses, resume, yaw and independent presentation")
    quit()
