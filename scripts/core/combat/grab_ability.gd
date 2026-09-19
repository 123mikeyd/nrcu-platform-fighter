extends RefCounted
## Tick counter + unrounded source durations preserve phase remainders.
const CURVE = preload("res://data/contact/grab_curve.tres")
const START_END := 0.20 + 4.0 / 24.0
const END_LENGTH := 13.0 / 24.0
var age := 0
var facing := 1.0
var activation_id := ""
var hold_duration := 1.25
var phase := "startup"
var elapsed := 0.0
var victim := 0
var ordinal := 0
var contact_evidence: Dictionary = {}
var contact_geometry := "legacy_body_capsule"
var anchor_offset := Vector3.ZERO
var hand_reference := Vector3.ZERO
func _init(direction: float, identity: String, duration := 1.25):
	facing = direction; activation_id = identity; hold_duration = clampf(duration, 0.25, 2.5)
func cooldown_ticks() -> int:
	return int(ceil((START_END + hold_duration + END_LENGTH + 0.25) * 60.0 - 0.000001))
static func sample(clip: String, seconds: float, direction: float) -> Vector3:
	var points: PackedVector3Array = CURVE.get_meta(clip)
	var frame := clampf(seconds * 24.0, 0, points.size() - 1)
	var lower := int(floor(frame))
	return Basis(Vector3.UP, direction * PI / 2) * points[lower].lerp(points[mini(lower + 1, points.size() - 1)], frame - lower) * 1.25
func hand() -> Vector3:
	if phase == "startup":
		return sample("GrabStart", elapsed * (13.0 / 24.0) / 0.2 if elapsed <= 0.2 else 13.0 / 24.0 + elapsed - 0.2, facing)
	if phase == "hold": return sample("GrabLoop", fmod(elapsed, 1.25) if elapsed > 1.25 else elapsed, facing)
	return sample("GrabEnd", elapsed, facing)
func anchor(at: Vector3) -> Vector3:
	var delta := (hand() - hand_reference).limit_length(0.25); delta.z = 0
	return at + anchor_offset + delta
static func clear_path(actor, start: Vector3, end: Vector3, fighters: Dictionary) -> bool:
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	var excluded: Array[RID] = []
	for f in fighters.values():
		if is_instance_valid(f.actor): excluded.append(f.actor.get_rid())
	query.exclude = excluded; query.hit_from_inside = true
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
func closest(source_id: int, fighters: Dictionary, tick: int) -> int:
	contact_evidence.clear()
	contact_geometry = "legacy_body_capsule"
	var recipient = preload("res://scripts/core/collision/recipient_queries.gd")
	var source: Dictionary = fighters[source_id]
	var point: Vector3 = source.actor.global_position + sample("GrabStart", 13.0 / 24.0, facing)
	var best := 0; var best_distance := INF
	var ids := fighters.keys(); ids.sort()
	for id in ids:
		var target: Dictionary = fighters[id]
		if id == source_id or not target.enabled or not is_instance_valid(target.actor): continue
		if source.team >= 0 and source.team == target.team: continue
		if target.shield_command or target.frozen or target.caught_by != 0 or target.grab_immune_until > tick or target.grab != null or target.force != null: continue
		var offset: Vector3 = target.actor.global_position - source.actor.global_position
		if offset.length() > 1.85 or offset.x * facing <= 0: continue
		if recipient.generated(target):
			for capsule in recipient.primitives(target):
				var nearest := Geometry3D.get_closest_point_to_segment(point,capsule.a,capsule.b)
				var distance := point.distance_to(nearest)
				if distance <= float(capsule.radius)+.18 and distance < best_distance and clear_path(source.actor,source.actor.global_position+Vector3.UP,point,fighters) and clear_path(source.actor,point,nearest,fighters):
					best = id; best_distance = distance
					contact_geometry = "generated_hurtboxes"
					contact_evidence = recipient.evidence(target,capsule)
			# An absent/invalid/generated miss must not enter the native loop.
			continue
		for child in target.actor.get_children():
			if not child is CollisionShape3D or child.disabled or not child.shape is CapsuleShape3D: continue
			var shape: CapsuleShape3D = child.shape
			var transform: Transform3D = child.global_transform
			var axis := maxf(0, shape.height * 0.5 - shape.radius)
			var nearest := Geometry3D.get_closest_point_to_segment(point, transform * Vector3(0, -axis, 0), transform * Vector3(0, axis, 0))
			var distance := point.distance_to(nearest)
			var radius := shape.radius * maxf(transform.basis.x.length(), transform.basis.z.length())
			if distance <= radius + 0.18 and distance < best_distance and clear_path(source.actor, source.actor.global_position + Vector3.UP, point, fighters) and clear_path(source.actor, point, nearest, fighters):
				best = id; best_distance = distance
				contact_geometry = "legacy_body_capsule"; contact_evidence.clear()
	return best
