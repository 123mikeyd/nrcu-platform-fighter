extends Node
# Humanoid arm rigs only. Native assets are immutable; each library is a rest-baked derivative.
const VIEWS={"teknium":"TekniumVisual","doge_man":"DogeVisual","turbofit":"TurboFitVisual","ice_mage":"IceMageVisual","witcheer":"WitcheerVisual","mephisto":"MephistoVisual"}
const HURT=preload("res://scripts/body_hurtboxes.gd")
var duration=.5
var active_start=5.0/30.0
var active_end=6.0/30.0
var move="neutral"
var clip="Neutral"
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
var wrist_name="RightToeBase"
var elbow_name="RightFoot"
func _ready():
 actor=get_parent();view=actor._visual_root.get_node(VIEWS[actor.character_id])
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
 player=view.animation_player
 for kind in ["neutral","down","up"]:
  var library=load("res://assets/air_basic/"+kind+"/"+actor.character_id+".tres").duplicate(true)
  # Reuse the currently imported donor clips exactly on their native fighter.
  if actor.character_id=="turbofit" and kind in ["neutral","down"]:
   library=AnimationLibrary.new()
   library.add_animation("Neutral" if kind=="neutral" else "Down",player.get_animation("AirSideKick" if kind=="neutral" else "AirDownKick").duplicate(true))
  if actor.character_id=="teknium" and kind=="up":
   library=AnimationLibrary.new()
   library.add_animation("Up",load("res://assets/reactions/teknium_air_up.tres").get_animation("Backflip33_73").duplicate(true))
  player.add_animation_library("humanoid_air_"+kind,library)
 if actor.character_id=="turbofit":wrist_name="mixamorig_RightToe_End";elbow_name="mixamorig_RightFoot"
 assert(skeleton.find_bone(wrist_name)>=0 and skeleton.find_bone(elbow_name)>=0)
func start(aim:Vector2)->bool:
 if active or actor.is_grounded() or not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or actor.shielding:return false
 move="up" if aim.y<-.1 else ("down" if aim.y>.1 else "neutral")
 clip="Up" if move=="up" else ("Down" if move=="down" else "Neutral")
 duration=.6 if move=="up" else (38.0/30.0 if move=="down" else .5)
 active_start=18.5/30.0 if move=="up" else (.4 if move=="down" else 5.0/30.0)
 active_end=27.75/30.0 if move=="up" else (.5 if move=="down" else 6.0/30.0)
 var side="Left" if move=="down" else "Right"
 wrist_name=("mixamorig_"+side+"Toe_End") if actor.character_id=="turbofit" else side+"ToeBase"
 elbow_name=("mixamorig_" if actor.character_id=="turbofit" else "")+side+"Foot"
 active=true;elapsed=0;direction=signf(aim.x) if absf(aim.x)>.1 else actor.facing;actor.facing=direction;targets.clear();contacts.clear();serial+=1
 actor.attack_cooldown=duration;actor.last_move="AIR BACKFLIP 33-73" if move=="up" else ("AIR DOWN KICK" if move=="down" else "AIR NEUTRAL KICK")
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
 view.current_clip="humanoid_air_"+move+"/"+clip
 player.speed_scale=1;player.play("humanoid_air_"+move+"/"+clip,0);player.seek(source_time(time),true);player.pause()
 skeleton.force_update_all_bone_transforms()
func bone_point(bone:String)->Vector3:
 return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
