extends Node3D
# Girl and approved visual-only native companion. Shared combat remains unchanged.
const MODEL = preload("res://assets/mephisto/mephisto_girl.glb")
const VISUAL_SCALE := 1.25
const FLOOR_OFFSET := 0.04
var model: Node3D
var animation_player: AnimationPlayer
var current_clip := "Idle"
var fallback_label := ""
var shadow_move := ""
const Kit=preload("res://scripts/mephisto_kit.gd")
func kit_wrist(hand: String) -> Vector3:
    var sk: Skeleton3D=$CompanionFacing/ShadowCompanion.forms[0].find_children("*","Skeleton3D",true,false)[0]
    sk.force_update_all_bone_transforms()
    return sk.global_transform*sk.get_bone_global_pose(sk.find_bone(hand)).origin
func kit_hand(hand: String) -> Vector3:
    # Damage follows the physical palm segment, not an invisible forward box.
    return kit_wrist(hand).lerp(kit_wrist(hand+"_End"),.65)
func kit_pose(id: String,time: float,direction: float):
    # Re-seed from native compensated baseline every sample: no accumulated IK.
    shadow_pose("ShadowUppercut",0,direction)
    shadow_move=id
    var d=Kit.MOVES[id]
    var c=$CompanionFacing/ShadowCompanion
    var sk: Skeleton3D=c.forms[0].find_children("*","Skeleton3D",true,false)[0]
    var owner_=get_parent().get_parent()
    var preparation=smoothstep(0,d.startup,time)
    var strike=smoothstep(d.startup,d.startup+d.active,time)
    var recovery=smoothstep(d.startup+d.active,Kit.duration(id),time)
    var target: Vector3=d.from.lerp(d.to,strike)
    target.x*=direction
    var native=kit_wrist(d.hand)
    var goal=native.lerp(owner_.global_position+target,preparation*(1.0-recovery))
    Kit.reach(sk,d.hand,sk.global_transform.affine_inverse()*goal)
    var hand_axis: Vector3=d.launch
    hand_axis.x*=direction
    var wrist=sk.find_bone(d.hand)
    var tip=sk.find_bone(d.hand+"_End")
    var a=(sk.get_bone_global_pose(tip).origin-sk.get_bone_global_pose(wrist).origin).normalized()
    var b=(sk.global_transform.basis.inverse()*hand_axis).normalized()
    var parent_rotation=sk.get_bone_global_pose(sk.get_bone_parent(wrist)).basis.orthonormalized().get_rotation_quaternion()
    var turn=Quaternion.IDENTITY.slerp(Quaternion(a,b),preparation*(1.0-recovery))
    sk.set_bone_pose_rotation(wrist,(parent_rotation.inverse()*turn*parent_rotation*sk.get_bone_pose_rotation(wrist)).normalized())
    if d.get("both",false):
        var second: Vector3=owner_.global_position+target+Vector3(-direction*.22,.02,-.20)
        Kit.reach(sk,"RightHand",sk.global_transform.affine_inverse()*kit_wrist("RightHand").lerp(second,preparation*(1.0-recovery)))
    # Legacy shared .22-.60 pitch snippet visibly raises the girl's knee.
    # Retained on unrelated routes pending review; not an authored jab.
    animation_player.play("PitchGuillotine",0)
    animation_player.seek(.22+.38*sin(preparation*(1.0-recovery)*PI*.5),true)
    animation_player.pause()
    current_clip=id
var side_pose_restore={}
func restore_side_pose():
    if side_pose_restore.is_empty():return
    var sk: Skeleton3D=$CompanionFacing/ShadowCompanion.forms[0].find_children("*","Skeleton3D",true,false)[0]
    for i in side_pose_restore:sk.set_bone_pose(i,side_pose_restore[i])
    sk.force_update_all_bone_transforms()
    side_pose_restore.clear()
