extends RefCounted
# Narrow mesh-bound palm/boot queries for the two approved grounded basics.
# These are enclosing limb volumes, not exact triangle collision or extra reach.
const HURT=preload("res://scripts/body_hurtboxes.gd")
static var bounds:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/witcheer/witcheer_basic_bounds.json")).bones
static func sample(actor,from_time:float,to_time:float)->void:
 var move:Dictionary=actor.witcheer_moves[actor.witcheer_clip]
 var start=maxf(from_time,float(move.active_start));var end=minf(to_time,float(move.active_end))
 if start>end:return
 var view=actor._visual_root.get_node("WitcheerVisual")
 var sk:Skeleton3D=view.model.find_children("*","Skeleton3D",true,false)[0]
 var name="RightHand" if actor.witcheer_clip=="NeutralHook" else "RightFoot"
 var spec:Dictionary=bounds[name];var bone_index=sk.find_bone(name)
 var t=start
 while t<=end+.000001:
  view.show_move(actor.witcheer_clip,t,actor.witcheer_facing);sk.force_update_all_bone_transforms()
  var bone=sk.global_transform*sk.get_bone_global_pose(bone_index)
  var center=bone*Vector3(spec.center[0],spec.center[1],spec.center[2])
  var shape=SphereShape3D.new();shape.radius=float(spec.radius)*maxf(bone.basis.x.length(),maxf(bone.basis.y.length(),bone.basis.z.length()))
  var query=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,center);query.collision_mask=7
  HURT.prepare(actor,query)
  var space=actor.get_world_3d().direct_space_state;var hits=space.intersect_shape(query,64)
  for hit in hits:
   var target=HURT.resolve(hit.collider)
   if not actor.can_hit(target) or target in actor.witcheer_basic_targets:continue
   actor.witcheer_basic_targets.append(target);actor.witcheer_struck=true
   var contact=HURT.shape_contact(space,query,hit,hits)
   var direction:float=-actor.witcheer_facing if actor.witcheer_clip=="TurnaroundKick" else actor.witcheer_facing
   HURT.deliver(target,float(move.damage),Vector3(direction,.35,0),3.8,contact)
  if t>=end-.000001:break
  t=minf(t+1.0/240.0,end)
