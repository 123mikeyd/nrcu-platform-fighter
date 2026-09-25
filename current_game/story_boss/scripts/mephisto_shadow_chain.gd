extends Node3D
# One world-space polyline drives the visible tendril and (separately) contact.
const LENGTH=2.8
const RADIUS=.085
const TIP_RADIUS=.17
const SEGMENTS=24
var moves
var points=PackedVector3Array()
var direction=Vector3.RIGHT
var links=[]
var wisps=[]
var smoke_material:ShaderMaterial
var tip:MeshInstance3D
const HIT_INTERVAL=.30
var next_hit={}
var release_extension=0.0
var visual_clock=0.0
func contact_shape(a:Vector3,b:Vector3,radius:float,shape)->Array:
 var xf:Transform3D=shape.global_transform
 var half=maxf(0,shape.shape.height*.5-shape.shape.radius)
 var pair=Geometry3D.get_closest_points_between_segments(a,b,xf*Vector3(0,-half,0),xf*Vector3(0,half,0))
 var body_radius=shape.shape.radius*maxf(xf.basis.x.length(),xf.basis.z.length())
 return [pair[0],pair[1]] if pair[0].distance_to(pair[1])<=radius+body_radius else []
func hit_targets():
 if moves.move!="ShadowChain" or moves.elapsed<.30:return
 for target in get_tree().get_nodes_in_group("fighters"):
  if not moves.actor.can_hit(target) or moves.elapsed<next_hit.get(target.get_instance_id(),0.0):continue
  var hit=[];var receiving;var tip_hit=false
  var shapes=target.get_hurtbox_shapes()
  # Tip has priority when both touch, with one shared per-target cadence.
  for shape in shapes:
   if not shape is CollisionShape3D or shape.disabled or not shape.shape is CapsuleShape3D:continue
   hit=contact_shape(points[-1],points[-1],TIP_RADIUS,shape)
   if not hit.is_empty():receiving=shape;tip_hit=true;break
  if hit.is_empty():
   for shape in shapes:
    if not shape is CollisionShape3D or shape.disabled or not shape.shape is CapsuleShape3D:continue
    for i in SEGMENTS:
     hit=contact_shape(points[i],points[i+1],RADIUS,shape)
     if not hit.is_empty():receiving=shape;break
    if not hit.is_empty():break
  if not hit.is_empty():
   next_hit[target.get_instance_id()]=moves.elapsed+HIT_INTERVAL
   var damage=6.0 if tip_hit else 2.0
   var launch=Vector3(direction.x,.35+maxf(0,direction.y),0).normalized()
   moves.contacts.append({"move":"ShadowChain","elapsed":moves.elapsed,"target":target.character_id,"damage":damage,"kind":"tip" if tip_hit else "length","point":str(hit[0]),"radius":TIP_RADIUS if tip_hit else RADIUS})
   preload("res://scripts/body_hurtboxes.gd").deliver_capsule(target,damage,launch,3.6 if tip_hit else 1.4,receiving,hit[1],hit[0],moves.actor)
func _ready():
 add_to_group("mephisto_shadow_chain")
 direction=Vector3(moves.facing,0,0)
 var material=StandardMaterial3D.new();material.albedo_color=Color(.13,.07,.21);material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 for i in SEGMENTS:
  var part=MeshInstance3D.new();var mesh=CapsuleMesh.new();mesh.radius=RADIUS;mesh.height=.3;mesh.radial_segments=8;mesh.rings=2;part.mesh=mesh;part.material_override=material;add_child(part);links.append(part)
 tip=MeshInstance3D.new();var orb=SphereMesh.new();orb.radius=TIP_RADIUS;orb.height=TIP_RADIUS*2;tip.mesh=orb
 var bright=StandardMaterial3D.new();bright.albedo_color=Color(.85,.39,1);bright.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;tip.material_override=bright;add_child(tip)
 var halo=Node3D.new();halo.name="SmokeHalo";add_child(halo)
 smoke_material=ShaderMaterial.new();smoke_material.shader=preload("res://story_boss/scripts/mephisto_shadow_chain.gdshader")
 var noise=FastNoiseLite.new();noise.seed=818;noise.frequency=.06
 var texture=NoiseTexture2D.new();texture.width=64;texture.height=64;texture.noise=noise;texture.seamless=true
 smoke_material.set_shader_parameter("noise_tex",texture)
 for i in SEGMENTS+1:
  var wisp=MeshInstance3D.new();var quad=QuadMesh.new();quad.size=Vector2.ONE*.42;wisp.mesh=quad;wisp.material_override=smoke_material;halo.add_child(wisp);wisps.append(wisp)
 update_shape(0)
func update_shape(delta:float):
 var input=moves.actor._read_raw_controls(0)
 var aim=Vector3(float(int(input.right)-int(input.left)),float(int(input.up)-int(input.down)),0)
 if moves.move=="ShadowChain" and aim.length_squared()>.1:
  # Angular steering handles antiparallel input; normalized linear lerp sticks.
  var angle=lerp_angle(atan2(direction.y,direction.x),atan2(aim.y,aim.x),minf(1,delta*9))
  direction=Vector3(cos(angle),sin(angle),0)
 var origin:Vector3=moves.view().demon_point("DEF-hand.R")
 var perpendicular=Vector3(-direction.y,direction.x,0)
 var extension=smoothstep(.12,.30,moves.elapsed) if moves.move=="ShadowChain" else release_extension*(1.0-smoothstep(0,moves.duration(),moves.elapsed))
 points.clear()
 for i in SEGMENTS+1:
  var u=float(i)/SEGMENTS
  var point=origin+direction*LENGTH*u*extension+perpendicular*sin(u*TAU*1.2-visual_clock*5)*.13*sin(u*PI)*extension
  # The native free hand is off-plane. Bend the VISIBLE manifestation into
  # combat depth, rather than flattening only its contact query or widening it.
  point.z=lerpf(origin.z,moves.actor.global_position.z,smoothstep(0,.4,u)*extension)
  points.append(point)
 for i in SEGMENTS:
  var a=points[i];var b=points[i+1];var axis=b-a
  links[i].global_position=(a+b)*.5
  links[i].mesh.height=maxf(RADIUS*2,axis.length()+RADIUS*2)
  if axis.length_squared()>.000001:
   var y=axis.normalized();var x=Vector3(0,0,1).cross(y).normalized();links[i].global_basis=Basis(x,y,x.cross(y))
 tip.global_position=points[-1]
 smoke_material.set_shader_parameter("phase",visual_clock)
 for i in wisps.size():wisps[i].global_position=points[i]
func tick(delta:float):
 visual_clock+=delta
 if moves.move=="ShadowChain" and not moves.actor._read_raw_controls(0).special:
  release_extension=smoothstep(.12,.30,moves.elapsed)
  moves.chain_animation().release()
  update_shape(0);return
 update_shape(delta)
 if moves.move=="ShadowChain":hit_targets()
