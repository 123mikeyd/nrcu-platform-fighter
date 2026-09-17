extends Node3D
# v003 evaluated paired reel. Original native girl retained for her existing air libraries.
const MODEL=preload("res://assets/mephisto/mephisto_girl.glb")
const PAIR=preload("res://assets/mephisto_paired/paired_v003.glb")
const VISUAL_SCALE=1.25
const FLOOR_OFFSET=.04
var model:Node3D
var animation_player:AnimationPlayer
var current_clip="Idle"
var shadow_move=""
var fallback_label="Paired starter; air/special polish pending"
var pair:Node3D
var pair_player:AnimationPlayer
var demon:Skeleton3D
var girl:Skeleton3D
var pair_girl:Node3D
var girl_ground=Vector3.ZERO
var source_frame=704.0
var walk_clock=0.0
var walking=false
var native_model:Node3D
var native_player:AnimationPlayer
var native_skeleton:Skeleton3D
var native_clock=0.0
var native_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/mephisto_girl2/phase_catalog.json"))
const NATIVE_BONES={"Hips":"DEF-spine","Spine":"DEF-spine.001","Spine1":"DEF-spine.002","Spine2":"DEF-spine.003","neck":"DEF-spine.004","Head":"DEF-spine.005","LeftUpLeg":"DEF-thigh.L","RightUpLeg":"DEF-thigh.R","LeftLeg":"DEF-shin.L","RightLeg":"DEF-shin.R","LeftFoot":"DEF-foot.L","RightFoot":"DEF-foot.R","LeftToeBase":"DEF-toe.L","RightToeBase":"DEF-toe.R","LeftArm":"DEF-upper_arm.L","RightArm":"DEF-upper_arm.R","LeftForeArm":"DEF-forearm.L","RightForeArm":"DEF-forearm.R","LeftHand":"DEF-hand.L","RightHand":"DEF-hand.R"}
func native_pose(clip:String,time:float,loop=false):
 if not native_player or not native_catalog.has(clip):return
 var d=native_catalog[clip]
 var t=fmod(maxf(0,time),d.seconds) if loop else clampf(time,0,d.seconds)
 native_player.play(native_player.get_animation_list()[0],0)
 native_player.seek(d.start/24.0+t,true);native_player.pause()
 native_skeleton.force_update_all_bone_transforms()
 current_clip="Girl2/"+clip
func old_geometry_hidden():
 for old in [model,pair_girl]:
  for mesh in old.find_children("*","MeshInstance3D",true,false):mesh.visible=false
func fit_native_to_pair(frame:float):
 if not native_model:return
 old_geometry_hidden()
 var seat=1.0
 if frame>=577 and frame<=704:seat=1.0-smoothstep(637,661,frame)
 elif frame>=733:seat=smoothstep(742,758,frame)
 native_pose("Seat",0)
 var seated=[]
 for i in native_skeleton.get_bone_count():seated.append(native_skeleton.get_bone_pose_rotation(i))
 native_pose("Idle",0)
 for i in native_skeleton.get_bone_count():native_skeleton.set_bone_pose_rotation(i,native_skeleton.get_bone_pose_rotation(i).slerp(seated[i],seat))
 native_skeleton.force_update_all_bone_transforms()
 native_model.rotation.y=pair.rotation.y+pair_girl.rotation.y
 var oldhip=girl.global_transform*girl.get_bone_global_pose(girl.find_bone("Hips")).origin
 var newhip=native_skeleton.global_transform*native_skeleton.get_bone_global_pose(native_skeleton.find_bone("DEF-spine")).origin
 native_model.global_position+=oldhip-newhip
func native_air_from_donor():
 var donor:Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
 native_pose("Idle",0)
 for old in NATIVE_BONES:
  var src=donor.find_bone(old);var dst=native_skeleton.find_bone(NATIVE_BONES[old])
  if src<0 or dst<0:continue
  var delta=donor.get_bone_global_pose(src).basis.orthonormalized()*donor.get_bone_global_rest(src).basis.orthonormalized().inverse()
  var desired=(delta*native_skeleton.get_bone_global_rest(dst).basis).get_rotation_quaternion()
  var parent=native_skeleton.get_bone_parent(dst)
  var parent_rot=Quaternion.IDENTITY if parent<0 else native_skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
  native_skeleton.set_bone_pose_rotation(dst,(native_skeleton.get_bone_rest(dst).basis.get_rotation_quaternion().inverse()*parent_rot.inverse()*desired).normalized())
  native_skeleton.force_update_all_bone_transforms()
 current_clip="Girl2/rest-aware/"+str(animation_player.assigned_animation)
