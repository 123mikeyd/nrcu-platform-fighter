extends Node3D
# Approved Girl2 is the only visible girl. Old rigs are hidden motion carriers.
const MODEL=preload("res://assets/mephisto/mephisto_girl.glb")
const PAIR=preload("res://assets/mephisto_paired/paired_v003.glb")
const VISUAL_SCALE=1.25
const FLOOR_OFFSET=.04
const COMPANION_MODE=true
var companion
var model:Node3D
var animation_player:AnimationPlayer
var current_clip="Idle"
var shadow_move=""
var fallback_label="Girl2 native paired kit; first-pass choreography"
var pair:Node3D
var pair_player:AnimationPlayer
var demon:Skeleton3D
var girl:Skeleton3D
var pair_girl:Node3D
var girl_ground=Vector3.ZERO
var source_frame=704.0
var walk_clock=0.0
var walking=false
# Approved Rust review size. Source rigs/Actions remain in their original units.
const APPROVED_GIRL_SCALE=.71926
const SOURCE_GIRL_SCALE=.504
const NATIVE_SOLE_Y=.047908014
var native_unscaled_transform=Transform3D.IDENTITY
var native_model:Node3D
var native_player:AnimationPlayer
var native_skeleton:Skeleton3D
var native_clock=0.0
# Locomotion owns a state-local clock and ONE immutable outgoing snapshot.
# Sample the advancing native target, never recursively damp the previous pose.
var locomotion_state=""
var locomotion_started=0.0
var locomotion_seed:Array[Transform3D]=[]
const LOCOMOTION_BLEND=.16
func locomotion_snapshot()->Array[Transform3D]:
 var result:Array[Transform3D]=[]
 native_skeleton.force_update_all_bone_transforms()
 for i in native_skeleton.get_bone_count():result.append(native_skeleton.get_bone_global_pose(i))
 return result
func locomotion_pose(clip:String,outgoing:Array[Transform3D]):
 if clip!=locomotion_state:
  locomotion_state=clip;locomotion_started=native_clock;locomotion_seed=outgoing
 var elapsed=maxf(0,native_clock-locomotion_started)
 native_pose(clip,elapsed,true)
 if clip not in ["Idle","Run"] or elapsed>=LOCOMOTION_BLEND or locomotion_seed.is_empty():return
 var targets=locomotion_snapshot()
 var weight=smoothstep(0,LOCOMOTION_BLEND,elapsed)
 for i in targets.size():
  native_skeleton.set_bone_global_pose_override(i,locomotion_seed[i].interpolate_with(targets[i],weight),1.0,true)
 native_skeleton.force_update_all_bone_transforms()
var native_reel=""
var footless_player:AnimationPlayer
var palm_samples=[]
static var palm_binding_cache={}
var native_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/mephisto_girl2/phase_catalog.json"))
const NATIVE_BONES={"Hips":"DEF-spine","Spine":"DEF-spine.001","Spine1":"DEF-spine.002","Spine2":"DEF-spine.003","neck":"DEF-spine.004","Head":"DEF-spine.005","LeftUpLeg":"DEF-thigh.L","RightUpLeg":"DEF-thigh.R","LeftLeg":"DEF-shin.L","RightLeg":"DEF-shin.R","LeftFoot":"DEF-foot.L","RightFoot":"DEF-foot.R","LeftToeBase":"DEF-toe.L","RightToeBase":"DEF-toe.R","LeftArm":"DEF-upper_arm.L","RightArm":"DEF-upper_arm.R","LeftForeArm":"DEF-forearm.L","RightForeArm":"DEF-forearm.R","LeftHand":"DEF-hand.L","RightHand":"DEF-hand.R"}
func native_pose(clip:String,time:float,loop=false):
 if not native_player or not native_catalog.has(clip):return
 if clip=="Run":
  if not native_player.has_animation_library("human_locomotion"):
   native_player.add_animation_library("human_locomotion",load("res://assets/mephisto_girl2/human_run.tres"))
  native_player.play("human_locomotion/HumanRun",0)
  native_player.seek(fposmod(time,.43),true);native_player.pause()
  native_skeleton.force_update_all_bone_transforms()
  current_clip="Girl2/Run"
  return
 var d=native_catalog[clip]
 var t=fmod(maxf(0,time),d.seconds) if loop else clampf(time,0,d.seconds)
 native_player.play(native_reel,0)
 native_player.seek(d.start/24.0+t,true);native_player.pause()
 native_skeleton.force_update_all_bone_transforms()
 current_clip="Girl2/"+clip
func old_geometry_hidden():
 for old in [model,pair_girl]:
  for mesh in old.find_children("*","MeshInstance3D",true,false):mesh.visible=false
func fit_native_to_pair(frame:float):
 if not native_model:return
 old_geometry_hidden()
 native_model.scale=Vector3.ONE*SOURCE_GIRL_SCALE
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
 if seat<1.0:
  var ground=Basis(Vector3.UP,pair.rotation.y)*girl_ground
  ground.y=0;ground.z=0
  native_model.position=native_model.position.lerp(ground,1.0-seat)
 apply_girl_size(seat)
