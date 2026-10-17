extends Node
# Approved v001 bounded airborne gather, plank and native-air exit.
# Additive native bone-only library includes baked object roll; actor hull untouched.
const HOLD_TIME=28.0/30.0
const LAND_LEAD=4.0/60.0
# User-requested side-A arc: one bounded entry launch, never an additive boost.
const ENTRY_SIDE_SPEED=3.0
var travel_speed=0.0
var phase="idle"
var unwind_elapsed=0.0
var unwind_pose=[]
var landing_prediction={}
const VIEWS={"teknium":"TekniumVisual","doge_man":"DogeVisual","turbofit":"TurboFitVisual","ice_mage":"IceMageVisual","witcheer":"WitcheerVisual","mephisto":"MephistoVisual"}
const HURT=preload("res://scripts/body_hurtboxes.gd")
# Conservative tempo pass: preserve all source poses and source active bounds.
# Source 0..6 / 6..14 / 14..28 maps to real 0..5 / 5..12 / 12..24 @30.
const DURATION=24.0/30.0
func source_time(real_time:float)->float:
 if real_time<=5.0/30.0:return real_time*6.0/5.0
 if real_time<=12.0/30.0:return 6.0/30.0+(real_time-5.0/30.0)*8.0/7.0
 return minf(HOLD_TIME,14.0/30.0+(real_time-12.0/30.0)*14.0/12.0)
const ACTIVE_START=6.0/30.0
const ACTIVE_END=14.0/30.0
var actor
var view
var skeleton:Skeleton3D
var player:AnimationPlayer
var active=false
var elapsed=0.0
var direction=1.0
var targets=[]
var contacts=[]
var release_attack=false
var serial=0
func _ready():
 actor=get_parent();view=actor._visual_root.get_node(VIEWS[actor.character_id])
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
 player=view.animation_player
 var library=load("res://assets/doge_man/dropkick_air_v001.tres").duplicate(true)
 player.add_animation_library("doge_air_drop",library)
 for bone in ["LeftFoot","LeftToeBase","RightFoot","RightToeBase"]:assert(skeleton.find_bone(bone)>=0)
func start(aim:Vector2)->bool:
 if active or actor.is_grounded() or not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or actor.shielding:return false
 active=true;phase="extension";unwind_elapsed=0;unwind_pose.clear();landing_prediction.clear();elapsed=0;direction=signf(aim.x);actor.facing=direction;targets.clear();contacts.clear();serial+=1
 travel_speed=direction*clampf(actor.velocity.x*direction,ENTRY_SIDE_SPEED,actor.MOVE_SPEED)
 actor.velocity.x=travel_speed
 actor.attack_cooldown=DURATION;actor.last_move="AIR DROP KICK"
 actor.attack_flash_time=0
 if actor._attack_flash:actor._attack_flash.visible=false
 present(0)
 return true
func cancel():
 if not active:return
 active=false;phase="idle";travel_speed=0;unwind_pose.clear();targets.clear();actor.attack_cooldown=0
 release_attack=actor._read_raw_controls(0).attack
 player.stop()
func filter_controls(input:Dictionary)->Dictionary:
 if release_attack:
  if not input.attack:release_attack=false
  else:input.attack=false
 return input
func before_tick():
 if active and (not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or actor._read_raw_controls(0).shield):cancel()
func _process(_delta):
 if active and (not actor.controls_enabled or actor.freeze_remaining>0 or actor.hitstun>0 or actor.magic_locked()):cancel()
func before_move():
 if active:
  actor.facing=direction;actor.attack_cooldown=maxf(actor.attack_cooldown,.1)
  # Carry the previous post-collision horizontal velocity through ordinary
  # input deceleration. Walls may stop it; held/reverse input cannot add speed.
  actor.velocity.x=travel_speed
var hurt_synced:=false
func present(time:float):
 hurt_synced=false
 actor._visual_root.scale=Vector3.ONE;actor._visual_root.rotation=Vector3.ZERO
 # Facing is already baked in the approved paired Actions; no second yaw flip.
 view.model.rotation.y=PI/2
 if actor.character_id=="teknium":view.position.y=0
 view.current_clip="doge_air_drop/DOGE_AIR_v001_"+("RIGHT_BODY" if direction>0 else "LEFT_BODY")
 player.speed_scale=1;player.play(view.current_clip,0);player.seek(minf(time,HOLD_TIME),true);player.pause()
 skeleton.force_update_all_bone_transforms()
func bone_point(bone:String)->Vector3:
 return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
func query(point:Vector3,radius:float,time:float):
 var shape=SphereShape3D.new();shape.radius=radius
 query_shape(shape,Transform3D(Basis.IDENTITY,point),point,radius,time)
func query_shin(knee:Vector3,ankle:Vector3,radius:float,time:float):
 var axis=ankle-knee
 var shape=CapsuleShape3D.new();shape.radius=radius;shape.height=axis.length()+2*radius
 var orientation=Basis(Quaternion(Vector3.UP,axis.normalized())) if axis.length_squared()>.00000001 else Basis.IDENTITY
 var center=(knee+ankle)*.5
 query_shape(shape,Transform3D(orientation,center),center,radius,time)