func shadow_pose(move: String, time: float, direction: float):
    restore_side_pose()
    shadow_move=move
    model.rotation.y=direction*PI/2
    $CompanionFacing.rotation.y=model.rotation.y
    var c=$CompanionFacing/ShadowCompanion
    c.combat_pose=true
    c._set_form(0,.14,0)
    c._set_form(1,1.25,1)
    var ap=c.players[0]
    var sk: Skeleton3D=c.forms[0].find_children("*","Skeleton3D",true,false)[0]
    var native_body={}
    if move=="RubberGuillotine":
        ap.play("ShadowDownStrike",0);ap.seek(0,true)
        for bone in ["Spine01","Spine"]:
            native_body[bone]=sk.get_bone_pose_rotation(sk.find_bone(bone))
    ap.play("RubberGuillotine" if move=="RubberGuillotine" else "ShadowDownStrike",0)
    ap.seek(time,true)
    ap.pause()
    if move=="RubberGuillotine":
        correct_side_body(sk,native_body,time,direction)
    var hide=0.0
    if move=="ShadowUppercut":hide=smoothstep(.32,.40,time)*(1.0-smoothstep(.99,1.14,time))
    c.materials[0].set_shader_parameter("hand_world",shadow_hand())
    c.materials[0].set_shader_parameter("hand_hide",hide)
    animation_player.play("PitchGuillotine" if move=="RubberGuillotine" else "Idle",0)
    animation_player.seek(time if move=="RubberGuillotine" else 0.0,true)
    animation_player.pause()
    current_clip="PitchGuillotine" if move=="RubberGuillotine" else "Idle"
func correct_side_body(sk: Skeleton3D, native: Dictionary, time: float, direction: float):
    var weight=smoothstep(.30,1.35,time)*(1.0-smoothstep(1.85,3.95,time))
    for bone in ["Spine01","Spine","neck","Head","RightShoulder","LeftShoulder"]:
        var i=sk.find_bone(bone)
        side_pose_restore[i]=sk.get_bone_pose(i)
    # Correct only the upper body; preserve both complete arm world transforms,
    # including the approved nonuniform elastic scale and wrist sweep.
    var shoulders={}
    for bone in ["RightShoulder","LeftShoulder"]:
        var i=sk.find_bone(bone)
        shoulders[i]=sk.get_bone_global_pose(i)
    for bone in native:
        var i=sk.find_bone(bone)
        sk.set_bone_pose_rotation(i,sk.get_bone_pose_rotation(i).slerp(native[bone],.40*weight))
    sk.force_update_all_bone_transforms()
    for i in shoulders:sk.set_bone_global_pose(i,shoulders[i])
    sk.force_update_all_bone_transforms()
    for bone in ["neck","Head"]:
        var i=sk.find_bone(bone)
        var face=(kit_wrist("headfront")-kit_wrist("Head")).normalized()
        var goal=Vector3(direction,.12,.10*direction).normalized()
        var turn=Quaternion.IDENTITY.slerp(Quaternion(face,goal),weight*(.40 if bone=="neck" else .85))
        var world_parent=sk.global_transform.basis*sk.get_bone_global_pose(sk.get_bone_parent(i)).basis
        var q=world_parent.orthonormalized().get_rotation_quaternion()
        sk.set_bone_pose_rotation(i,(q.inverse()*turn*q*sk.get_bone_pose_rotation(i)).normalized())
        sk.force_update_all_bone_transforms()
func restore_toss_anchor():
    var anchor=get_node_or_null("CompanionFacing")
    if not anchor:return
    anchor.top_level=false
    anchor.position=Vector3(0,0,-.36)
    anchor.scale=Vector3.ONE
    anchor.rotation=Vector3(0,model.rotation.y,0)
func anchor_toss():
    var anchor=$CompanionFacing
    var world=anchor.global_transform
    anchor.top_level=true
    anchor.global_transform=world
func girl_hips() -> Vector3:
    var sk: Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
    sk.force_update_all_bone_transforms()
    return sk.global_transform*sk.get_bone_global_pose(sk.find_bone("Hips")).origin
