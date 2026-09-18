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
func _ready():
 actor=get_parent();view=actor._visual_root.get_node("DogeVisual");player=view.animation_player
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
func duration()->float:
 if clip=="Roundhouse25_42":return 17.0/30.0
 if clip=="LeadJab":return 4.0/3.0
 if clip=="FlurryRecovery":return player.get_animation("Punch4").length-.25
 return .25
func begin(next:String,blend:float):
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
 clip="";elapsed=0;buffered=false;blend_from.clear();targets.clear();actor.attack_cooldown=0
func before_tick():
 if not clip.is_empty() and (not actor.controls_enabled or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked()):cancel()
func before_move():
 if not clip.is_empty():actor.facing=direction
func present(t:float):
 if clip.is_empty():return
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
