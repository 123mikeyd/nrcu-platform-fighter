extends SceneTree
var failures := 0
func check(ok: bool, text: String):
    if not ok: failures += 1; printerr("FAIL: " + text)
func _initialize(): call_deferred("run")
func run():
    var roster=load("res://scripts/roster.gd")
    check("mephisto" in roster.ids(), "Mephisto selectable identity")
    var path="res://assets/mephisto/mephisto_girl.glb"
    check(ResourceLoader.exists(path),"source-backed girl imported")
    if failures: quit(1);return
    var f=load("res://scripts/fighter.gd").new();f.character_id="mephisto";root.add_child(f)
    f.set_physics_process(false)
    var v=f.get_node_or_null("VisualRoot/MephistoVisual")
    check(v!=null,"girl replaces all primitive presentation")
    if not v: quit(1);return
    check(v.model.find_children("*","Skeleton3D",true,false)[0].get_bone_count()==24,"24 source bones")
    var ap=v.animation_player
    for clip in ["Idle","Run","Hit"]:check(ap.has_animation(clip),"source clip "+clip)
    check(absf(ap.get_animation("Run").length-0.6)<0.002,"exact run duration")
    check(absf(ap.get_animation("Idle").length-11.4)<0.002,"exact idle duration")
    v.sync_pose(true,Vector3.ZERO,false,false,false,1.0)
    check(v.current_clip=="Idle" and ap.is_playing(),"dedicated animated idle")
    v.sync_pose(true,Vector3(4,0,0),false,false,false,1.0)
    check(v.current_clip=="Run" and ap.is_playing(),"dedicated run")
    var skeleton=v.model.find_children("*","Skeleton3D",true,false)[0]
    ap.seek(0,true);skeleton.force_update_all_bone_transforms();var p=skeleton.get_bone_pose_rotation(1)
    ap.advance(.2);skeleton.force_update_all_bone_transforms();check(p.angle_to(skeleton.get_bone_pose_rotation(1))>.01,"run moves actual skeleton after transition blend")
    v.sync_pose(true,Vector3(-4,0,0),false,false,false,-1.0)
    check(is_equal_approx(v.model.rotation.y,-PI/2),"left facing yaw not negative scale")
    v.sync_pose(false,Vector3(0,5,0),false,false,false,1.0)
    check(v.current_clip=="Idle" and not ap.is_playing(),"honest held airborne fallback")
    v.sync_pose(true,Vector3.ZERO,true,false,false,1.0)
    check(v.current_clip=="Hit","source Block8 provisional hit response")
    v.sync_pose(true,Vector3(4,0,0),false,false,false,1.0)
    check(v.current_clip=="Run" and ap.assigned_animation=="Run" and ap.is_playing(),"run resumes after interruption")
    var other=load("res://scripts/fighter.gd").new();other.character_id="mephisto";other.player_index=2;root.add_child(other);other.set_physics_process(false)
    check(ap.get_animation("Run")!=other.get_node("VisualRoot/MephistoVisual").animation_player.get_animation("Run"),"independent animations")
    other.position.x=1.5;f.controls_enabled=true;f.basic_attack(Vector2.RIGHT,false)
    check(other.damage_percent>0,"generic provisional basic damages")
    check(f.doge_attack_clip.is_empty() and f.witcheer_clip.is_empty() and not f.teknium_magic,"no borrowed unique fighter kit")
    f.queue_free();other.queue_free();await process_frame
    if failures==0:print("PASS: Mephisto source asset, locomotion, fallback, facing, independent resources and generic basic")
    quit(1 if failures else 0)
