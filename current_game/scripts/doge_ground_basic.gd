extends Node
# Doge-only native ground basics.
# Neutral basic = V5 "Thanos" 6-hit boxing string (installed 2026-09-28, replaces
# Lead Jab + Alternating Flurry). Side basic = Roundhouse25_42 (unchanged).
# Each fresh basic press during a punch queues the next punch; no press = short
# recovery blend back to Idle. One hit ledger per punch, sampled at 240 Hz on the
# same controller clock that poses the rig (native hand/forearm, not actor range).
const BOX:="BoxingString6"
const BOX_RECOVER:="BoxingRecover"
const BOX_FPS:=30.0
const BOX_CONTACT:=[11.0,24.0,40.0,54.0,68.0,84.0]       # source frames @30 (V5 validation)
const BOX_HAND:=["Right","Left","Right","Left","Right","Left"]
const BOX_NAME:=["RIGHT UPPERCUT","LEFT JAB","BIG RIGHT HOOK","LEFT UPPERCUT","RIGHT CROSS","LEFT HOOK"]
const BOX_DAMAGE:=[5.0,4.0,6.0,5.0,6.0,8.0]
const BOX_PUSH:=[0.0,0.0,0.0,0.0,0.0,4.5]   # 1-5 keep the victim in range; hook 6 launches
const BOX_LIFT:=[0.0,0.0,0.0,0.0,0.0,.35]
const BOX_ACTIVE_PRE:=3.0     # frames before contact (fist is already travelling fast)
const BOX_ACTIVE_POST:=2.0    # frames after contact (drive-through)
# Tempo (2026-09-29, Mike: "faster first punch, tighter gaps, shorter recovery
# after each tap; not too fast"). Contact frames/poses stay the V5 source; only
# the playback clock is sped up. Internal timings above stay in SOURCE seconds.
var box_speed_open:=1.5      # source-clock rate until punch 1 contact (wind-up)
var box_speed:=1.3           # source-clock rate for the rest of the string
var box_decide_after:=3.0    # source frames after contact: continue or recover
var box_recover_time:=.14    # real seconds: held pose blends back to Idle
const BOX_HOLD_PUSH:=0.3     # m/s cap on horizontal pushback for string hits 1-5 (hook 6 launches normally)
const BOX_KNUCKLE_CM:=9.0     # knuckle offset along the hand bone (rig centimetres)
var actor
var view
var player:AnimationPlayer
var skeleton:Skeleton3D
var clip=""
var elapsed=0.0
var direction=1.0
var serial=0
var buffered=false
var blend_from=[]
var blend_seconds=0.0
var targets=[]
var contacts=[]
var plant_valid=false
var plant_anchor=Vector3.ZERO
var plant_model_position=Vector3.ZERO
var box_index=0
func _ready():
 actor=get_parent();view=actor._visual_root.get_node("DogeVisual");player=view.animation_player
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
func box_decide(i:int)->float:
 return (BOX_CONTACT[i]+box_decide_after)/BOX_FPS
func rate(t:float)->float:
 if clip!=BOX:return 1.0
 return box_speed_open if t<BOX_CONTACT[0]/BOX_FPS else box_speed
func real_remaining(t:float,finish:float)->float:
 # Real seconds from source time t to source time finish at the tempo clock.
 if clip!=BOX:return maxf(0,finish-t)
 var c0:float=BOX_CONTACT[0]/BOX_FPS
 var a:float=maxf(0,minf(finish,c0)-t)/box_speed_open
 return a+maxf(0,finish-maxf(t,c0))/box_speed
func box_segment_start(i:int)->float:
 return 0.0 if i==0 else box_decide(i-1)
func duration()->float:
 # Provisional trial: unchanged active end 10/30, then three source frames
 # of native leg lowering before controls/locomotion return (13/30 total).
 if clip=="Roundhouse25_42":return 13.0/30.0
 if clip==BOX:return box_decide(box_index)
 if clip==BOX_RECOVER:return box_recover_time
 return .25