func apply_girl_size(seated:float):
 # Always called after the ORIGINAL placement writer, never compounded each tick.
 # Stand about the evaluated native Idle sole; carry about the evaluated hip.
 native_unscaled_transform=native_model.transform
 var pivot=native_model.to_global(Vector3(0,NATIVE_SOLE_Y,0)).lerp(girl_point("Hips"),seated)
 var ratio=APPROVED_GIRL_SCALE/SOURCE_GIRL_SCALE
 native_model.scale*=ratio
 native_model.global_position=pivot+(native_model.global_position-pivot)*ratio
 # Seat footprint was behind the wrist after enlargement. Recenter toward the
 # left palm in its evaluated basis, fading out through pickup/setdown.
 var support=demon.global_transform*demon.get_bone_global_pose(demon.find_bone("DEF-hand.L"))
 native_model.global_position+=support.basis*Vector3(-.08,.12,.035)*seated
func native_air_from_donor():
 locomotion_state=""
 # Aerial donor owns the visible skeleton immediately, including blend entry.
 native_skeleton.clear_bones_global_pose_override()
 var donor:Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
 native_pose("Idle",0)
 for old in NATIVE_BONES:
  var src=donor.find_bone(old);var dst=native_skeleton.find_bone(NATIVE_BONES[old])
  if src<0 or dst<0:continue
  var delta=donor.get_bone_global_pose(src).basis.orthonormalized()*donor.get_bone_global_rest(src).basis.orthonormalized().inverse()
  var desired=(delta*native_skeleton.get_bone_global_rest(dst).basis).get_rotation_quaternion()
  var parent=native_skeleton.get_bone_parent(dst)
  var parent_rot=Quaternion.IDENTITY if parent<0 else native_skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
  native_skeleton.set_bone_pose_rotation(dst,(parent_rot.inverse()*desired).normalized())
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
 native_reel=native_player.get_animation_list()[0]
 native_player.add_animation_library("kick",preload("res://assets/mephisto_girl2/goalkeeper_kick.tres"))
 native_skeleton=native_model.find_children("*","Skeleton3D",true,false)[0]
 footless_player=AnimationPlayer.new();footless_player.name="FootlessPlayer";add_child(footless_player)
 footless_player.add_animation_library("",preload("res://assets/mephisto_paired/footless_pair.tres"))
 if not COMPANION_MODE:
  var smoke=preload("res://scripts/mephisto_footless_smoke.gd").new();smoke.name="FootlessSmoke";add_child(smoke);smoke.setup(self)
  demon_palm_points()
 old_geometry_hidden()
 pose_frame(704,1)
 girl_ground=pair_girl.position
 model.visible=false
 if COMPANION_MODE:
  pair.visible=false
  companion=preload("res://scripts/mephisto03_companion.gd").new()
  companion.name="Mephisto03Companion";add_child(companion);companion.setup(self)
func actor():return get_parent().get_parent()
func pose_frame(frame:float,direction:float):
 demon.clear_bones_global_pose_override();native_skeleton.clear_bones_global_pose_override()
 source_frame=frame
 pair.rotation.y=direction*PI/2
 pair_player.play("PairedReel",0);pair_player.seek(clampf(frame,1,816)/24.0,true);pair_player.pause()
 demon.force_update_all_bone_transforms();girl.force_update_all_bone_transforms()
 pair_girl.visible=true;model.visible=false
 fit_native_to_pair(frame)
func demon_point(bone:String)->Vector3:
 demon.force_update_all_bone_transforms()
 return demon.global_transform*demon.get_bone_global_pose(demon.find_bone(bone)).origin
func demon_palm_points()->Array:
 if palm_samples.is_empty():
  for mesh in demon.find_children("*","MeshInstance3D",true,false):
   var id=mesh.mesh.get_instance_id()
   if palm_binding_cache.has(id):palm_samples.append_array(palm_binding_cache[id]);continue
   var cached=[]
   var cells={}
   for surface in mesh.mesh.get_surface_count():
    var a=mesh.mesh.surface_get_arrays(surface);var influences=int(a[Mesh.ARRAY_BONES].size()/a[0].size())
    for i in a[0].size():
     var weight=0.0;var bindings=[]
     for j in influences:
      var bind=a[Mesh.ARRAY_BONES][i*influences+j];var w=a[Mesh.ARRAY_WEIGHTS][i*influences+j]
      if w<=0:continue
      var name=mesh.skin.get_bind_name(bind)
      if name=="DEF-hand.R":weight+=w
     if weight<.5:continue
     var cell=Vector3i((a[0][i]/.045).floor())
     if cells.has(cell):continue
     for j in influences:
      var bind=a[Mesh.ARRAY_BONES][i*influences+j];var w=a[Mesh.ARRAY_WEIGHTS][i*influences+j]
      if w>0:bindings.append([demon.find_bone(mesh.skin.get_bind_name(bind)),mesh.skin.get_bind_pose(bind)*a[0][i],w])
     cells[cell]=true;cached.append(bindings)
   palm_binding_cache[id]=cached;palm_samples.append_array(cached)
 var points=[]
 for bindings in palm_samples:
  var point=Vector3.ZERO
  for bind in bindings:point+=(demon.get_bone_global_pose(bind[0])*bind[1])*bind[2]
  points.append(demon.global_transform*point)
 return points
