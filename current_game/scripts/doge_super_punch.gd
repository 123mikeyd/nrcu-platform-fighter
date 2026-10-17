extends Node
# Isolated normal-grounded Ultimate-inspired candidate. No charge meter or reversal.
const START := 52.0/60.0
const END := 57.0/60.0 # exclusive: frame58
const TOTAL := 103.0/60.0 # frame104 input is legal
const DAMAGE := 25.0 # Reference damage; NRCU balance provisional.
const PUSH := 9.0 # Existing full-power Goalkeeper NRCU strength, NOT Smash BKB/KBG.
var actor
var view
var player: AnimationPlayer
var skeleton: Skeleton3D
var active := false
var elapsed := 0.0
var direction := 1.0
var serial := 0
var targets: Array = []
var contacts: Array = []
var geometry: Array = []
var morphs: Array = []
const VFX=preload("res://scripts/doge_punch_vfx.gd")
var windup_vfx: Node3D
var impact_vfx: Array = []
var impact_count := 0
var feedback_target: Node
func fist_position()->Vector3:
 var g=geometry[0] # Native right fist center, not an actor-origin offset.
 return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(g.bone))*vector(g.a)
func clear_vfx():
 feedback_target=null
 if is_instance_valid(windup_vfx):windup_vfx.queue_free()
 windup_vfx=null
 for effect in impact_vfx:
  if is_instance_valid(effect):effect.queue_free()
 impact_vfx.clear()
func update_windup():
 if elapsed>=.20 and elapsed<START:
  if not is_instance_valid(windup_vfx):
   windup_vfx=VFX.new();actor.add_child(windup_vfx)
  windup_vfx.global_position=fist_position();windup_vfx.pose(elapsed)
 elif is_instance_valid(windup_vfx):windup_vfx.queue_free();windup_vfx=null
 impact_vfx=impact_vfx.filter(func(effect):return is_instance_valid(effect) and not effect.is_queued_for_deletion())
func impact_at(point:Vector3):
 var effect=VFX.new();effect.impact=true;actor.add_child(effect)
 effect.top_level=true;effect.global_position=point
 impact_vfx.append(effect);impact_count+=1
func _ready():
 actor=get_parent();view=actor._visual_root.get_node("DogeVisual");player=view.animation_player
 skeleton=view.model.find_children("*","Skeleton3D",true,false)[0]
 var lib=load("res://assets/doge_man/super_doge_punch.tres")
 player.get_animation_library("").add_animation("SuperDogePunch",lib.get_animation("SuperDogePunch").duplicate(true))
 geometry=JSON.parse_string(FileAccess.get_file_as_string("res://assets/doge_man/super_doge_geometry.json"))
 for mesh in view.model.find_children("*","MeshInstance3D",true,false):
  for i in mesh.mesh.get_blend_shape_count():
   if "Left_Fist_STUDY" in str(mesh.mesh.get_blend_shape_name(i)):morphs.append([mesh,i,mesh.get_blend_shape_value(i)])
func committed()->bool:return active and elapsed<TOTAL-.000001
func start():
 if active or not actor.is_grounded():return
 clear_vfx();impact_count=0
 active=true;elapsed=0;direction=actor.facing;serial+=1;targets.clear();contacts.clear()
 actor.charging=false;actor.charge_time=0;actor.attack_cooldown=TOTAL;actor.last_move="SUPER DOGE PUNCH"
 actor.attack_flash_time=0
 if actor._attack_flash:actor._attack_flash.hide()
 for m in morphs:m[0].set_blend_shape_value(m[1],0.0)
 present()
func cancel():
 clear_vfx()
 if not active:return
 active=false;elapsed=0;targets.clear();actor.attack_cooldown=0
 for m in morphs:m[0].set_blend_shape_value(m[1],m[2])
 player.speed_scale=1;view.current_clip=""
func before_tick():
 if not active:return
 if not actor.controls_enabled or actor.stocks<=0 or actor.hitstun>0 or actor.freeze_remaining>0 or actor.sleep_remaining>0 or actor.magic_locked() or is_instance_valid(actor.caught_by) or (actor.tumble and actor.tumble.active):cancel();return
 if elapsed>=TOTAL-.000001:cancel()
func before_move():
 if not active:return
 actor.facing=direction;actor.velocity.x=0
func present():
 if not active:return
 actor._visual_root.scale=Vector3.ONE;view.flight_root.rotation=Vector3.ZERO;view.model.rotation.y=direction*PI/2
 view.current_clip="SuperDogePunch";player.play("SuperDogePunch",0);player.seek(minf(elapsed,TOTAL),true);player.pause()
 skeleton.force_update_all_bone_transforms()
 var hurt=actor.get_node_or_null("BodyHurtboxes")
 if hurt:hurt.sync()
 update_windup()
func after_tick(delta:float):
 if not active:return
 # Grounded-only first candidate: losing support cancels before outgoing contact.
 if not actor.is_grounded():cancel();return
 present()
 if elapsed>=START-.000001 and elapsed<END-.000001:query_contact()
 elapsed+=delta
 actor.attack_cooldown=0.0 if elapsed>=TOTAL-.000001 else TOTAL-elapsed
func vector(a)->Vector3:return Vector3(a[0],a[1],a[2])
func world_regions()->Array:
 var regions=[]
 for g in geometry:
  var xf:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(g.bone))
  regions.append({"a":xf*vector(g.a),"b":xf*vector(g.b),"radius":float(g.radius)*maxf(xf.basis.x.length(),maxf(xf.basis.y.length(),xf.basis.z.length())),"bone":g.bone})
 return regions
func query_contact():
 for g in world_regions():
  for target in get_tree().get_nodes_in_group("fighters"):
   if not actor.can_hit(target) or target in targets:continue
   for shape in target.get_hurtbox_shapes():
    if not shape is CollisionShape3D or shape.disabled or not shape.shape is CapsuleShape3D:continue
    var capsule:CapsuleShape3D=shape.shape;var xf:Transform3D=shape.global_transform
    var half=maxf(0,capsule.height*.5-capsule.radius)
    var a:Vector3=xf*Vector3(0,-half,0);var b:Vector3=xf*Vector3(0,half,0)
    var radius=capsule.radius*maxf(xf.basis.x.length(),maxf(xf.basis.y.length(),xf.basis.z.length()))
    var pair=Geometry3D.get_closest_points_between_segments(g.a,g.b,a,b)
    if pair[0].distance_to(pair[1])>g.radius+radius:continue
    var ray=PhysicsRayQueryParameters3D.create(pair[0],pair[1],3)
    var excluded:Array[RID]=[]
    for fighter in get_tree().get_nodes_in_group("fighters"):excluded.append(fighter.get_rid())
    ray.exclude=excluded
    if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
    targets.append(target)
    contacts.append({"time":elapsed,"serial":serial,"target":target.character_id,"bone":g.bone,"receiver":str(shape.name),"point":str(pair[0]),"receiver_axis":str(pair[1]),"radius":g.radius,"receiver_radius":radius,"separation":pair[0].distance_to(pair[1])})
    var before_damage:float=target.damage_percent
    var was_shielding:bool=target.shielding
    feedback_target=target
    preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,DAMAGE,Vector3(direction,.25,0),PUSH,shape,pair[1],pair[0],actor)
    feedback_target=null
    # Deliver is authoritative: shield/counter/protection/clank cannot spawn impact.
    if not was_shielding and target.damage_percent>before_damage:
     impact_at(pair[1]+(pair[0]-pair[1]).normalized()*radius)
    break