func toss_pose(time: float, direction: float):
    shadow_pose("ShadowUppercut",0,direction)
    shadow_move="CinderToss"
    var sk: Skeleton3D=$CompanionFacing/ShadowCompanion.forms[0].find_children("*","Skeleton3D",true,false)[0]
    var hips=girl_hips()
    var amount=smoothstep(0,.16,time)
    # Two actual palms brace the native girl's lower torso. The girl is held
    # in neutral; lift travel is exclusively the fighter's physics velocity.
    for pair in [["LeftHand",.17],["RightHand",-.17]]:
        var hand: String=pair[0]
        var goal=hips+Vector3(-direction*.02,-.02,pair[1]*direction)
        var target=kit_hand(hand).lerp(goal,amount)
        for iteration in 4:
            var wrist_goal=kit_wrist(hand)+(target-kit_hand(hand))
            Kit.reach(sk,hand,sk.global_transform.affine_inverse()*wrist_goal)
    current_clip="CinderToss"
func shadow_hand() -> Vector3:
    var sk: Skeleton3D=$CompanionFacing/ShadowCompanion.forms[0].find_children("*","Skeleton3D",true,false)[0]
    sk.force_update_all_bone_transforms()
    return sk.global_transform*sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
func end_shadow_move():
    restore_side_pose()
    shadow_move=""
    var c=get_node_or_null("CompanionFacing/ShadowCompanion")
    if c:
        c.materials[0].set_shader_parameter("hand_hide",0.0)
        c.combat_pose=false
        c.reset_presentation()
        for ap in c.players: ap.stop()
func _ready() -> void:
    scale = Vector3.ONE * VISUAL_SCALE
    position.y = FLOOR_OFFSET
    model = MODEL.instantiate()
    add_child(model)
    animation_player = model.find_children("*", "AnimationPlayer", true, false)[0]
    for library_name in animation_player.get_animation_library_list():
        var source = animation_player.get_animation_library(library_name)
        var library = AnimationLibrary.new()
        for clip in source.get_animation_list():
            var animation: Animation = source.get_animation(clip).duplicate(true)
            animation.loop_mode = Animation.LOOP_LINEAR if clip in ["Idle", "Run"] else Animation.LOOP_NONE
            library.add_animation(clip, animation)
        animation_player.remove_animation_library(library_name)
        animation_player.add_animation_library(library_name, library)
    for mesh in model.find_children("*", "MeshInstance3D", true, false):
        for surface in mesh.mesh.get_surface_count():
            var source = mesh.get_active_material(surface)
            if source is StandardMaterial3D:
                var material: StandardMaterial3D = source.duplicate()
                material.metallic = 0.0
                material.roughness = 0.75
                material.emission_enabled = false
                mesh.set_surface_override_material(surface, material)
    var companion_facing = Node3D.new()
    companion_facing.name = "CompanionFacing"
    companion_facing.position.z = -.36
    add_child(companion_facing)
    var companion = preload("res://scripts/mephisto_companion.gd").new()
    companion.name = "ShadowCompanion"
    companion_facing.add_child(companion)
    sync_pose(true, Vector3.ZERO, false, false, false, 1.0)
func sync_pose(grounded: bool, motion: Vector3, hurt: bool, busy: bool, disabled: bool, facing: float) -> void:
    if not animation_player: return
    if not shadow_move.is_empty() and not hurt and not disabled: return
    model.rotation.y = facing * PI / 2.0
    $CompanionFacing.rotation.y = model.rotation.y
    if disabled: $CompanionFacing/ShadowCompanion.reset_presentation()
    var clip := "Hit" if hurt and not disabled else ("Run" if grounded and absf(motion.x) > 0.2 and not busy and not disabled else "Idle")
    var held := clip == "Idle" and (not grounded or busy or disabled)
    fallback_label = "Held Idle: no jump/fall/attack animation assigned" if held else ("Provisional Block8 reaction" if clip == "Hit" else "")
    if current_clip != clip or animation_player.assigned_animation != clip:
        animation_player.play(clip, 0.10)
    elif not animation_player.is_playing() and (clip != "Hit" or animation_player.current_animation_position < animation_player.get_animation(clip).length):
        animation_player.play(clip)
    current_clip = clip
    if held:
        animation_player.play("Idle")
        animation_player.seek(0, true)
        animation_player.pause()
