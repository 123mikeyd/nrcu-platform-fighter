extends Node
# Doge-only native ground basics. Provisional source-speed timing, not final approval.
const LEAD_DEADLINE=.42
const LEAD_LINK=.50
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
func _ready():
 actor=get_parent();view=actor._visual_root.get_node("DogeVisual");player=view.animation_player
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
func duration()->float:
 # Provisional trial: unchanged active end 10/30, then three source frames
 # of native leg lowering before controls/locomotion return (13/30 total).
 if clip=="Roundhouse25_42":return 13.0/30.0
 if clip=="LeadJab":return 4.0/3.0
 if clip=="FlurryRecovery":return player.get_animation("Punch4").length-.25
 return .25
func begin(next:String,blend:float):
 if plant_valid:
  view.model.position=plant_model_position
  plant_valid=false
 blend_from.clear()
 for b in skeleton.get_bone_count():
  blend_from.append([skeleton.get_bone_pose_position(b),skeleton.get_bone_pose_rotation(b),skeleton.get_bone_pose_scale(b)])
 clip=next;elapsed=0;buffered=false;blend_seconds=blend;targets.clear()
 if clip!="FlurryRecovery":serial+=1
 actor.attack_cooldown=duration();actor.attack_flash_time=0
 if actor._attack_flash:actor._attack_flash.visible=false
 actor.last_move="ROUNDHOUSE" if clip=="Roundhouse25_42" else ("LEAD JAB" if clip=="LeadJab" else "ALTERNATING FLURRY")
 present(0)
func start(aim:Vector2):
 contacts.clear()
 direction=signf(aim.x) if absf(aim.x)>.1 else actor.facing
 actor.facing=direction
 begin("Roundhouse25_42" if absf(aim.x)>.1 else "LeadJab",0.0 if absf(aim.x)>.1 else .06)
func press():
 if not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or not actor.is_grounded():return
 if clip=="LeadJab" and elapsed<=LEAD_DEADLINE+.000001:buffered=true
 elif clip in ["Punch2","Punch3"] and elapsed>=.04 and elapsed<=.23:buffered=true
func cancel():
 if clip.is_empty():return
 if plant_valid:
  view.model.position=plant_model_position
  plant_valid=false
 clip="";elapsed=0;buffered=false;blend_from.clear();targets.clear();actor.attack_cooldown=0
func before_tick():
 if not clip.is_empty() and (not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked()):cancel()
func before_move():
 if not clip.is_empty():actor.facing=direction
 # Committed grounded basics own horizontal locomotion. Never pin the actor
 # transform or vertical velocity: jumps, lost support and hits retain physics.
 if clip in ["Roundhouse25_42","LeadJab","Punch2","Punch3","FlurryRecovery"] and actor.is_grounded() and actor.velocity.y<=0:
  actor.velocity.x=0
func present(t:float):
 if clip.is_empty():return
 if plant_valid:view.model.position=plant_model_position
 actor._visual_root.scale=Vector3.ONE;view.model.rotation.y=direction*PI/2
 var source_clip="Punch4" if clip=="FlurryRecovery" else clip
 var source_time=t+.25 if clip=="FlurryRecovery" else t
 view.current_clip=source_clip;player.play(source_clip,0);player.seek(source_time,true);player.pause()
 # Blend evaluated full local transforms, including hips/feet, not detached fists.
 # Time keeps advancing at original speed; damage will use this same posed rig.
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
 var finish=LEAD_LINK if clip=="LeadJab" and buffered else duration()
 var end=minf(elapsed+delta,finish)
 var t=elapsed
 while t<end-.000001:
  t=minf(t+1.0/240.0,end)
  query_contact(t)
 elapsed=end;present(elapsed);actor.attack_cooldown=maxf(0,finish-elapsed)
 if elapsed>=finish-.000001:
  if buffered:begin("Punch3" if clip=="Punch2" else "Punch2",.10 if clip=="LeadJab" else (.06 if clip=="Punch3" else .02))
  elif clip in ["Punch2","Punch3"]:begin("FlurryRecovery",.10)
  else:cancel()

func point(bone:String)->Vector3:
 return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin

func query_contact(t:float):
 var window={"LeadJab":Vector2(10.0/30.0,14.0/30.0),"Punch2":Vector2(.08,.18),"Punch3":Vector2(.07,.16),"Roundhouse25_42":Vector2(6.0/30.0,10.0/30.0)}.get(clip,Vector2(-1,-1))
 if t<window.x or t>window.y:return
 present(t)
 var limb="Right" if clip=="Punch2" else "Left"
 var a=point(limb+"Foot" if clip=="Roundhouse25_42" else limb+"ForeArm")
 var b=point(limb+"ToeBase" if clip=="Roundhouse25_42" else limb+"Hand")
 var radius=minf(.10,a.distance_to(b)*.30)
 # The roundhouse strikes with the shin as well as the foot. Retain the
 # original foot volume; add only knee-to-ankle at that same narrow radius.
 # Both segments share the strike ledger and the existing 240 Hz pose sweep.
 query_segment(t,limb,a,b,radius)
 if clip=="Roundhouse25_42":query_segment(t,limb,point(limb+"Leg"),a,radius)

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
   var damage=10.0 if clip=="Roundhouse25_42" else 8.0
   contacts.append({"clip":clip,"serial":serial,"time":t,"limb":limb,"point":str(pair[0]),"receiver_axis":str(pair[1]),"radius":radius,"receiver_radius":body_radius,"distance":pair[0].distance_to(pair[1]),"target":target.character_id,"region":str(shape.name),"actor_position":str(actor.global_position),"target_position":str(target.global_position),"damage":damage})
   preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,damage,Vector3(direction,.1,0),4.2 if clip=="Roundhouse25_42" else 1.0,shape,pair[1],pair[0], actor)
   break
