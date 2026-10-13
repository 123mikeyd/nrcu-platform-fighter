extends RefCounted
# Physical straight shaft only, measured from the approved prop below its gold head.
# No fighter-origin reach box and no ornamental-head damage.
const HURT = preload("res://scripts/body_hurtboxes.gd")
const A = Vector3(0, -0.9530329704, 0)
const B = Vector3(0, 0.5538161397, 0)
const RADIUS = 0.05373597665
static func shaft_transform(view) -> Transform3D:
 var sk: Skeleton3D = view.model.find_children("*", "Skeleton3D", true, false)[0]
 sk.force_update_all_bone_transforms()
 # BoneAttachment3D updates deferred; query the current posed bone directly.
 return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftHand")) * view.cane.transform
static func sample(actor, from_time: float, to_time: float) -> void:
 var clip: String = actor.witcheer_clip
 var move: Dictionary = actor.witcheer_moves[clip]
 var start: float = maxf(from_time, float(move.active_start))
 var end: float = minf(to_time, float(move.active_end))
 if start > end: return
 var view = actor._visual_root.get_node("WitcheerVisual")
 var t: float = start
 while t <= end + 0.000001:
  view.show_move(clip, t, actor.witcheer_facing)
  var m: Transform3D = shaft_transform(view)
  var a: Vector3 = m * A; var b: Vector3 = m * B
  var radius: float = RADIUS * maxf(m.basis.x.length(), maxf(m.basis.y.length(), m.basis.z.length()))
  var shape := CapsuleShape3D.new()
  shape.radius = radius
  shape.height = maxf(a.distance_to(b), radius * 2.0)
  var rotation := Quaternion(Vector3.UP, (b-a).normalized())
  var query := PhysicsShapeQueryParameters3D.new()
  query.shape = shape; query.transform = Transform3D(Basis(rotation), (a+b)*0.5)
  query.collision_mask = 7; query.margin = 0.001
  HURT.prepare(actor, query)
  var space = actor.get_world_3d().direct_space_state
  var hits = space.intersect_shape(query, 64)
  for hit in hits:
   var target = HURT.resolve(hit.collider)
   if not actor.can_hit(target) or target in actor.witcheer_basic_targets: continue
   actor.witcheer_basic_targets.append(target); actor.witcheer_struck = true
   var contact = HURT.shape_contact(space, query, hit, hits)
   HURT.deliver(target, float(move.damage), Vector3(actor.witcheer_facing, .35, 0), 3.8, contact, actor)
  if t >= end - 0.000001: break
  t = minf(t + 1.0/384.0, end)
 # Restore the current clock rather than leaving the sampled active-end pose.
 view.show_move(clip, to_time, actor.witcheer_facing)
