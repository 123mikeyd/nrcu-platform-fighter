extends Node3D
# Guitar presentation accompanying the fighter-owned held Sound Orb.
const GUITAR=preload("res://assets/turbofit/real_guitar.glb")
const WAVE_PRESENTATION_DURATION=0.55*0.8/0.7 # provisional +14.3%, gameplay stays 0.55s
var guitar: Node3D
var view
var skeleton: Skeleton3D
var side_requested=false
var mode=""
var clock=0.0
var playing=false
var blocked=false
var phase=""
var amount=0.0
var input_owned=false
func begin_performance():
 hide_now()
 phase="entry"
 input_owned=false
func tick_input(f,input):
 if phase.is_empty(): return
 input_owned=true
 if input.left or input.right or input.jump or input.up or input.attack or not f.is_grounded():
  f._clear_sound_orb(); hide_now(); return
 if not input.down or not input.special:
  f._clear_sound_orb()
  phase="release"
func _ready():
 view=get_parent()
 skeleton=view._kick_skeleton
 guitar=GUITAR.instantiate()
 guitar.name="MikesRealGuitar"
 add_child(guitar)
 guitar.visible=false
 # GLB geometry: +Y neck, +Z strings, body at negative Y.
 # Native imported mesh is 1.9055m; 0.64 gives a 1.22m instrument.
 process_priority=100
func hide_now():
 phase=""
 amount=0.0
 input_owned=false
 guitar.visible=false
 mode=""
 if playing:
  skeleton.clear_bones_global_pose_override()
 playing=false
 clock=0.0
func guard(f,interrupted=false):
 blocked=interrupted or f.hitstun>0 or f.shielding or f.freeze_remaining>0 or f.magic_locked() or not f.controls_enabled or f.stocks<=0 or is_instance_valid(f.caught_by) or (f.tumble and f.tumble.active)
 if blocked and not phase.is_empty(): f._clear_sound_orb()
 if not phase.is_empty() and phase!="release" and f.sound_orb_time<=0:
  # Release may have been sampled by the early fighter watchdog.
  phase="release"
 if blocked or (mode=="wave" and f.charging) or (phase.is_empty() and f.attack_cooldown<=0 and not f.charging and not wave_tail()): hide_now()
func present(grounded,interrupted,shielding,move,attack_clip,delta):
 if blocked or interrupted or shielding or not attack_clip.is_empty(): hide_now(); return
 var desired=""
 if move in ["CHARGING","POWER CHORD"]: desired="power"
 if grounded and move=="GUITAR SWING" and side_requested: desired="swing"
 if move=="SOUND WAVE" or (move.is_empty() and delta>0 and wave_tail()): desired="wave"
 var f=view.get_parent().get_parent()
 if not phase.is_empty():
  if not input_owned and f.sound_orb_time<=0: hide_now(); return
  amount=move_toward(amount,0.0 if phase=="release" else 1.0,delta/(0.20 if phase=="release" else 0.28))
  if phase=="release" and amount<=0: hide_now(); return
  if amount>=1 and phase=="entry": phase="loop"
  desired="play"
 if desired.is_empty(): hide_now(); return
 if mode!=desired:
  skeleton.clear_bones_global_pose_override(); clock=0
 mode=desired
 playing=mode=="play"
 clock+=delta
 guitar.visible=true
 if mode in ["swing","wave","power"]: update_attachment()
func _process(_delta):
 if not guitar.visible: return
 var f=view.get_parent().get_parent()
 if f and f.has_method("is_grounded"):
  guard(f)
  if phase.is_empty() and f.attack_cooldown<=0 and not f.charging and not wave_tail(): hide_now()
 if guitar.visible and mode in ["swing","wave","power"]: update_attachment()
func wave_tail():
 return mode=="wave" and clock<WAVE_PRESENTATION_DURATION
func bone_world(name):
 return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_"+name))
func update_attachment():
 skeleton.force_update_all_bone_transforms()
 if mode in ["swing","wave","power"]:
  var hand=bone_world("RightHand")
  # Neck crosses the palm; pivot 7cm past the wrist, 1cm into palm.
  var basis=hand.basis.orthonormalized()*Basis.from_euler(Vector3(0,0,PI/2))
  var grip=hand.origin+hand.basis.orthonormalized()*Vector3(0,0.07,0.01)
  guitar.global_transform=Transform3D(basis*0.8,grip-basis*Vector3(0,0.46,0)*0.8)
 elif mode=="play":
  apply_playing_grip()

