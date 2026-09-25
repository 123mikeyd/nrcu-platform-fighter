extends Node
# Girl-owned bounded mechanics. No changes to the accepted demon kit.
var moves
var fx:MeshInstance3D
var ember=Vector3.ZERO
var origin=Vector3.ZERO
var reflected=[]
var released_early=false
var teleported=false
var travel=Vector3.UP
const DEPART=16.0/24.0
const VANISH=.16
const ARRIVE=20.0/24.0
func actor():return moves.actor
func view():return moves.view()
func protected_window()->bool:
 return (moves.move=="Barrier" and moves.elapsed>=.20 and moves.elapsed<=.55) or (moves.move in ["PairTeleport","PairVanish"] and moves.elapsed>=DEPART and moves.elapsed<DEPART+VANISH)
func sphere(radius:float,color:Color):
 if is_instance_valid(fx):fx.queue_free()
 fx=MeshInstance3D.new();fx.name="Girl2MagicEffect"
 var mesh=SphereMesh.new();mesh.radius=radius;mesh.height=radius*2;fx.mesh=mesh
 var material=StandardMaterial3D.new();material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.albedo_color=color;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.cull_mode=BaseMaterial3D.CULL_DISABLED
 fx.material_override=material;actor().get_parent().add_child(fx);fx.add_to_group("girl2_magic_effects")
func begin(id:String):
 reflected.clear();released_early=false;teleported=false;origin=actor().global_position
 if id=="EmberHold":actor().charging=true;actor().charge_time=0
 if id in ["PairTeleport","PairVanish"]:actor().recovery_spent=true;actor().jumps_used=2;travel=Vector3.UP
func cancel():
 if is_instance_valid(fx):fx.queue_free()
 fx=null;reflected.clear();released_early=false
 if view():
  view().visible=true
  if moves.move in ["EmberHold","EmberRelease"]:view().native_skeleton.clear_bones_global_pose_override()
func release():
 if moves.elapsed<.75:released_early=true;return
 actor().charging=false;actor().charge_time=0
 moves.move="EmberRelease";moves.elapsed=0;actor().attack_cooldown=moves.duration();actor().last_move="EMBER BURST"
 sphere(.65,Color(1,.28,.04,.52));fx.global_position=ember
func present():
 var v=view();var t=moves.elapsed
 if moves.move=="PairVanish":
  v.pose_frame(1,moves.facing);v.visible=not (t>=DEPART and t<DEPART+VANISH);return
 v.pose_frame(704,moves.facing);v.show_native_girl(moves.facing)
 match moves.move:
  "Barrier":v.native_pose("Barrier",t)
  "EmberHold","EmberRelease":preload("res://story_boss/scripts/mephisto_ember_pose.gd").present(v,moves.move,t)
  "PairTeleport":
   v.visible=not (t>=DEPART and t<DEPART+VANISH)
   v.native_pose("TeleportDepart",t) if t<DEPART+VANISH else v.native_pose("TeleportArrive",t-DEPART-VANISH)
func tick(delta:float):
 var t=moves.elapsed
 match moves.move:
  "Barrier":
   if t>=.20 and t<=.55:
    if not is_instance_valid(fx):
     sphere(1.15,Color(1,.36,.06,.8))
     var ring=TorusMesh.new();ring.inner_radius=1.08;ring.outer_radius=1.15;fx.mesh=ring
     fx.rotation.x=PI/2
    var center:Vector3=view().girl_point("Hips")+Vector3.UP*.2
    fx.global_position=center;fx.rotation.y=t*9
    for projectile in get_tree().get_nodes_in_group("projectiles"):
     if not is_instance_valid(projectile) or projectile.is_queued_for_deletion() or projectile in reflected or not projectile.has_method("reflect"):continue
     if projectile.get_meta("girl2_reflect_frame",-1)==Engine.get_physics_frames():continue
     var source=projectile.get("source")
     if not is_instance_valid(source) or source==actor() or not source.can_hit(actor()):continue
     if projectile.global_position.distance_to(center)<=1.5:
      reflected.append(projectile)
      projectile.set_meta("girl2_reflect_frame",Engine.get_physics_frames())
      var old_life=projectile.get("lifetime")
      projectile.reflect(actor(),Color(1,.35,.06))
      if old_life!=null:projectile.set("lifetime",old_life)
    moves.query_hand(center,.85,6.0,Vector3(moves.facing,.2,0),2.6)
   elif is_instance_valid(fx):fx.queue_free();fx=null
  "EmberHold":
   if t>=.75:
    if not is_instance_valid(fx):
     sphere(.15,Color(1,.25,.035,.9));ember=view().girl_point("RightHand");ember.z=actor().global_position.z;origin=ember
    var input=actor()._read_raw_controls(0)
    var vertical=float(int(input.up)-int(input.down))
    var next=ember+Vector3(moves.facing*2.8,vertical*2.2,0)*delta
    var ray=PhysicsRayQueryParameters3D.create(ember,next,2)
    var hit=actor().get_world_3d().direct_space_state.intersect_ray(ray)
    if not hit.is_empty():next=hit.position
    ember=next;fx.global_position=ember
    if released_early or not input.special or t>=3.25 or ember.distance_to(origin)>=7.0 or not hit.is_empty():release()
  "EmberRelease":
   if t>=.18 and t<=.32:
    moves.query_hand(ember,.65,11.0,Vector3(moves.facing,.35,0),4.2)
   if is_instance_valid(fx):
    fx.scale=Vector3.ONE*(.23 if t<.18 else 1.0+minf(t-.18,.22)*1.5)
    fx.material_override.albedo_color.a=maxf(0,.52*(1-t/.5))
    if t>=.5:fx.queue_free();fx=null
  "PairTeleport","PairVanish":
   if moves.move=="PairVanish" and t>=.50 and t<DEPART:
    if not is_instance_valid(fx):sphere(.85,Color(.48,.19,.68,.5))
    fx.global_position=actor().global_position+Vector3.UP
    moves.query_hand(fx.global_position,.85,8.0,Vector3(moves.facing,.4,0),3.5)
   if t<.55:
    var input=actor()._read_raw_controls(0)
    var direction=Vector3(float(int(input.right)-int(input.left)),float(int(input.up)-int(input.down)),0)
    if direction.length_squared()>.1:travel=direction.normalized()
   if t>=DEPART and not teleported:
    teleported=true
    actor().velocity=Vector3.ZERO
    var displacement=travel*4.5
    var capsule=CapsuleShape3D.new();capsule.radius=.42;capsule.height=1.8
    var query=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.collision_mask=2;query.transform=Transform3D(Basis.IDENTITY,actor().global_position+Vector3.UP*.95);query.motion=displacement;query.margin=.04
    var safe=actor().get_world_3d().direct_space_state.cast_motion(query)
    var destination:Vector3=actor().global_position+displacement*maxf(0,safe[0]-.025)
    destination.x=clampf(destination.x,-19,19);destination.y=clampf(destination.y,-3,15);destination.z=0
    actor().global_position=destination
    sphere(.7,Color(.8,.22,.05,.3));fx.global_position=destination+Vector3.UP
   if t>=DEPART and t<DEPART+VANISH:actor().velocity=Vector3.ZERO
   if is_instance_valid(fx) and t>.9:fx.queue_free();fx=null