func _process(delta):
 native_clock+=delta
 if walking:walk_clock=fmod(walk_clock+delta,132.0/24.0)
 if native_model and actor().humanoid_air_basic and actor().humanoid_air_basic.active:native_air_from_donor()
 elif native_model and actor().humanoid_air_side and actor().humanoid_air_side.active:native_air_from_donor()
func _ready():
 scale=Vector3.ONE*VISUAL_SCALE;position.y=.04
 model=MODEL.instantiate();add_child(model);model.scale=Vector3.ONE*.55
 animation_player=model.find_children("*","AnimationPlayer",true,false)[0]
 for libname in animation_player.get_animation_library_list():
  var lib=animation_player.get_animation_library(libname).duplicate(true)
  animation_player.remove_animation_library(libname);animation_player.add_animation_library(libname,lib)
  for n in lib.get_animation_list():lib.get_animation(n).loop_mode=Animation.LOOP_LINEAR if n in ["Idle","Run"] else Animation.LOOP_NONE
 pair=PAIR.instantiate();pair.name="Demon2GirlPair";add_child(pair)
 pair_player=pair.find_children("*","AnimationPlayer",true,false)[0]
 demon=pair.get_node("rig/Skeleton3D");pair_girl=pair.get_node("01_A1_11_Girl_PlacementRoot")
 girl=pair_girl.get_node("01_A1_11_Girl_Rig/Skeleton3D")
 native_model=preload("res://assets/mephisto_girl2/girl2_native.glb").instantiate();native_model.name="ApprovedGirl2";add_child(native_model);native_model.scale=Vector3.ONE*.45
 native_player=native_model.find_children("*","AnimationPlayer",true,false)[0]
 native_skeleton=native_model.find_children("*","Skeleton3D",true,false)[0]
 old_geometry_hidden()
 pose_frame(704,1)
 girl_ground=pair_girl.position
 model.visible=false
func actor():return get_parent().get_parent()
func pose_frame(frame:float,direction:float):
 source_frame=frame
 pair.rotation.y=direction*PI/2
 pair_player.play("PairedReel",0);pair_player.seek(clampf(frame,1,816)/24.0,true);pair_player.pause()
 demon.force_update_all_bone_transforms();girl.force_update_all_bone_transforms()
 pair_girl.visible=true;model.visible=false
 fit_native_to_pair(frame)
func demon_point(bone:String)->Vector3:
 demon.force_update_all_bone_transforms()
 return demon.global_transform*demon.get_bone_global_pose(demon.find_bone(bone)).origin
func girl_point(bone:String)->Vector3:
 if native_skeleton:
  native_skeleton.force_update_all_bone_transforms()
  var index=native_skeleton.find_bone(NATIVE_BONES.get(bone,bone))
  if index>=0:return native_skeleton.global_transform*native_skeleton.get_bone_global_pose(index).origin
 var sk:Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0] if model.visible else girl
 sk.force_update_all_bone_transforms()
 return sk.global_transform*sk.get_bone_global_pose(sk.find_bone(bone)).origin
func show_native_girl(direction:float):
 pair_girl.visible=false;model.visible=true
 model.rotation.y=direction*PI/2
 model.position=Basis(Vector3.UP,direction*PI/2)*girl_ground
 # The retained native Idle/Run are already floor-rooted, unlike the reel's posed root.
 model.position.y=0
 if native_model:
  native_model.rotation.y=model.rotation.y
  native_model.position=model.position
  old_geometry_hidden()
func girl_pose(time:float,direction:float):
 pose_frame(704,direction);show_native_girl(direction)
 var moves=actor().mephisto_moves
 var clip=moves.move if moves else "Idle"
 native_pose(clip,time)
func end_shadow_move():shadow_move=""
func restore_toss_anchor():pass
func sync_pose(grounded:bool,motion:Vector3,hurt:bool,busy:bool,disabled:bool,direction:float):
 if not pair_player:return
 var a=actor();var moves=a.mephisto_moves
 if moves and not moves.move.is_empty() and not hurt and not disabled:return
 var dem= moves.demon_form if moves else false
 pose_frame(1 if dem else 704,direction)
 walking=dem and grounded and absf(motion.x)>.2 and not busy and not disabled and not hurt
 if walking:
  pair_player.play("PairedWalk",0);pair_player.seek(1.0/24.0+walk_clock,true);pair_player.pause()
  current_clip="PairedWalk"
 if not dem:
  show_native_girl(direction)
  var clip="Hit" if hurt else ("Run" if grounded and absf(motion.x)>.2 and not busy and not disabled else "Idle")
  if animation_player.assigned_animation!=clip:animation_player.play(clip,.1)
  elif not animation_player.is_playing():animation_player.play(clip)
  current_clip=clip
  native_pose(clip,native_clock,true)