func footless_pose(clip:String,time:float,direction:float):
 var clock=preload("res://scripts/mephisto_arm_timing.gd")
 var source=(clock.frame_at(clip,time)-1.0)/24.0
 var end=clock.time_at(clip,1+footless_player.get_animation(clip).length*24)
 var blend=minf(smoothstep(0,clock.ENTRY,time),1.0-smoothstep(end,end+clock.EXIT,time))
 native_pair_pose(clip,source,blend,direction)
func pair_snapshot()->Dictionary:
 var old=[]
 for sk in [demon,native_skeleton]:
  var poses=[]
  for i in sk.get_bone_count():poses.append(sk.get_bone_global_pose(i))
  old.append(poses)
 return {"poses":old,"placement":native_unscaled_transform}
func native_pair_pose(clip:String,source:float,blend:float,direction:float,seed:Dictionary={}):
 # Bind-adapted affine samples preserve source shear and both characters.
 pose_frame(1,direction)
 var base=pair_snapshot() if seed.is_empty() else seed
 var old=base.poses
 var placement=base.placement
 var full=footless_player.get_animation(clip).get_meta("full_globals")
 native_player.pause();pair_player.pause()
 footless_player.play(clip,0);footless_player.seek(source,true);footless_player.pause()
 var turn=Transform3D(Basis(Vector3.UP,direction*PI/2),Vector3.ZERO)
 native_model.transform=placement.interpolate_with(turn*native_model.transform,blend)
 var sample=source*24.0;var lo=mini(int(floor(sample)),full.size()-1);var hi=mini(lo+1,full.size()-1);var fraction=sample-lo
 for k in 2:
  var sk=demon if k==0 else native_skeleton
  for i in sk.get_bone_count():
   # Preserve evaluated Rigify shear as well as complete imported bind bases.
   # TRS-only tracks cannot exactly represent compressed multi-segment legs.
   var a:Transform3D=full[lo][k][i];var b:Transform3D=full[hi][k][i]
   var pose=Transform3D(Basis(a.basis.x.lerp(b.basis.x,fraction),a.basis.y.lerp(b.basis.y,fraction),a.basis.z.lerp(b.basis.z,fraction)),a.origin.lerp(b.origin,fraction))
   if blend<.99999:pose=old[k][i].interpolate_with(pose,blend)
   sk.set_bone_global_pose_override(i,pose,1.0,true)
  sk.force_update_all_bone_transforms()
 apply_girl_size(1.0)
 source_frame=1+source*24;current_clip=clip
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
  native_model.scale=Vector3.ONE*SOURCE_GIRL_SCALE
  native_model.rotation.y=model.rotation.y
  native_model.position=model.position
  native_model.position.z=0
  apply_girl_size(0.0)
  old_geometry_hidden()
func girl_pose(time:float,direction:float):
 locomotion_state=""
 pose_frame(704,direction);show_native_girl(direction)
 var moves=actor().mephisto_moves
 var clip=moves.move if moves else "Idle"
 native_pose(clip,time)
func end_shadow_move():
 shadow_move=""
 if demon:demon.clear_bones_global_pose_override()
 if native_skeleton:native_skeleton.clear_bones_global_pose_override()
func restore_toss_anchor():pass
func sync_pose(grounded:bool,motion:Vector3,hurt:bool,busy:bool,disabled:bool,direction:float):
 if not pair_player:return
 var a=actor();var moves=a.mephisto_moves
 if moves and not moves.move.is_empty() and not hurt and not disabled:
  locomotion_state=""
  return
 # Capture BEFORE pose_frame resamples Seat/Idle for placement.
 var outgoing=locomotion_snapshot()
 var dem= moves.demon_form if moves else false
 pose_frame(1 if dem else 704,direction)
 walking=dem and grounded and absf(motion.x)>.2 and not busy and not disabled and not hurt
 if walking:
  pair_player.play("PairedWalk",0);pair_player.seek(1.0/24.0+walk_clock,true);pair_player.pause()
  fit_native_to_pair(1)
  current_clip="PairedWalk"
 if not dem:
  show_native_girl(direction)
  var clip="Hit" if hurt else ("Run" if grounded and absf(motion.x)>.2 and not busy and not disabled else "Idle")
  if animation_player.assigned_animation!=clip:animation_player.play(clip,.1)
  elif not animation_player.is_playing():animation_player.play(clip)
  current_clip=clip
  if clip=="Hit":
   locomotion_state="";native_pose(clip,native_clock,true)
  else:
   locomotion_pose(clip,outgoing)
   # Reapply the unchanged companion alignment after final moving pelvis sampling.
   if companion:companion.sync_pose()
