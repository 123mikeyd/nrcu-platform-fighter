extends Node
# ISOLATED REVIEW: rigid body + external graphic jaws, not an anatomical jaw rig.
const HURT=preload("res://scripts/body_hurtboxes.gd")
const DURATION=0.32
var actor
var view
var cue:Node3D
var jaws=[]
var active=false
var elapsed=0.0
var direction=Vector3.RIGHT
var kind=""
var airborne=false
var targets=[]
var contacts=[]
var offset=Vector3.ZERO
var attack_facing=1.0
var base_center=Vector3.ZERO
func _ready():
 actor=get_parent();view=actor.get_node("VisualRoot/GGBVisual")
 cue=Node3D.new();cue.name="BiteCue_REVIEW";actor.add_child(cue);cue.visible=false
 var mat=StandardMaterial3D.new();mat.albedo_color=Color(1,.91,.63);mat.roughness=.8
 for side in [-1,1]:
  var jaw=Node3D.new();cue.add_child(jaw);jaws.append(jaw)
  var rail=MeshInstance3D.new();var mesh=BoxMesh.new();mesh.size=Vector3(.46,.045,.065);rail.mesh=mesh;rail.material_override=mat;rail.position.x=.59;jaw.add_child(rail)
  for i in 3:
   var tooth=MeshInstance3D.new();var cone=CylinderMesh.new();cone.top_radius=0;cone.bottom_radius=.043;cone.height=.105;cone.radial_segments=3;tooth.mesh=cone;tooth.material_override=mat
   tooth.position=Vector3(.44+i*.15,-side*.065,0);tooth.rotation.z=PI if side>0 else 0;jaw.add_child(tooth)
func start(aim:Vector2,air:bool):
 active=true;elapsed=0;targets.clear();contacts.clear();airborne=air
 kind="side"
 if absf(aim.x)>.1:actor.facing=signf(aim.x)
 attack_facing=actor.facing
 direction=Vector3(actor.facing,0,0)
 if absf(aim.y)>.1:
  kind="up" if aim.y<0 else "down"
  direction=Vector3.UP if aim.y<0 else Vector3.DOWN
 actor.attack_cooldown=DURATION;actor.last_move="BITE [REVIEW]";actor.attack_flash_time=0
 if kind!="side":actor.last_move=kind.to_upper()+" RAM [REVIEW]"
 if actor._attack_flash:actor._attack_flash.visible=false
 present()
func invalid()->bool:
 return not actor.controls_enabled or actor.stocks<=0 or actor.hitstun>0 or actor.freeze_remaining>0 or actor.magic_locked() or actor.drop_committed or (actor.tumble and actor.tumble.active) or (actor.revival and actor.revival.phase!="idle")
func before_tick():
 if active and invalid():cancel()
func cancel():
 active=false;elapsed=0;offset=Vector3.ZERO;targets.clear()
 cue.visible=false
 view.position=Vector3(0,0 if actor.drop_committed else view.NORMAL_HOVER,0)
func present():
 var drive=clampf((elapsed-.06)/.055,0,1) if elapsed<.17 else clampf((DURATION-elapsed)/.15,0,1)
 offset=direction*.18*drive
 if kind=="up":offset=Vector3.UP*.28*drive
 if kind=="down":
  offset=Vector3.DOWN*(.28 if airborne else .08)*drive
  if not airborne and elapsed<.09:offset=Vector3.UP*.14*sin(clampf(elapsed/.09,0,1)*PI)
 # Compact diagonal body ram: actual body, not a detached/remote hit sphere.
 # Pure vertical .28 movement could never bridge native capsule separation.
 if kind!="side":offset.x=attack_facing*.38*drive
 view.rotation.y=attack_facing*.48
 view.position=Vector3(0,view.NORMAL_HOVER,0)
 base_center=view.body_center_world()
 var body=SphereShape3D.new();body.radius=.43
 var sweep=PhysicsShapeQueryParameters3D.new();sweep.shape=body;sweep.transform=Transform3D(Basis.IDENTITY,base_center);sweep.motion=offset;sweep.collision_mask=2;sweep.margin=0;sweep.exclude=[actor.get_rid()]
 var fractions=actor.get_world_3d().direct_space_state.cast_motion(sweep)
 if not fractions.is_empty():offset*=fractions[0]
 view.position=Vector3(0,view.NORMAL_HOVER,0)+offset
 cue.visible=active and kind=="side"
 cue.position=view.body_center_world()-actor.global_position+Vector3(0,0,.12)
 cue.scale.x=attack_facing
 var gap=lerpf(.23,.07,clampf((elapsed-.075)/.075,0,1))
 jaws[0].position.y=-gap;jaws[1].position.y=gap
func tick(delta:float):
 if not active:return
 if invalid() or (airborne and actor.is_grounded()):cancel();return
 elapsed+=delta
 if elapsed>=DURATION:cancel();return
 present()
 if elapsed>=.09 and elapsed<=.18:
  if kind=="side":query(cue.to_global(Vector3(.64,0,0)),.12)
  else:query(view.body_center_world()+direction*.16,.27)
func query(point:Vector3,radius:float):
 var origin=base_center
 var ray=PhysicsRayQueryParameters3D.create(origin,point,2);ray.exclude=[actor.get_rid()]
 if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():return
 var s=SphereShape3D.new();s.radius=radius
 var q=PhysicsShapeQueryParameters3D.new();q.shape=s;q.transform=Transform3D(Basis.IDENTITY,point);q.collision_mask=7;q.margin=0
 HURT.prepare(actor,q)
 for hit in actor.get_world_3d().direct_space_state.intersect_shape(q,64):
  var target=HURT.resolve(hit.collider)
  if actor.can_hit(target) and target not in targets:
   targets.append(target);contacts.append({"time":elapsed,"point":str(point),"radius":radius,"target":str(target.name)})
   var launch=direction
   if kind=="side":launch.y=.35
   hit.position=point;HURT.deliver(target,8,launch,3.8,hit,actor)
