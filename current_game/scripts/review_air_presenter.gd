extends Node
# Isolated native recipient fit. Controller remains sole movement/input owner.
var actor
var view
var skeleton:Skeleton3D
var data
var indices=[]
var initial=[]
var expected=[]
var active=false
var exiting=false
var exit_poses=[]
var exit_yaw=0.0
var exit_clock=0.0
var exit_jumps=0
var weak_clock=0.0
var source_time=0.0
func _ready():
 actor=get_parent()
 view=actor._visual_root.get_node("TekniumVisual" if actor.character_id=="teknium" else "TurboFitVisual")
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
 data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/"+actor.character_id+"/reduced_tuck_review.json"))
 for name in data.names:
  var i=skeleton.find_bone(name);assert(i>=0);indices.append(i)
func vec(v):return Vector3(v[0],v[1],v[2])
func transform(raw):return Transform3D(Basis(vec(raw[0]),vec(raw[1]),vec(raw[2])),vec(raw[3]))
func sample(i):
 var f=clampf(source_time*data.fps,0,data.poses.size()-1)
 return transform(data.poses[int(f)][i]).interpolate_with(transform(data.poses[mini(int(f)+1,data.poses.size()-1)][i]),f-floorf(f))
func present(t,strong):
 if not active:
  initial.clear()
  for i in indices:initial.append(skeleton.get_bone_pose(i))
 active=true;exiting=false
 # Strong starts at frame7 like Doge. Small uses native frame4 recoil,
 # a provisional role fit, not a newly approved static endpoint.
 source_time=.2+t if strong else .1
 var side=signf(actor.velocity.x)
 view.model.rotation.y=-(side if side!=0 else -actor.facing)*PI/2
 if actor.character_id=="teknium":
  view.jump_active=false;view.position.y=0;view.placement_target=0;view.placement_elapsed=.06
 else:view.cancel_power_chord();view.falling=false;view.landing_remaining=0
 view.animation_player.pause();view.current_clip="ReviewAirNative"
 expected.clear()
 for n in indices.size():
  var pose=initial[n].interpolate_with(sample(n),smoothstep(0,.065,t))
  expected.append(pose);skeleton.set_bone_pose(indices[n],pose)
 skeleton.force_update_all_bone_transforms()
func finish():
 if not active:return
 active=false;weak_clock=0
 exiting=actor.hitstun<=0 and not actor.is_grounded() and actor.controls_enabled and actor.stocks>0
 exit_clock=0;exit_jumps=actor.jumps_used;exit_poses.clear();exit_yaw=view.model.rotation.y
 for i in indices:exit_poses.append(skeleton.get_bone_pose(i))
 view.current_clip="";view.animation_player.speed_scale=1;view.model.rotation.y=actor.facing*PI/2
func action_owns():
 return actor.jumps_used!=exit_jumps or actor.attack_cooldown>0 or actor.charging or actor.recovery_active>0 or actor.humanoid_air_basic.active or actor.humanoid_air_side.active or (actor.character_id=="teknium" and (view.jump_active or actor.teknium_magic.phase!="idle" or actor.teknium_specials.phase!="idle"))
func _physics_process(delta):
 if not actor.controls_enabled or actor.stocks<=0 or actor.freeze_remaining>0 or is_instance_valid(actor.caught_by):
  finish();exiting=false;return
 if actor.tumble.active:return
 if actor.hitstun>0 and not actor.is_grounded():
  weak_clock+=delta;present(weak_clock,false);return
 if active:finish()
 if not exiting:return
 if action_owns() or actor.is_grounded() or actor.hitstun>0:
  exiting=false;return
 exit_clock+=delta
 # Target the native controller's actual air pose; do not substitute Idle.
 var target="Jump" if actor.character_id=="teknium" else ("FallLoop" if actor.velocity.y<=0 else "Jump")
 view.current_clip=target;view.animation_player.play(target,0,1)
 view.animation_player.seek(view.animation_player.get_animation(target).length if actor.character_id=="teknium" else exit_clock,true)
 view.animation_player.advance(0);view.animation_player.pause()
 var weight=smoothstep(0,.08,exit_clock)
 view.model.rotation.y=lerp_angle(exit_yaw,actor.facing*PI/2,weight)
 for n in indices.size():skeleton.set_bone_pose(indices[n],exit_poses[n].interpolate_with(skeleton.get_bone_pose(indices[n]),weight))
 skeleton.force_update_all_bone_transforms()
 if exit_clock>=.08:
  exiting=false
  if actor.character_id=="turbofit":view.animation_player.play()
func pose_error():
 var error=0.0
 for n in expected.size():
  var actual=skeleton.get_bone_pose(indices[n]);error=maxf(error,actual.origin.distance_to(expected[n].origin))
  for k in 3:error=maxf(error,actual.basis[k].distance_to(expected[n].basis[k]))
 return error