func begin(next:String,blend:float):
 if plant_valid:
  view.model.position=plant_model_position
  plant_valid=false
 blend_from.clear()
 for b in skeleton.get_bone_count():
  blend_from.append([skeleton.get_bone_pose_position(b),skeleton.get_bone_pose_rotation(b),skeleton.get_bone_pose_scale(b)])
 clip=next;elapsed=0;buffered=false;blend_seconds=blend;targets.clear()
 if clip!=BOX_RECOVER:serial+=1
 if clip==BOX:box_index=0
 actor.attack_cooldown=real_remaining(0,duration());actor.attack_flash_time=0
 if actor._attack_flash:actor._attack_flash.visible=false
 update_label()
 present(0)
func update_label():
 if clip=="Roundhouse25_42":actor.last_move="ROUNDHOUSE"
 elif clip in [BOX,BOX_RECOVER]:actor.last_move="BOXING %d/6 %s"%[box_index+1,BOX_NAME[box_index]]
func start(aim:Vector2):
 contacts.clear()
 direction=signf(aim.x) if absf(aim.x)>.1 else actor.facing
 actor.facing=direction
 begin("Roundhouse25_42" if absf(aim.x)>.1 else BOX,0.0 if absf(aim.x)>.1 else .08)
func press():
 if not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or not actor.is_grounded():return
 # A fresh press during the current punch queues the next one (any time after
 # a short 0.05 s guard so the starting press itself can never double-count).
 if clip==BOX and box_index<BOX_CONTACT.size()-1 and elapsed>=box_segment_start(box_index)+.05:buffered=true
func cancel():
 if clip.is_empty():return
 if plant_valid:
  view.model.position=plant_model_position
  plant_valid=false
 clip="";elapsed=0;buffered=false;blend_from.clear();targets.clear();actor.attack_cooldown=0;box_index=0
func before_tick():
 if not clip.is_empty() and (not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked()):cancel()
func before_move():
 if not clip.is_empty():actor.facing=direction
 # Committed grounded basics own horizontal locomotion. Never pin the actor
 # transform or vertical velocity: jumps, lost support and hits retain physics.
 if clip in ["Roundhouse25_42",BOX,BOX_RECOVER] and actor.is_grounded() and actor.velocity.y<=0:
  actor.velocity.x=0
func present(t:float):
 if clip.is_empty():return
 if plant_valid:view.model.position=plant_model_position
 actor._visual_root.scale=Vector3.ONE;view.model.rotation.y=direction*PI/2
 # Recovery blends the held string pose into Idle's first frame; locomotion
 # then continues Idle from there.
 var source_clip="Idle" if clip==BOX_RECOVER else clip
 var source_time=0.0 if clip==BOX_RECOVER else t
 view.current_clip=source_clip;player.play(source_clip,0);player.seek(source_time,true);player.pause()
 # Blend evaluated full local transforms, including hips/feet, not detached fists.
 var weight=smoothstep(0,blend_seconds,t) if blend_seconds>0 else 1.0
 if weight<1.0:
  for b in skeleton.get_bone_count():
   skeleton.set_bone_pose_position(b,blend_from[b][0].lerp(skeleton.get_bone_pose_position(b),weight))
   skeleton.set_bone_pose_rotation(b,blend_from[b][1].slerp(skeleton.get_bone_pose_rotation(b),weight))
   skeleton.set_bone_pose_scale(b,blend_from[b][2].lerp(skeleton.get_bone_pose_scale(b),weight))
 skeleton.force_update_all_bone_transforms()
 # Rigid presentation-root compensation, not IK or source-pose editing.
 # Query and final presentation both pass here at the same source clock.
 # The toe is the support pivot; foot rotation/heel lift remains authored.
 if clip=="Roundhouse25_42":
  if not plant_valid:
   plant_model_position=view.model.position
   plant_anchor=point("RightToeBase")
   plant_valid=true
  view.model.global_position+=plant_anchor-point("RightToeBase")
func after_tick(delta:float):
 if clip.is_empty():return
 if not actor.is_grounded():cancel();return
 var finish=duration()
 # Advance the source clock at the tempo rate (split at the wind-up boundary).
 var src:float=elapsed;var left:float=delta
 if clip==BOX and src<BOX_CONTACT[0]/BOX_FPS:
  var c0:float=BOX_CONTACT[0]/BOX_FPS
  var need:float=(c0-src)/box_speed_open
  if left<need:src+=left*box_speed_open;left=0
  else:src=c0;left-=need
 src+=left*rate(src)
 var end=minf(src,finish)
 var t=elapsed
 while t<end-.000001:
  t=minf(t+1.0/240.0,end)
  query_contact(t)
 elapsed=end;present(elapsed)
 actor.attack_cooldown=real_remaining(elapsed,finish)+(box_recover_time if clip==BOX else 0.0)
 if elapsed>=finish-.000001:
  if clip==BOX:
   if buffered and box_index<BOX_CONTACT.size()-1:
    # Continue the same clip without a blend: the next punch is already keyed.
    box_index+=1;buffered=false;targets.clear();serial+=1;update_label()
    actor.attack_cooldown=real_remaining(elapsed,duration())+box_recover_time
   else:
    begin(BOX_RECOVER,box_recover_time)
  else:cancel()

