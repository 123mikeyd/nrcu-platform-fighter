extends "res://scripts/approved_fitted_reaction.gd"
# Isolated Doge-only subclass. Base ground reactions remain byte-identical.
func present_sample(t):
 if not actor.is_grounded() and actor.hitstun>0:
  if not actor.tumble.active:trial_present(t,false)
  return
 super.present_sample(t)
func _physics_process(delta):
 tick(delta)
 trial_exit_tick(delta)
func tick(delta):
 if trial_active and actor.tumble.active:return
 super.tick(delta)
func clear():
 if trial_active:
  trial_exit_active=actor.hitstun<=0 and not actor.is_grounded() and actor.controls_enabled and actor.stocks>0
  trial_exit_clock=0;trial_exit_poses.clear()
  if trial_exit_active:
   for name in trial_data.names:trial_exit_poses.append(skeleton.get_bone_pose(skeleton.find_bone(name)))
   trial_exit_yaw=actor._visual_root.get_node("DogeVisual").model.rotation.y
  trial_active=false;trial_initial.clear();trial_expected.clear()
  actor._visual_root.get_node("DogeVisual").model.rotation.y=actor.facing*PI/2
 super.clear()

# ISOLATED UNAPPROVED ART TRIAL. No actor travel, resources or timing writes.
var trial_data: Dictionary = {}
var trial_initial: Array = []
var trial_expected: Array = []
var trial_active := false
var trial_source_time := 0.0
func trial_transform(raw):
 return Transform3D(Basis(vec(raw[0]),vec(raw[1]),vec(raw[2])),vec(raw[3]))
func trial_present(t:float,strong:bool):
 if trial_data.is_empty():trial_data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/doge_man/trial_air_poses.json"))
 if not trial_active:
  trial_initial.clear()
  for name in trial_data.names:trial_initial.append(skeleton.get_bone_pose(skeleton.find_bone(name)))
 trial_exit_active=false
 trial_active=true;active=true
 var view=actor._visual_root.get_node("DogeVisual")
 view.cancel_up_special();view.jump_elapsed=-1;view.fall_elapsed=-1
 var side=signf(actor.velocity.x) if strong else incoming_side
 view.model.rotation.y=-(side if side!=0 else -actor.facing)*PI/2
 view.animation_player.pause()
 trial_source_time=.2+t if strong else 0.0
 var f=clampf(trial_source_time*120,0,trial_data.poses.size()-1)
 var weight=smoothstep(0,.065,t)
 trial_expected.clear()
 for i in trial_data.names.size():
  var pose=trial_transform(trial_data.static.small[i])
  if strong:
   pose=trial_transform(trial_data.poses[int(f)][i]).interpolate_with(trial_transform(trial_data.poses[mini(int(f)+1,trial_data.poses.size()-1)][i]),f-floorf(f))
  pose=trial_initial[i].interpolate_with(pose,weight)
  trial_expected.append(pose)
  skeleton.set_bone_pose(skeleton.find_bone(trial_data.names[i]),pose)
 skeleton.force_update_all_bone_transforms()
func trial_pose_error():
 var error=0.0
 for i in trial_expected.size():
  var actual=skeleton.get_bone_pose(skeleton.find_bone(trial_data.names[i]))
  error=maxf(error,actual.origin.distance_to(trial_expected[i].origin))
  error=maxf(error,actual.basis.get_rotation_quaternion().angle_to(trial_expected[i].basis.get_rotation_quaternion()))
 return error

# Newly authored 80ms presentation-only exit; never owns input or movement.
var trial_exit_active := false
var trial_exit_clock := 0.0
var trial_exit_poses: Array = []
var trial_exit_yaw := 0.0
func trial_exit_tick(delta):
 if not trial_exit_active:return
 var view=actor._visual_root.get_node("DogeVisual")
 var combat=actor.attack_cooldown>0 or actor.charging or actor.torpedo_phase!="idle" or actor.recovery_active>0 or actor.air_doge.active() or actor.humanoid_air_basic.active or actor.humanoid_air_side.active or actor.doge_air_drop.active or view.jump_elapsed>=0
 if combat or actor.is_grounded() or actor.hitstun>0 or not actor.controls_enabled or actor.stocks<=0 or actor.freeze_remaining>0 or is_instance_valid(actor.caught_by):
  trial_exit_active=false
  return
 trial_exit_clock+=delta
 # Sample the current native moving air target, never a standing Idle.
 if view.current_clip!="MidairMoves2":
  view.current_clip="MidairMoves2";view.animation_player.play("MidairMoves2",0)
 view.animation_player.speed_scale=1
 view.animation_player.seek(trial_exit_clock,true);view.animation_player.advance(0);view.animation_player.pause()
 var weight=smoothstep(0,.08,trial_exit_clock)
 view.model.rotation.y=lerp_angle(trial_exit_yaw,actor.facing*PI/2,weight)
 for i in trial_data.names.size():
  var bone=skeleton.find_bone(trial_data.names[i])
  skeleton.set_bone_pose(bone,trial_exit_poses[i].interpolate_with(skeleton.get_bone_pose(bone),weight))
 skeleton.force_update_all_bone_transforms()
 if trial_exit_clock>=.08:
  trial_exit_active=false;trial_exit_poses.clear();view.animation_player.play()
