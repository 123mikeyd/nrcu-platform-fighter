extends RefCounted
## Match-called world ray, never an autonomous Node. Returns a contact or expiry.
static func advance(shot: Dictionary, fighters: Dictionary, tick: int) -> Dictionary:
	if shot.spawn_tick == tick: return {}
	var source: Dictionary = fighters[shot.source]
	if not source.enabled or not is_instance_valid(source.actor): return {"consumed": true}
	shot.ttl -= 1
	if shot.ttl <= 0: return {"consumed": true}
	var start: Vector3 = shot.position
	var end := start + Vector3(shot.facing * 15.0 / 60.0, 0, 0)
	end.z = move_toward(start.z, 0, 6.0 / 60.0)
	var query := PhysicsRayQueryParameters3D.create(start, end, 3)
	query.hit_from_inside = true
	var excluded: Array[RID] = []
	var eligible: Dictionary = {}
	var generated_hit := {}
	var generated_target := {}
	var recipient = preload("res://scripts/core/collision/recipient_queries.gd")
	for id in fighters:
		var f: Dictionary = fighters[id]
		if id == shot.source or not f.enabled or (source.team >= 0 and source.team == f.team): excluded.append(f.actor.get_rid())
		elif recipient.generated(f):
			excluded.append(f.actor.get_rid())
			var contact: Dictionary = recipient.sphere(f,start,end,0.0)
			if not contact.is_empty() and (generated_hit.is_empty() or contact.t < generated_hit.t or (contact.t == generated_hit.t and id < generated_hit.victim)):
				generated_hit = contact; generated_hit.victim = id; generated_target = f
		else: eligible[f.actor.get_instance_id()] = id
	# Unregistered core bodies are not match participants, not terrain.
	for body in source.actor.get_tree().get_nodes_in_group("core_fighters"):
		if not eligible.has(body.get_instance_id()) and not excluded.has(body.get_rid()): excluded.append(body.get_rid())
	query.exclude = excluded
	var hit: Dictionary = source.actor.get_world_3d().direct_space_state.intersect_ray(query)
	# Compare the frozen limb sweep with the unchanged world ray. Terrain wins
	# equal-time contacts; generated misses cannot be consumed by native bodies.
	var native_t: float = start.distance_to(hit.position)/start.distance_to(end) if not hit.is_empty() else INF
	if not generated_hit.is_empty() and generated_hit.t < native_t:
		shot.position = start.lerp(end,generated_hit.t)
		return {"consumed":true,"contact":recipient.annotate({"source":shot.source,"victim":generated_hit.victim,"activation_id":shot.activation_id,"tick":tick,"damage":8.0,"base_knockback":6.0,"direction":Vector3(shot.facing,.12,0)},generated_target,generated_hit)}
	shot.position = end if hit.is_empty() else hit.position
	if hit.is_empty(): return {}
	var result := {"consumed": true}
	if eligible.has(hit.collider.get_instance_id()):
		result.contact = {"source": shot.source, "victim": eligible[hit.collider.get_instance_id()], "activation_id": shot.activation_id, "tick": tick, "damage": 8.0, "base_knockback": 6.0, "direction": Vector3(shot.facing, 0.12, 0)}
	return result