func query(point:Vector3,radius:float,time:float):
 var shape=SphereShape3D.new();shape.radius=radius
 var q=PhysicsShapeQueryParameters3D.new();q.shape=shape;q.transform=Transform3D(Basis.IDENTITY,point);q.collision_mask=7;q.margin=0
 HURT.prepare(actor,q)
 for hit in actor.get_world_3d().direct_space_state.intersect_shape(q,64):
  var target=HURT.resolve(hit.collider)
  if actor.can_hit(target) and target not in targets and (move!="down" or target.global_position.y<actor.global_position.y):
   targets.append(target)
   contacts.append({"time":time,"source_time":source_time(time),"source_frame":(33 if move=="up" else (4 if move=="down" else 36))+source_time(time)*30,"point":str(point),"radius":radius,"target":target.character_id,"collider":str(hit.collider.name),"shape":hit.shape,"receiver":"fitted anatomy" if hit.collider.has_meta("hurtbox_actor") else "existing movement capsule"})
   hit.position=point;HURT.deliver(target,8.0 if move=="up" else 14.0,Vector3.DOWN if move=="down" else Vector3(direction,0 if move=="up" else .35,0),3.8 if move=="up" else 5.5,hit)
func source_time(t:float)->float:
 return air_up_source_time(t) if move=="up" else t
const AIR_UP_SPEED := 2.0
const AIR_UP_HALF_TIME := 8.0/15.0
const AIR_UP_HALF_SOURCE := 20.0/30.0
func air_up_source_time(t: float) -> float:
 t=clampf(t*AIR_UP_SPEED,0,AIR_UP_HALF_TIME+AIR_UP_HALF_SOURCE)
 if t>=AIR_UP_HALF_TIME:return AIR_UP_HALF_SOURCE+t-AIR_UP_HALF_TIME
 var u=t/AIR_UP_HALF_TIME
 return AIR_UP_HALF_TIME*(1.5*u-.5*u*u*u+.25*u*u*u*u)

func air_up_elapsed_time(source: float) -> float:
 source=clampf(source,0,2*AIR_UP_HALF_SOURCE)
 if source>=AIR_UP_HALF_SOURCE:return (AIR_UP_HALF_TIME+source-AIR_UP_HALF_SOURCE)/AIR_UP_SPEED
 var lo=0.0;var hi=AIR_UP_HALF_TIME/AIR_UP_SPEED
 for i in 32:
  var mid=(lo+hi)*.5
  if air_up_source_time(mid)<source:lo=mid
  else:hi=mid
 return (lo+hi)*.5 if source>0 else 0.0

func air_up_sample_next(t: float,end: float) -> float:
 # Source-domain240Hz also guarantees >=240Hz real-time at rates2..3.
 # Keep the exact callback endpoint; do not discard its fractional interval.
 var source_end=air_up_source_time(end)
 var next_source=air_up_source_time(t)+1.0/240.0
 return end if next_source>=source_end else air_up_elapsed_time(next_source)

func after_tick(delta:float):
 if not active:return
 if actor.is_grounded() or not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked():cancel();return
 var end=minf(elapsed+delta,duration);var t=elapsed
 while t<end-.000001:
  t=air_up_sample_next(t,end) if move=="up" else minf(t+1.0/240.0,end)
  var source=source_time(t)
  if source>=active_start and source<=active_end:
   present(t)
   if move=="up":
    var prefix="mixamorig_" if actor.character_id=="turbofit" else ""
    var hips=bone_point(prefix+"Hips")
    for side in ["Left","Right"]:
     var knee=bone_point(prefix+side+"Leg");var ankle=bone_point(prefix+side+"Foot");var toe=bone_point(prefix+side+"ToeBase")
     for fraction in [0.0,.25,.5,.75,1.0]:
      var shin=knee.lerp(ankle,fraction);var foot=ankle.lerp(toe,fraction)
      if shin.y>hips.y:query(shin,.10,t)
      if foot.y>hips.y:query(foot,.10,t)
   else:
    var elbow=bone_point(elbow_name);var wrist=bone_point(wrist_name)
    # Conservative core on the native foot; never widened to recover misses.
    var radius=minf(.22,elbow.distance_to(wrist)*.5)
    query(elbow.lerp(wrist,.5),radius,t)
 elapsed=end;present(elapsed)
 if elapsed>=duration:cancel();actor._update_move_visuals(0,true)