func query_shape(shape:Shape3D,transform:Transform3D,point:Vector3,radius:float,time:float):
 var q=PhysicsShapeQueryParameters3D.new();q.shape=shape;q.transform=transform;q.collision_mask=7;q.margin=0
 if hurt_synced:HURT.prepare_presynced(actor,q)
 else:HURT.prepare(actor,q);hurt_synced=true
 for hit in actor.get_world_3d().direct_space_state.intersect_shape(q,64):
  var target=HURT.resolve(hit.collider)
  if actor.can_hit(target) and target not in targets:
   targets.append(target)
   contacts.append({"time":time,"source_frame":1+time*30,"point":str(point),"radius":radius,"target":target.character_id,"collider":str(hit.collider.name),"shape":hit.shape,"receiver":"fitted anatomy" if hit.collider.has_meta("hurtbox_actor") else "existing movement capsule"})
   hurt_synced=false
   hit.position=point;HURT.deliver(target,8.0,Vector3(direction,0,0),3.8,hit, actor)
func after_tick(delta:float):
 if not active:return
 travel_speed=actor.velocity.x
 if not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked():cancel();return
 if actor.is_grounded():cancel();actor._update_move_visuals();return
 if phase=="unwind":
  unwind_elapsed+=delta;present_unwind();return
 landing_prediction=predict_landing()
 if not landing_prediction.is_empty():
  phase="unwind";unwind_elapsed=0;unwind_pose.clear()
  present(source_time(elapsed))
  for i in skeleton.get_bone_count():unwind_pose.append(skeleton.get_bone_pose(i))
  present_unwind();return
 var end=minf(elapsed+delta,DURATION);var t=source_time(elapsed)
 var source_end=source_time(end)
 while t<source_end-.000001:
  t=minf(t+1.0/480.0,source_end)
  if t>=ACTIVE_START and t<=ACTIVE_END:
   present(t)
   for limb in ["Left","Right"]:
    var ankle=bone_point(limb+"Foot");var toe=bone_point(limb+"ToeBase")
    # Retain native ankle-to-toe spheres; no invisible forward/actor-range reach.
    var radius=minf(.10,ankle.distance_to(toe)*.25)
    for fraction in [0.0,.25,.5,.75,1.0]:query(ankle.lerp(toe,fraction),radius,t)
    # Cover only the striking shin, using the unchanged foot radius and active
    # source-clock sweep. No thigh, torso, extra reach, or second hit ledger.
    query_shin(bone_point(limb+"Leg"),ankle,radius,t)
 elapsed=end;present(source_time(elapsed))
 if elapsed>=DURATION-.000001:
  active=false;phase="idle";travel_speed=0;targets.clear();actor.attack_cooldown=0
  release_attack=actor._read_raw_controls(0).attack
  # f29 already restores native air frame12. Rebase into ordinary facing
  # before handing off: blending a baked LEFT root under a new -90 yaw
  # double-mirrors the outgoing pose for a frame.
  view.model.rotation.y=direction*PI/2
  view.current_clip="MidairMoves2";player.play("MidairMoves2",0)
  player.seek(12.0/30.0,true);player.advance(0)
  actor._update_move_visuals(0)

func predict_landing()->Dictionary:
 if actor.velocity.y>=0:return {}
 var params=PhysicsTestMotionParameters3D.new()
 params.from=actor.global_transform
 var gravity=actor.ssb_movement.gravity() if actor.ssb_movement else actor.GRAVITY
 params.motion=actor.velocity*LAND_LEAD+Vector3.DOWN*gravity*LAND_LEAD*LAND_LEAD*.5
 params.margin=actor.safe_margin;params.max_collisions=32
 var exclude:Array[RID]=[]
 for fighter in get_tree().get_nodes_in_group("fighters"):
  if fighter is PhysicsBody3D:exclude.append(fighter.get_rid())
 for platform in get_tree().get_nodes_in_group("pass_through_platforms"):
  var top=float(platform.get_meta("top_y",platform.global_position.y))
  if actor.global_position.y<top-.06 or (platform==actor._drop_platform and actor._drop_time>0):exclude.append(platform.get_rid())
 params.exclude_bodies=exclude
 var result=PhysicsTestMotionResult3D.new()
 if PhysicsServer3D.body_test_motion(actor.get_rid(),params,result):
  for i in result.get_collision_count():
   var collider=result.get_collider(i)
   if is_instance_valid(collider) and not collider.is_in_group("fighters") and result.get_collision_normal(i).dot(actor.up_direction)>=cos(actor.floor_max_angle):
    return {"elapsed":elapsed,"y":actor.global_position.y,"velocity_y":actor.velocity.y,"safe_fraction":result.get_collision_safe_fraction(),"collider":str(collider.name)}
 return {}

func present_unwind():
 view.model.rotation.y=PI/2
 view.current_clip="MidairMoves2"
 player.play("MidairMoves2",0);player.seek(0,true);player.pause()
 if direction<0:
  # Paired source is baked under a fixed model yaw. Express the ordinary
  # opposite-facing target in that same space before interpolating bones.
  var hips=skeleton.find_bone("Hips")
  var pose=skeleton.get_bone_pose(hips)
  pose=Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)*pose
  skeleton.set_bone_pose(hips,pose)
 var u=smoothstep(0,LAND_LEAD,unwind_elapsed)
 for i in skeleton.get_bone_count():
  var pose:Transform3D=unwind_pose[i].interpolate_with(skeleton.get_bone_pose(i),u)
  skeleton.set_bone_pose_position(i,pose.origin)
  skeleton.set_bone_pose_rotation(i,pose.basis.get_rotation_quaternion())
  skeleton.set_bone_pose_scale(i,pose.basis.get_scale())
 skeleton.force_update_all_bone_transforms()