func rock_pose(facing):
 skeleton.clear_bones_global_pose_override()
 view.model.rotation.y=facing*PI/2
 view.current_clip="GuitarRockReview"
 # Editable RockOutSouthpawV2: fixed native Idle reference, authored FK/IK.
 # No independent hair simulation: hair follows the existing skinned head.
 view.animation_player.play("Idle",0)
 view.animation_player.speed_scale=0
 view.animation_player.seek(0,true)
 skeleton.force_update_all_bone_transforms()
 var standing=[]
 for i in skeleton.get_bone_count():standing.append(skeleton.get_bone_global_pose(i))
 var feet={}
 for side in ["Left","Right"]:
  var foot=bone_world(side+"Foot")
  var local=view.model.to_local(foot.origin)
  local.x=0.29 if side=="Left" else -0.29
  local.z+=0.12 if side=="Left" else -0.10
  foot.origin=view.model.to_global(local)
  feet[side]=foot
 var beat=clock*TAU*1.7
 var hip=bone_world("Hips")
 hip.origin+=view.model.global_basis*Vector3(0.018*sin(beat/2),-0.12-0.022*(1-cos(beat)),0)
 set_world_bone("Hips",hip)
 # Chest leads, head follows; instrument is anchored to hips, not skull.
 rotate_model_bone("Spine",0.08+0.11*(1-cos(beat)))
 rotate_model_bone("Spine1",0.035+0.055*(1-cos(beat)))
 rotate_model_bone("Neck",0.04+0.14*(1-cos(beat-0.55)))
 rotate_model_bone("Head",0.04+0.23*(1-cos(beat-0.7)))
 for side in ["Left","Right"]:
  var shoulder=bone_world(side+"Shoulder")
  shoulder.basis=Basis(view.model.global_basis.z.normalized(),-0.22 if side=="Left" else 0.22)*shoulder.basis
  set_world_bone(side+"Shoulder",shoulder)
 for side in ["Left","Right"]:
  solve_limb(side+"UpLeg",side+"Leg",side+"Foot",feet[side].origin,feet[side].basis.orthonormalized(),feet[side].origin+view.model.global_basis*Vector3(0,0.3,1))
 update_attachment()
 # Entry and release blend skinned pose, not a timer-only prop toggle.
 var weight=smoothstep(0,1,amount)
 if weight<1:
  var posed=[]
  for i in skeleton.get_bone_count():posed.append(skeleton.get_bone_global_pose(i))
  for i in skeleton.get_bone_count():skeleton.set_bone_global_pose_override(i,standing[i].interpolate_with(posed[i],weight),1,true)
  skeleton.force_update_all_bone_transforms()

func rotate_model_bone(name,angle):
 var pose=bone_world(name)
 pose.basis=Basis(view.model.global_basis.x.normalized(),angle)*pose.basis
 set_world_bone(name,pose)

func set_world_bone(name,pose):
 skeleton.set_bone_global_pose_override(skeleton.find_bone("mixamorig_"+name),skeleton.global_transform.affine_inverse()*pose,1.0,true)
 skeleton.force_update_all_bone_transforms()

func solve_arm(side,target,hand_basis,pole):
 solve_limb(side+"Arm",side+"ForeArm",side+"Hand",target,hand_basis,pole)
func solve_limb(upper_name,lower_name,end_name,target,hand_basis,pole):
 var a=bone_world(upper_name)
 var b=bone_world(lower_name)
 var c=bone_world(end_name)
 var l1=a.origin.distance_to(b.origin)
 var l2=b.origin.distance_to(c.origin)
 var delta=target-a.origin
 var d=clampf(delta.length(),absf(l1-l2)+0.001,l1+l2-0.001)
 var axis=delta.normalized()
 var bend=(pole-a.origin)-axis*(pole-a.origin).dot(axis)
 bend=bend.normalized()
 var along=(l1*l1-l2*l2+d*d)/(2*d)
 var elbow=a.origin+axis*along+bend*sqrt(maxf(0,l1*l1-along*along))
 var wrist=a.origin+axis*d
 var upper=Basis(Quaternion((b.origin-a.origin).normalized(),(elbow-a.origin).normalized()))*a.basis
 set_world_bone(upper_name,Transform3D(upper,a.origin))
 b=bone_world(lower_name); c=bone_world(end_name)
 var lower=Basis(Quaternion((c.origin-b.origin).normalized(),(wrist-elbow).normalized()))*b.basis
 set_world_bone(lower_name,Transform3D(lower,elbow))
 set_world_bone(end_name,Transform3D(hand_basis.scaled(c.basis.get_scale()),wrist))

func apply_playing_grip():
 # Left-handed: RIGHT frets, LEFT strums; +Z strings stay outward.
 var hips=view.model.to_local(bone_world("Hips").origin)
 var rotation=Basis(Vector3.BACK,1.20)
 var local_pose=Transform3D(rotation*0.64,hips+Vector3(-0.03,0.23,0.18))
 guitar.global_transform=view.model.global_transform*local_pose
 var gb=guitar.global_transform.basis.orthonormalized()
 var right_target=guitar.to_global(Vector3(0.11,0.43,0.04))
 var left_target=guitar.to_global(Vector3(-0.11-0.055*sin(clock*TAU*5),-0.42,0.025))
 var right_basis=Basis(gb.y,-gb.x,gb.z)
 var left_basis=Basis(-gb.y,gb.x,gb.z)
 solve_arm("Right",right_target,right_basis,view.model.to_global(hips+Vector3(-0.62,-0.08,0.25)))
 solve_arm("Left",left_target,left_basis,view.model.to_global(hips+Vector3(0.55,-0.08,0.25)))
 # Export has one grouped Index chain per hand, not independent five fingers.
 # Curl those real skinned joints: no invented finger rig or mesh replacement.
 for side in ["Right","Left"]:
  for segment in [1,2,3]:
   var name=side+"HandIndex"+str(segment)
   var pose=bone_world(name)
   var axis=-gb.y if side=="Right" else gb.y
   pose.basis=Basis(axis,0.65 if side=="Right" else 0.8)*pose.basis
   set_world_bone(name,pose)
