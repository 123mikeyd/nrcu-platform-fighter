extends Node
# Humanoid arm rigs only. Native assets are immutable; each library is a rest-baked derivative.
const VIEWS={"teknium":"TekniumVisual","doge_man":"DogeVisual","turbofit":"TurboFitVisual","ice_mage":"IceMageVisual","witcheer":"WitcheerVisual","mephisto":"MephistoVisual"}
const HURT=preload("res://scripts/body_hurtboxes.gd")
const DURATION=10.0/24.0
const ACTIVE_START=7.25/24.0
const ACTIVE_END=9.0/24.0
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
var wrist_name="LeftHand"
var elbow_name="LeftForeArm"
func _ready():
 actor=get_parent();view=actor._visual_root.get_node(VIEWS[actor.character_id])
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
 player=view.animation_player
 var library=load("res://assets/air_superman/"+actor.character_id+".tres").duplicate(true)
 player.add_animation_library("humanoid_air_side",library)
 if actor.character_id=="turbofit":wrist_name="mixamorig_LeftHand";elbow_name="mixamorig_LeftForeArm"
 assert(skeleton.find_bone(wrist_name)>=0 and skeleton.find_bone(elbow_name)>=0)
func start(aim:Vector2)->bool:
 if active or actor.is_grounded() or not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or actor.shielding:return false
 active=true;elapsed=0;direction=signf(aim.x);actor.facing=direction;targets.clear();contacts.clear();serial+=1
 actor.attack_cooldown=DURATION;actor.last_move="AIR SUPERMAN"
 actor.attack_flash_time=0
 if actor._attack_flash:actor._attack_flash.visible=false
 present(0)
 return true
func cancel():
 if not active:return
 active=false;targets.clear();actor.attack_cooldown=0
 release_attack=actor._read_raw_controls(0).attack
 player.stop()
func filter_controls(input:Dictionary)->Dictionary:
 if release_attack:
  if not input.attack:release_attack=false
  else:input.attack=false
 return input
func before_tick():
 if active and (not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or actor._read_raw_controls(0).shield):cancel()
func before_move():
 if active:actor.facing=direction
func present(time:float):
 actor._visual_root.scale=Vector3.ONE;actor._visual_root.rotation=Vector3.ZERO
 view.model.rotation.y=direction*PI/2
 if actor.character_id=="teknium":view.position.y=0
 view.current_clip="humanoid_air_side/Superman"
 player.speed_scale=1;player.play("humanoid_air_side/Superman",0);player.seek(time,true);player.pause()
 skeleton.force_update_all_bone_transforms()
func bone_point(bone:String)->Vector3:
 return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
func query(point:Vector3,radius:float,time:float):
 var shape=SphereShape3D.new();shape.radius=radius
 var q=PhysicsShapeQueryParameters3D.new();q.shape=shape;q.transform=Transform3D(Basis.IDENTITY,point);q.collision_mask=7;q.margin=0
 HURT.prepare(actor,q)
 for hit in actor.get_world_3d().direct_space_state.intersect_shape(q,64):
  var target=HURT.resolve(hit.collider)
  if actor.can_hit(target) and target not in targets:
   targets.append(target)
   contacts.append({"time":time,"source_frame":25+time*24,"point":str(point),"radius":radius,"target":target.character_id,"collider":str(hit.collider.name),"shape":hit.shape,"receiver":"fitted anatomy" if hit.collider.has_meta("hurtbox_actor") else "existing movement capsule"})
   hit.position=point;HURT.deliver(target,8.0,Vector3(direction,0,0),3.8,hit)
func after_tick(delta:float):
 if not active:return
 if actor.is_grounded() or not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked():cancel();return
 var end=minf(elapsed+delta,DURATION);var t=elapsed
 while t<end-.000001:
  t=minf(t+1.0/240.0,end)
  if t>=ACTIVE_START and t<=ACTIVE_END:
   present(t)
   var elbow=bone_point(elbow_name);var wrist=bone_point(wrist_name)
   # Samples on native anatomy, no forward reach or actor-range damage.
   var radius=minf(.10,elbow.distance_to(wrist)*.25)
   for fraction in [0.0,.25,.5,.75,1.0]:query(elbow.lerp(wrist,fraction),radius,t)
 elapsed=end;present(elapsed)
 if elapsed>=DURATION:cancel();actor._update_move_visuals(0,true)