func point(bone:String)->Vector3:
 return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin

func knuckle(limb:String)->Vector3:
 var hand:=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(limb+"Hand"))
 return hand*Vector3(0,BOX_KNUCKLE_CM,0)

func box_active(t:float)->bool:
 var c:float=BOX_CONTACT[box_index]
 return t>=(c-BOX_ACTIVE_PRE)/BOX_FPS and t<=(c+BOX_ACTIVE_POST)/BOX_FPS

func query_contact(t:float):
 if clip==BOX:
  if not box_active(t):return
  present(t)
  var hand:String=BOX_HAND[box_index]
  var elbow=point(hand+"ForeArm");var wrist=point(hand+"Hand")
  # Fist volume: mid-forearm to knuckles, same narrow radius rule as before.
  query_segment(t,hand,elbow.lerp(wrist,.5),knuckle(hand),minf(.10,elbow.distance_to(wrist)*.30))
  return
 var window={"Roundhouse25_42":Vector2(6.0/30.0,10.0/30.0)}.get(clip,Vector2(-1,-1))
 if t<window.x or t>window.y:return
 present(t)
 var limb="Left"
 var a=point(limb+"Foot")
 var b=point(limb+"ToeBase")
 var radius=minf(.10,a.distance_to(b)*.30)
 # The roundhouse strikes with the shin as well as the foot. Retain the
 # original foot volume; add only knee-to-ankle at that same narrow radius.
 # Both segments share the strike ledger and the existing 240 Hz pose sweep.
 query_segment(t,limb,a,b,radius)
 query_segment(t,limb,point(limb+"Leg"),a,radius)

func query_segment(t:float,limb:String,a:Vector3,b:Vector3,radius:float):
 for target in get_tree().get_nodes_in_group("fighters"):
  if not actor.can_hit(target) or target in targets or (target.global_position.x-actor.global_position.x)*direction<=0:continue
  for shape in target.get_hurtbox_shapes():
   if not shape is CollisionShape3D or shape.disabled or not shape.shape is CapsuleShape3D:continue
   var capsule:CapsuleShape3D=shape.shape
   var transform:Transform3D=shape.global_transform
   var half=maxf(0,capsule.height*.5-capsule.radius)
   var c=transform*Vector3(0,-half,0);var d=transform*Vector3(0,half,0)
   var body_radius=capsule.radius*maxf(transform.basis.x.length(),transform.basis.z.length())
   var pair=Geometry3D.get_closest_points_between_segments(a,b,c,d)
   if pair[0].distance_to(pair[1])>radius+body_radius:continue
   targets.append(target)
   var box:bool=clip==BOX
   var damage=(BOX_DAMAGE[box_index] if box else 10.0)
   var push=(BOX_PUSH[box_index] if box else 4.2)
   var lift=(BOX_LIFT[box_index] if box else .1)
   contacts.append({"clip":clip,"punch":(box_index+1 if box else 0),"serial":serial,"time":t,"limb":limb,"point":str(pair[0]),"receiver_axis":str(pair[1]),"radius":radius,"receiver_radius":body_radius,"distance":pair[0].distance_to(pair[1]),"target":target.character_id,"region":str(shape.name),"actor_position":str(actor.global_position),"target_position":str(target.global_position),"damage":damage})
   preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,damage,Vector3(direction,lift,0),push,shape,pair[1],pair[0], actor)
   # String hits 1-5 keep the victim in front of Doge: damage and hitstun are
   # unchanged, only the horizontal slide is capped (hook 6 launches normally).
   if box and box_index<BOX_CONTACT.size()-1 and absf(target.velocity.x)>BOX_HOLD_PUSH:
    target.velocity.x=signf(target.velocity.x)*BOX_HOLD_PUSH
   break
