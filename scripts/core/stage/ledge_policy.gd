extends Resource
## Pure caller-owned state and proposals. No Node callbacks or actor mutation.
## P5 proposed tuning only; these do not alter the accepted movement profile.
@export var protection_ticks: int = 30
@export var regrab_ticks: int = 45
@export var max_hang_ticks: int = 180
@export var jump_velocity: Vector3 = Vector3(4, 10, 0)
@export var drop_speed: float = 2.0

func advance(previous: Dictionary, actors: Dictionary, anchors: Array, tick: int, clear_path: Callable, actor_clear_path: Callable = Callable()) -> Dictionary:
	var state: Dictionary = previous.duplicate(true)
	if not state.has("actors"): state.actors = {}
	var proposals := {}
	# Exactly once per committed simulation tick; replay/paused calls are inert.
	if tick <= int(state.get("tick", -1)): return {"state": state, "proposals": proposals}
	state.tick = tick
	var by_id := {}
	var duplicates := {}
	for anchor in anchors:
		if by_id.has(anchor.anchor_id): duplicates[anchor.anchor_id] = true
		else: by_id[anchor.anchor_id] = anchor
	for key in duplicates: by_id.erase(key)
	by_id.erase("")
	for id in state.actors.keys():
		if not actors.has(id): state.actors.erase(id)
	var ids = actors.keys(); ids.sort()
	# Release pass precedes contest pass, independent of actor order.
	for id in ids:
		var snapshot: Dictionary = actors[id]
		if not state.actors.has(id): state.actors[id] = _fresh()
		var entry: Dictionary = state.actors[id]
		if entry.anchor_id == "":
			# Trusted transition event, NOT grounded proximity/head/ceiling contact.
			if snapshot.get("terrain_landed", false): entry.benefit_used = false
			continue
		var reason := ""
		if not snapshot.get("enabled", true): reason = "disabled"
		elif snapshot.get("eliminated", false): reason = "ko"
		elif not _available(snapshot): reason = str(snapshot.get("status", "disabled"))
		elif not by_id.has(entry.anchor_id): reason = "anchor_removed"
		elif tick - entry.caught_at >= maxi(1, max_hang_ticks): reason = "timeout"
		var intent: String = snapshot.get("intent", "")
		if reason == "" and intent in ["drop", "jump", "climb"]: reason = intent
		var points: Array = []
		var velocity := Vector3.ZERO
		if by_id.has(entry.anchor_id):
			var anchor = by_id[entry.anchor_id]
			points = [snapshot.position, anchor.hang(snapshot)]
			if reason == "climb":
				# Rise entirely outside the wall, then translate over the top.
				points.append(Vector3(anchor.hang(snapshot).x, anchor.climb(snapshot).y, anchor.hang(snapshot).z))
				points.append(anchor.climb(snapshot))
			elif reason == "jump": velocity = Vector3(anchor.outward * jump_velocity.x, jump_velocity.y, jump_velocity.z)
			elif reason in ["drop", "timeout"]: velocity = Vector3(0, -absf(drop_speed), 0)
		if reason == "" or reason == "climb":
			if (not actor_clear_path.call(id, points) if actor_clear_path.is_valid() else not clear_path.is_valid() or not clear_path.call(points)): reason = "blocked"; points = []
		if reason != "":
			entry.anchor_id = ""
			entry.unlock_tick = tick + maxi(1, regrab_ticks)
			proposals[id] = _proposal(reason, points if reason == "climb" else [], velocity)
		else:
			proposals[id] = _proposal("hang", points, Vector3.ZERO)
			proposals[id].protected = tick < entry.protected_until
	var occupied := {}
	for id in ids:
		var key: String = state.actors[id].anchor_id
		if key != "": occupied[key] = id
	var anchor_ids = by_id.keys(); anchor_ids.sort()
	for id in ids:
		var entry: Dictionary = state.actors[id]
		if proposals.has(id) or entry.anchor_id != "" or tick < entry.unlock_tick or not _available(actors[id]): continue
		if actors[id].get("intent", "") == "drop": continue
		for key in anchor_ids:
			var anchor = by_id[key]
			if occupied.has(key) or not anchor.eligible(actors[id]): continue
			var points = [actors[id].position, anchor.hang(actors[id])]
			if (not actor_clear_path.call(id, points) if actor_clear_path.is_valid() else not clear_path.is_valid() or not clear_path.call(points)): continue
			var benefit: bool = not entry.benefit_used
			entry.anchor_id = key; entry.caught_at = tick
			entry.protected_until = tick + maxi(0, protection_ticks) if benefit else tick
			entry.benefit_used = true
			occupied[key] = id
			proposals[id] = _proposal("catch", points, Vector3.ZERO)
			proposals[id].restore_recovery = benefit
			proposals[id].protected = tick < entry.protected_until
			proposals[id].cancel_recovery = true
			break
	return {"state": state, "proposals": proposals}

## Call inside a physics tick. Capsule offset is relative to actor foot origin.
## Terrain-only layer 1 by default; do not exclude the supporting stage collider.
func terrain_path_clear(space: PhysicsDirectSpaceState3D, shape: Shape3D, offset: Variant, points: Array, mask: int = 1, exclude: Array[RID] = []) -> bool:
	if space == null or shape == null or points.is_empty() or mask == 0: return false
	var local_shape: Transform3D = Transform3D(Basis.IDENTITY, offset) if offset is Vector3 else offset
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape; query.collision_mask = mask; query.exclude = exclude
	query.collide_with_areas = false; query.collide_with_bodies = true; query.margin = 0.001
	for index in points.size():
		query.transform = Transform3D(Basis.IDENTITY, points[index]) * local_shape
		query.motion = Vector3.ZERO
		# Native body contact can stop inside the query's inflated margin without
		# penetration. Keep conservative terrain clearance, but test fighter
		# endpoints at their actual shape; never remove initial-overlap checks.
		query.collision_mask = mask & ~2
		query.margin = 0.001
		if query.collision_mask != 0 and not space.intersect_shape(query, 1).is_empty(): return false
		query.collision_mask = mask & 2
		query.margin = 0.0
		if query.collision_mask != 0 and not space.intersect_shape(query, 1).is_empty(): return false
		query.collision_mask = mask
		query.margin = 0.001
		if index + 1 == points.size(): continue
		query.motion = points[index + 1] - points[index]
		if query.motion.length_squared() == 0: continue
		var fraction := space.cast_motion(query)
		if fraction.is_empty() or fraction[0] < 1.0: return false
	return true

func _available(snapshot: Dictionary) -> bool:
	return snapshot.get("enabled", true) and snapshot.get("status", "normal") == "normal" and not snapshot.get("eliminated", false)
func _fresh() -> Dictionary:
	return {"anchor_id": "", "caught_at": -1, "unlock_tick": 0, "protected_until": 0, "benefit_used": false}
func _proposal(transition: String, points: Array, velocity: Vector3) -> Dictionary:
	return {"transition": transition, "path": points, "velocity": velocity, "restore_recovery": false, "protected": false, "cancel_recovery": false}
