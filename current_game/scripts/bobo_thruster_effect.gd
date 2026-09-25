extends Node3D
# Gameplay-only exhaust. Rendering and contact use the same bounded cylinders.
const HURT=preload("res://scripts/body_hurtboxes.gd")
const LENGTH:=0.9
const RADIUS:=0.16
var jets: Array[MeshInstance3D]=[]
var orb:MeshInstance3D
func _ready():
 for i in 2:
  var mesh=MeshInstance3D.new();var cylinder=CylinderMesh.new()
  cylinder.height=LENGTH;cylinder.top_radius=RADIUS;cylinder.bottom_radius=RADIUS
  mesh.mesh=cylinder;add_child(mesh);jets.append(mesh)
  var mat=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
  mat.albedo_color=Color(.25,.8,1);mesh.material_override=mat
 orb=MeshInstance3D.new();var sphere=SphereMesh.new();sphere.radius=.2;sphere.height=.4;orb.mesh=sphere;add_child(orb)
 var material=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(.7,.95,1);orb.material_override=material
 hide()
func powered(actor) -> bool:
 return (actor.special_move=="up" and actor.special_time>=17.0/30.0 and actor.special_time<63.0/30.0) or (actor.special_move=="side" and actor.special_time>=18.0/30.0 and actor.special_time<41.0/30.0)
func present(actor):
 show()
 orb.visible=actor.special_move=="neutral_charge"
 if orb.visible:
  orb.global_position=actor.special_hand_world("LeftHand")
  orb.scale=Vector3.ONE*lerpf(.5,1.8,actor.charge_time/actor.MAX_CHARGE_TIME)
 for i in 2:
  var jet=jets[i];jet.visible=powered(actor)
  if not jet.visible:continue
  var direction=Vector3.DOWN if actor.special_move=="up" else Vector3(-actor.special_facing,0,0)
  jet.global_position=actor.special_hand_world("LeftHand" if i==0 else "RightHand")+direction*LENGTH*.5
  jet.global_basis=Basis.IDENTITY if actor.special_move=="up" else Basis(Vector3.FORWARD,PI/2)
func contact(actor):
 if not visible or not powered(actor) or not actor.special_allowed() or actor.counter_hitstop>0:return
 var space=actor.get_world_3d().direct_space_state
 for jet in jets:
  if not jet.visible:continue
  var shape=CylinderShape3D.new();shape.height=LENGTH;shape.radius=RADIUS
  var q=PhysicsShapeQueryParameters3D.new();q.shape=shape;q.transform=jet.global_transform;q.collision_mask=5;q.margin=0
  HURT.prepare(actor,q)
  var hits=space.intersect_shape(q,32)
  for hit in hits:
   var target=HURT.resolve(hit.collider)
   if not actor.can_hit(target) or target in actor.special_targets:continue
   var contact=HURT.shape_contact(space,q,hit,hits)
   # Main terrain is layer1; pass-through platforms are layer2.
   var ray=PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP,jet.global_position,3)
   ray.exclude=[actor.get_rid(),target.get_rid()]
   if not space.intersect_ray(ray).is_empty():continue
   actor.special_targets.append(target)
   HURT.deliver(target,5.0,Vector3(actor.special_facing*.2,-1,0) if actor.special_move=="up" else Vector3(-actor.special_facing,.2,0),2.0,contact,actor)
