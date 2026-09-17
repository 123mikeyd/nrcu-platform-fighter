extends RefCounted
## Explicit match tick owner. Call only from a 60 Hz physics callback.
const Grab = preload("res://scripts/core/combat/grab_ability.gd")
var grab_hold_duration := 1.25
const Resolver = preload("res://scripts/core/combat/combat_resolver.gd")
const Recovery = preload("res://scripts/core/combat/recovery_ability.gd")
const Force = preload("res://scripts/core/combat/force_ability.gd")
var projectiles: Array[Dictionary] = []
var ability_events: Array[Dictionary] = []
var waves: Array = []
var projectile_host = preload("res://scripts/core/combat/projectile_host.gd").new()
var resolver = Resolver.new()
const Frame = preload("res://scripts/core/input/input_frame.gd")
const Buffer = preload("res://scripts/core/input/input_buffer.gd")
var _side = preload("res://data/moves/side_strike.tres").duplicate(true)
var _air = preload("res://data/moves/air_strike.tres").duplicate(true)
var _uppercut = preload("res://data/moves/uppercut.tres").duplicate(true)
var _up_air = preload("res://data/moves/up_air.tres").duplicate(true)
var _low_sweep = preload("res://data/moves/low_sweep.tres").duplicate(true)
var _down_strike = preload("res://data/moves/down_strike.tres").duplicate(true)
# Compare Vector2 components in their own precision, including exact endpoints.
const AIM_THRESHOLD = Vector2(0.1, 0.1)
var fighters: Dictionary = {}
var rules: Resource = null
var result: Dictionary = {}
var lifecycle_events: Array[Dictionary] = []
var _next_lifecycle: int = 0
var tick: int = 0
var generation: int = 1
var _next_activation: int = 0
var _last_physics_tick: int = -1
var events: Array[Dictionary] = []
const Defense = preload("res://scripts/core/combat/defense_policy.gd")
var defense_profile: Resource = null
var _defense_seen: Dictionary = {}
func configure_defense(profile: Resource) -> void:
	defense_profile = profile.duplicate(true) if profile != null else null
	for f in fighters.values():
		f.defense = Defense.new(defense_profile) if defense_profile != null and defense_profile.policy_id == "finite" else null
		if f.defense != null: f.defense.reset(f.actor.runtime.grounded)
func defense_telemetry(entity_id: int) -> Dictionary:
	var f: Dictionary = fighters[entity_id]
	return f.defense.snapshot() if f.defense != null else {"delegate_legacy": true}
var ledge_policy: Resource = null
var ledge_anchors: Array = []
var ledge_state: Dictionary = {}
var ledge_events: Dictionary = {}
var _ledge_intents: Dictionary = {}
var _ledge_landed: Dictionary = {}
func configure_ledges(anchors: Array, policy: Resource) -> void:
	ledge_policy = policy.duplicate(true) if policy != null else null
	ledge_anchors = []
	for anchor in anchors: ledge_anchors.append(anchor.duplicate(true))
	ledge_state = {}
	ledge_events = {}
func _release_ledge(id: int) -> void:
	if not _ledge_attached(id): return
	var entry: Dictionary = ledge_state.actors[id]
	entry.anchor_id = ""
	entry.unlock_tick = tick + maxi(1, ledge_policy.regrab_ticks)
	# No velocity write: incoming hit/freeze/capture/lifecycle owns motion.
func _ledge_attached(id: int) -> bool:
	return ledge_state.get("actors", {}).get(id, {}).get("anchor_id", "") != ""
func _ledge_protected(id: int) -> bool:
	return _ledge_attached(id) and tick < ledge_state.actors[id].protected_until
func ledge_telemetry(id: int) -> Dictionary:
	var entry: Dictionary = ledge_state.get("actors", {}).get(id, {}).duplicate(true)
	entry["anchor_id"] = entry.get("anchor_id", "")
	entry["protected"] = _ledge_protected(id)
	return entry
func _advance_ledges(ids: Array) -> void:
	if ledge_policy == null: return
	var snapshots := {}
	for id in ids:
		var f: Dictionary = fighters[id]
		if not is_instance_valid(f.actor) or not f.actor.is_inside_tree(): continue
		var collider: CollisionShape3D = f.actor.get_node("CoreCapsule")
		snapshots[id] = {"position": f.actor.global_position, "velocity": f.actor.velocity,
			"body": {"radius": collider.shape.radius, "height": collider.shape.height, "center": collider.position},
			"grounded": f.actor.runtime.grounded, "status": f.actor.runtime.states.status,
			"enabled": f.enabled, "eliminated": f.eliminated, "intent": _ledge_intents.get(id, ""), "terrain_landed": _ledge_landed.has(id)}
		if f.defense != null and f.defense.snapshot().action_locked: snapshots[id].status = "defense"
	# Every query is actor-aware; there is no first-fighter fallback geometry.
	var clear := Callable()
	var actor_clear := func(id, points):
		var actor = fighters[id].actor
		var exclude: Array[RID] = [actor.get_rid()]
		for body in actor.get_collision_exceptions():
			if is_instance_valid(body): exclude.append(body.get_rid())
		var collider: CollisionShape3D = actor.get_node("CoreCapsule")
		var relative_shape := Transform3D(actor.global_basis, Vector3.ZERO) * collider.transform
		return ledge_policy.terrain_path_clear(actor.get_world_3d().direct_space_state, collider.shape, relative_shape, points, actor.collision_mask, exclude)
	# A stopped actor neither departs nor contests. Reserve its occupied anchor
	# while advancing the live subset, then merge its shifted local deadlines.
	var previous := ledge_state.duplicate(true)
	var paused := {}
	var reserved := {}
	for id in _stopped:
		snapshots.erase(id)
		if not previous.get("actors", {}).has(id): continue
		var entry: Dictionary = previous.actors[id]
		if entry.anchor_id != "":
			reserved[entry.anchor_id] = true
			entry.caught_at += 1
		if entry.protected_until > tick: entry.protected_until += 1
		if entry.unlock_tick > tick: entry.unlock_tick += 1
		paused[id] = entry
		previous.actors.erase(id)
	var available: Array = []
	for anchor in ledge_anchors:
		if not reserved.has(anchor.anchor_id): available.append(anchor)
	var decision: Dictionary = ledge_policy.advance(previous, snapshots, available, tick, clear, actor_clear)
	decision.state.actors.merge(paused)
	ledge_events = decision.proposals
	for id in ledge_events:
		var proposal: Dictionary = ledge_events[id]
		if proposal.cancel_recovery:
			var f: Dictionary = fighters[id]
			if f.kit != null: f.kit.cancel()
			f.recovery = null
			f.actor.runtime.cancel_recovery_motion()
			f.move_id = ""; f.activation_id = ""
		if proposal.restore_recovery: fighters[id].actor.runtime.recovery_spent = false
		if proposal.transition in ["catch", "hang", "climb"]:
			top_support.release(id)
			fighters[id].actor.apply_ledge_path(proposal.path)
		elif proposal.transition in ["jump", "drop", "timeout"]:
			fighters[id].actor.velocity = proposal.velocity
			fighters[id].actor.runtime.velocity = proposal.velocity
		if proposal.transition == "jump": fighters[id].buffer.consume("jump")
		if proposal.transition == "drop": fighters[id].buffer.consume("down")
	ledge_state = decision.state
var hitstop_profile: Resource = null
var _hitstop_seen: Dictionary = {}
var _stopped: Dictionary = {}
func configure_hitstop(profile: Resource) -> void:
	hitstop_profile = profile.duplicate(true) if profile != null else null
func hitstop_telemetry(entity_id: int) -> Dictionary:
	var f: Dictionary = fighters[entity_id]
	return {"remaining_ticks": f.hitstop_left, "stopped_this_tick": _stopped.has(entity_id),
		"simulation_tick": f.actor.runtime.tick, "world_tick": tick, "generation": generation}
func _sync_joint_hitstop() -> void:
	# A live grab is one motion relation, not two independently ticking bodies.
	for id in fighters:
		var f: Dictionary = fighters[id]
		if f.caught_by == 0: continue
		var owner: Dictionary = fighters[f.caught_by]
		var remaining := maxi(f.hitstop_left, owner.hitstop_left)
		f.hitstop_left = remaining
		owner.hitstop_left = remaining
var kit_registry = preload("res://scripts/core/kits/kit_registry.gd").new()
func configure_actor_kit(entity_id: int, kit_id: String) -> bool:
	if not fighters.has(entity_id) or not kit_registry.contains(kit_id): return false
	expire_source(entity_id, "kit change")
	fighters[entity_id].kit = kit_registry.create(kit_id)
	fighters[entity_id].kit_id = kit_id
	fighters[entity_id].ready_tick = 0
	fighters[entity_id].magic_ready_tick = 0
	fighters[entity_id].buffer = Buffer.new()
	return true
func kit_telemetry(entity_id: int) -> Dictionary:
	var f: Dictionary = fighters[entity_id]
	var value: Dictionary = f.kit.snapshot() if f.kit != null else {"kit_id": f.kit_id, "action_locked": tick < f.ready_tick}
	value.merge({"simulation_tick": f.actor.runtime.tick, "world_tick": tick, "generation": generation, "stopped": _stopped.has(entity_id)})
	return value
func _kit_locked(f: Dictionary) -> bool:
	return f.kit != null and f.kit.locked()
func register_actor(entity_id: int, actor, team: int = -1, kit_id: String = "teknium") -> bool:
	# Full-roster opt-in is atomic. Return to legacy before adding participants.
	if fighter_interaction_mode == "grounded_jostle": return false
	assert(entity_id > 0 and not fighters.has(entity_id))
	fighters[entity_id] = {"actor": actor, "team": team, "enabled": true, "eliminated": false, "stocks": 0, "protection_until": 0,
		"projectile_absorbing": false, "absorbed_damage": 0.0, "kit_id": kit_id, "kit": kit_registry.create(kit_id), "percent": 0.0, "facing": 1.0, "move_id": "", "activation_id": "",
		"grab": null, "caught_by": 0, "grab_immune_until": 0, "magic_ready_tick": 0, "status_host": preload("res://scripts/core/combat/status_host.gd").new(), "manual_frozen": false, "frozen": false, "shield_command": false,
		"ready_tick": 0, "buffer": Buffer.new(), "force": null, "recovery": null, "hitstop_left": 0, "jump_release_pending": false, "defense_lock_pending": false, "defense": Defense.new(defense_profile) if defense_profile != null and defense_profile.policy_id == "finite" else null}
	actor.lock_body_configuration()
	actor.set_body_contacts(true)
	actor.tree_exiting.connect(_actor_exiting.bind(entity_id))
	return true
func _actor_exiting(entity_id: int) -> void:
	fighters[entity_id].enabled = false
	_invalidate_collision(entity_id,"tree exit")
	expire_source(entity_id, "tree exit")
	_reconcile_status(entity_id)
func status_telemetry(entity_id: int) -> Dictionary:
	var value: Dictionary = fighters[entity_id].status_host.snapshot()
	value.merge({"frozen": fighters[entity_id].frozen, "world_tick": tick, "generation": generation})
	return value
func set_frozen(entity_id: int, frozen: bool) -> void:
	var f: Dictionary = fighters[entity_id]
	f.manual_frozen = frozen
	cancel_action(entity_id, "incoming freeze")
	_reconcile_status(entity_id)
func cancel_action(entity_id: int, _reason: String) -> void:
	top_support.release(entity_id)
	var f: Dictionary = fighters[entity_id]
	f.projectile_absorbing = false
	if f.kit != null:
		if _reason == "status frozen" and f.kit.has_method("cancel_for_status"): f.kit.cancel_for_status("frozen")
		else: f.kit.cancel()
	if f.defense != null:
		if f.defense.snapshot().action_locked and is_instance_valid(f.actor) and f.actor.runtime.states.action == "movement_lock":
			f.defense_lock_pending = true
		f.defense.interrupt(_reason)
		_release_defense_lock(f)
	_release_ledge(entity_id)
	if f.caught_by != 0: _cancel_grab(f.caught_by)
	_cancel_grab(entity_id)
	# Release only our transient command lock; never erase landing recovery/stun.
	if is_instance_valid(f.actor):
		if f.force != null and f.actor.runtime.hitstun_left == 0 and f.actor.runtime.states.action == "movement_lock":
			f.actor.runtime.states.transition("action", "neutral", "force released")
		f.actor.runtime.cancel_recovery_motion()
	f.recovery = null
	fighters[entity_id].force = null
	fighters[entity_id].activation_id = ""
	fighters[entity_id].move_id = ""
func expire_source(entity_id: int, reason: String) -> void:
	cancel_action(entity_id, reason)
	projectile_host.expire_source(entity_id)
	fighters[entity_id].status_host.clear()
	_reconcile_status(entity_id)
	if fighters[entity_id].kit != null: fighters[entity_id].kit.cancel(true)
	fighters[entity_id].absorbed_damage = 0.0
	fighters[entity_id].hitstop_left = 0
	fighters[entity_id].jump_release_pending = false
	_stopped.erase(entity_id)
	var retained: Array[Dictionary] = []
	for shot in projectiles:
		if shot.source != entity_id: retained.append(shot)
	projectiles = retained
	waves = waves.filter(func(w):
		if w.source == entity_id: w.cancel()
		return w.active)
func set_enabled(entity_id: int, enabled: bool) -> void:
	var f: Dictionary = fighters[entity_id]
	if enabled and f.eliminated: return
	if f.enabled == enabled: return
	f.enabled = enabled
	_invalidate_collision(entity_id,"enable change")
	if not enabled: expire_source(entity_id, "disabled")
	cancel_action(entity_id, "enable change")
	f.buffer = Buffer.new()
	_reconcile_status(entity_id)
func _release_defense_lock(f: Dictionary) -> void:
	if not f.defense_lock_pending or not is_instance_valid(f.actor): return
	if f.actor.runtime.states.status != "normal": return
	if f.actor.runtime.states.action == "movement_lock": f.actor.runtime.states.transition("action", "neutral", "defense interrupted")
	f.defense_lock_pending = false
func _reconcile_status(entity_id: int) -> void:
	var f: Dictionary = fighters[entity_id]
	f.frozen = f.manual_frozen or f.status_host.freeze_remaining > 0
	if is_instance_valid(f.actor):
		var layer := 2 if f.enabled and not f.eliminated and f.actor.is_inside_tree() else 0
		if f.actor.collision_layer != layer:
			f.actor.collision_layer = layer
			f.actor.clear_body_contacts()
		f.actor.runtime.reconcile_status(f.enabled, f.frozen, f.caught_by != 0)
		_release_defense_lock(f)
		if f.kit != null and not _kit_locked(f):
			f.move_id = ""; f.activation_id = ""
var top_support = preload("res://scripts/core/collision/fighter_top_support.gd").new()
func _top_support_stance_eligible(id: int) -> bool:
	var f: Dictionary = fighters[id]
	return f.actor.runtime.states.status == "normal" and f.actor.runtime.states.action in ["neutral","none",""] and not f.actor.runtime.grounded and f.activation_id.is_empty() and f.force == null and f.recovery == null and f.grab == null and f.caught_by == 0 and not f.shield_command and str(kit_telemetry(id).get("presentation",{}).get("activation_id","")).is_empty()
func _top_support_geometry(id: int, advance: bool) -> Dictionary:
	var f: Dictionary = fighters[id]
	if not is_instance_valid(f.actor): return {}
	var definition = f.get("top_support_profile")
	var geometry: Dictionary = top_support.envelope(id,definition,not f.actor.runtime.grounded,advance and not _stopped.has(id))
	if definition != null and not top_support.relations.get(id,{}).is_empty() and _top_support_stance_eligible(id) and not _stopped.has(id):
		geometry.pose_category = "supported"
		geometry.height = definition.height
		if advance: top_support.envelopes[id] = geometry.duplicate(true)
	elif not geometry.is_empty() and geometry.pose_category == "supported" and not _stopped.has(id):
		geometry.pose_category = "airborne" if not f.actor.runtime.grounded else "upright"
	return geometry
func _top_support_snapshots(advance_envelopes := false) -> Dictionary:
	var snapshots := {}
	for id in fighters:
		var f: Dictionary = fighters[id]
		if not is_instance_valid(f.actor) or not f.actor.is_inside_tree(): continue
		var definition = f.get("top_support_profile")
		snapshots[id] = {"position":f.actor.global_position,"velocity":f.actor.velocity,
			"eligible":f.enabled and not f.eliminated and f.actor.runtime.states.status == "normal" and not _stopped.has(id) and not _ledge_attached(id) and f.grab == null and f.caught_by == 0,
			"profile":_top_support_geometry(id,advance_envelopes)}
		# Translate the solver's foot coordinate, not the actor/model. A fighter's
		# own head stays in actor space: compensate its profile by the same offset.
		# New acquisitions still use the physical unspecialized start trajectory.
		var sole: float = top_support.starts.get(id,{}).get("sole_offset",0.0) if advance_envelopes else top_support.relations.get(id,{}).get("sole_offset",0.0)
		snapshots[id].sole_offset = sole
		snapshots[id].actor_position = f.actor.global_position
		snapshots[id].position.y += sole
		if not snapshots[id].profile.is_empty(): snapshots[id].profile.height -= sole
	return snapshots
func top_support_telemetry(id: int) -> Dictionary:
	var value: Dictionary = top_support.snapshot(id)
	var f: Dictionary = fighters.get(id,{})
	var definition = f.get("top_support_profile")
	value.geometry = _top_support_geometry(id,false) if not f.is_empty() else {}
	value.generation = generation
	value.body = f.actor.body_profile_snapshot() if f.has("actor") and is_instance_valid(f.actor) else {}
	if f.has("actor") and is_instance_valid(f.actor) and f.actor.is_inside_tree():
		value.body.world_transform = f.actor.get_node("CoreCapsule").global_transform
		if not value.geometry.is_empty():
			var center: Vector3 = f.actor.global_position + Vector3.UP * float(value.geometry.height)
			value.geometry.world_segment = [center-Vector3.RIGHT*float(value.geometry.half_width),center+Vector3.RIGHT*float(value.geometry.half_width)]
			value.geometry.foot_anchor = f.actor.global_position
	return value
var _top_motion_exceptions: Array = []
func _begin_top_support_motion(frames: Dictionary) -> void:
	# A legally above-head pair must not let the narrower native cores cancel
	# the carrier's upward motion before the shared swept solver can run.
	# Exceptions are reciprocal, owned for this movement batch only, and never
	# remove a grab/fixture exception owned elsewhere.
	_top_motion_exceptions.clear()
	for id in top_support.starts:
		var rider: Dictionary = top_support.starts[id]
		if not rider.eligible: continue
		# Fast fall can traverse the core gap in one tick, including on an
		# edge exit. Keep native blocking instead of exempting that swept path.
		if fighters[id].actor.runtime.states.locomotion == "fast_fall" or frames.get(id,Frame.new()).pressed.get("down",false) or not fighters[id].buffer.peek("down").is_empty(): continue
		for carrier in top_support.starts:
			if carrier == id: continue
			if top_support.relations.get(id,{}).get("carrier",0) != carrier: continue
			var lower: Dictionary = top_support.starts[carrier]
			if not lower.eligible or lower.profile.is_empty(): continue
			var gap: float = rider.position.y-lower.position.y-lower.profile.height
			if gap < -0.002 or absf(rider.position.x-lower.position.x) > lower.profile.half_width+0.145: continue
			var a = fighters[id].actor; var b = fighters[carrier].actor
			for pair in [[a,b],[b,a]]:
				if not pair[1] in pair[0].get_collision_exceptions():
					pair[0].add_collision_exception_with(pair[1])
					_top_motion_exceptions.append(pair)
func _end_top_support_motion() -> void:
	for pair in _top_motion_exceptions:
		if is_instance_valid(pair[0]) and is_instance_valid(pair[1]): pair[0].remove_collision_exception_with(pair[1])
	_top_motion_exceptions.clear()
func _top_core_overlap(a, b) -> bool:
	# Both installed movement capsules are validated upright and unscaled.
	var ca: CollisionShape3D = a.get_node("CoreCapsule")
	var cb: CollisionShape3D = b.get_node("CoreCapsule")
	var separation: Vector3 = ca.global_position-cb.global_position
	var spines: float = (ca.shape.height+cb.shape.height)*0.5-ca.shape.radius-cb.shape.radius
	separation.y = maxf(0,absf(separation.y)-spines)
	return separation.length() < ca.shape.radius+cb.shape.radius-0.005
func _advance_top_support() -> void:
	var previous: Dictionary = top_support.relations.duplicate(true)
	var ends := _top_support_snapshots(true)
	var proposals: Dictionary = top_support.solve(ends,generation)
	# Physical start order is acyclic for above-plane catches. Commit carriers
	# first, then read their final actor/head, never an ID-ordered stale plane.
	var ordered = proposals.keys()
	ordered.sort_custom(func(a,b): return top_support.starts[a].position.y < top_support.starts[b].position.y if top_support.starts[a].position.y != top_support.starts[b].position.y else a < b)
	for id in ordered:
		var p: Dictionary = proposals[id]
		var final_plane: float = fighters[p.carrier].actor.global_position.y+_top_support_geometry(p.carrier,false).height
		if final_plane < p.plane and previous.get(id,{}).get("carrier",0) != p.carrier and ends[id].position.y > final_plane+0.002:
			p.reason = "committed_carrier_plane_not_reached"
			top_support.commit(id,p,false)
			continue
		p.plane = final_plane
		p.sole_offset = fighters[id].top_support_profile.supported_sole_offset if _top_support_stance_eligible(id) else 0.0
		var accepted: bool = fighters[id].actor.apply_fighter_top_support(p.plane-p.sole_offset,p.direction)
		if not accepted:
			var start: Dictionary = top_support.starts[p.carrier]
			fighters[p.carrier].actor.retract_blocked_fighter_lift(start.actor_position.y)
		top_support.commit(id,p,accepted)
	# A fast edge exit may leave the native rider beside (not on) the support.
	# If the later-moving carrier entered that rider, retract only its upward
	# step now rather than manufacture overlap for next tick's native recovery.
	for id in previous:
		var carrier: int = previous[id].carrier
		if proposals.has(id) or not ends.has(id) or not ends.has(carrier) or not ends[id].eligible or not ends[carrier].eligible: continue
		if ends[carrier].position.y <= top_support.starts[carrier].position.y: continue
		if not _top_core_overlap(fighters[id].actor,fighters[carrier].actor): continue
		fighters[carrier].actor.retract_blocked_fighter_lift(top_support.starts[carrier].actor_position.y)
		var rejected: Dictionary = previous[id].duplicate(true)
		rejected.reason = "native_core_overlap_on_release"
		top_support.commit(id,rejected,false)
const Jostle = preload("res://scripts/core/collision/fighter_jostle.gd")
var fighter_interaction_mode := "legacy_solid"
var _jostle_last: Dictionary = {}
## Detached configuration range, not a pair contact, wall or support surface.
func jostle_world(id: int) -> Dictionary:
	if not fighters.has(id): return {}
	var actor = fighters[id].actor
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return {}
	var snapshot := _jostle_snapshot(id)
	var shape: CollisionShape3D = actor.get_node("CoreCapsule")
	var center := Vector3(snapshot.center,snapshot.feet,shape.global_position.z)
	var last: Dictionary = _jostle_last.get(id,{})
	return {"entity_id":id,"mode":fighter_interaction_mode,"generation":generation,"tick":tick,
		"profile_revision":actor.body_profile_snapshot().revision,
		"world_segment":[center-Vector3.RIGHT*snapshot.radius,center+Vector3.RIGHT*snapshot.radius],
		"grounded":actor.has_terrain_support(),"eligible":fighter_interaction_mode == "grounded_jostle" and snapshot.eligible,
		"last_correction":last.get("correction",0.0) if last.get("generation",-1) == generation and tick > 0 and last.get("tick",-1) == tick-1 else 0.0}.duplicate(true)
func _jostle_snapshot(id: int) -> Dictionary:
	var f: Dictionary = fighters[id]
	var actor = f.actor
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return {"eligible":false}
	var shape: CollisionShape3D = actor.get_node("CoreCapsule")
	return {"eligible":f.enabled and not f.eliminated and not _stopped.has(id) and not f.frozen and actor.runtime.states.status == "normal" and actor.has_terrain_support() and not _ledge_attached(id) and f.grab == null and f.caught_by == 0 and f.recovery == null,
		"center":shape.global_position.x,"feet":actor.global_position.y,"radius":shape.shape.radius}
func _advance_ground_jostle(ids: Array) -> void:
	if fighter_interaction_mode != "grounded_jostle": return
	# Sorted IDs, one bounded pass. Terrain-blocked overlap is not a hard lock.
	var remaining := {}
	for id in ids: remaining[id] = Jostle.MAX_CORRECTION
	for i in ids.size():
		for j in range(i+1,ids.size()):
			var a = fighters[ids[i]].actor; var b = fighters[ids[j]].actor
			if not is_instance_valid(a) or not is_instance_valid(b): continue
			if b in a.get_collision_exceptions() or a in b.get_collision_exceptions(): continue
			var correction := Jostle.pair(_jostle_snapshot(ids[i]),_jostle_snapshot(ids[j]))
			if correction == Vector2.ZERO: continue
			var dx_a: float = clampf(correction.x,-remaining[ids[i]],remaining[ids[i]])
			var dx_b: float = clampf(correction.y,-remaining[ids[j]],remaining[ids[j]])
			var applied_a: float = a.apply_ground_jostle(dx_a)
			var applied_b: float = b.apply_ground_jostle(dx_b)
			remaining[ids[i]] -= absf(applied_a)
			remaining[ids[j]] -= absf(applied_b)
			for applied in [[ids[i],applied_a],[ids[j],applied_b]]:
				var last: Dictionary = _jostle_last.get(applied[0],{})
				var previous: float = last.get("correction",0.0) if last.get("generation",-1) == generation and last.get("tick",-1) == tick else 0.0
				_jostle_last[applied[0]] = {"generation":generation,"tick":tick,"correction":previous+applied[1]}
func reset_with_collision_profiles(spawns: Dictionary, profiles: Dictionary, interaction_mode: String = "auto") -> bool:
	if interaction_mode not in ["auto","grounded_jostle","legacy_solid"]: return false
	var complete := profiles.size() == fighters.size()
	for id in fighters:
		if profiles.get(id) == null: complete = false
	if interaction_mode == "grounded_jostle" and not complete: return false
	var selected := "grounded_jostle" if complete and interaction_mode != "legacy_solid" else "legacy_solid"
	# Prepare every source/policy before the atomic body-reset boundary.
	var prepared := {}
	for id in profiles:
		if not fighters.has(id): return false
		if profiles[id] == null:
			prepared[id] = null
			continue
		if not profiles[id] is Resource:
			_collision_install_diagnostics = PackedStringArray(["unsupported collision profile resource"])
			return false
		var host = preload("res://scripts/core/collision/collision_host.gd").new()
		var errors: PackedStringArray = host.configure(profiles[id],str(generation+1))
		if not errors.is_empty():
			_collision_install_diagnostics = errors
			return false
		prepared[id] = host
	if not reset_with_body_profiles(spawns,profiles): return false
	for id in prepared:
		fighters[id].collision_host = prepared[id]
		fighters[id].top_support_profile = preload("res://scripts/core/collision/fighter_top_support_profile.gd").for_collision(profiles[id]) if selected == "legacy_solid" else null
	fighter_interaction_mode = selected
	for id in fighters: fighters[id].actor.set_body_contacts(selected == "legacy_solid")
	_collision_install_diagnostics.clear()
	return true

var _collision_install_diagnostics := PackedStringArray()
func collision_install_diagnostics() -> PackedStringArray:
	return _collision_install_diagnostics.duplicate()
func collision_telemetry(id: int) -> Dictionary:
	if not fighters.has(id): return {"ok":false,"diagnostics":["unknown entity"]}
	var host = fighters[id].get("collision_host")
	return host.telemetry() if host != null else {"ok":true,"geometry_mode":"legacy_body_capsule","primitives":[],"has_bounds":false}
func _invalidate_collision(id: int, reason: String) -> void:
	var host = fighters[id].get("collision_host")
	if host != null: host.invalidate(reason)
func _commit_collision_poses(ids: Array, phase: String = "contacts") -> void:
	for id in ids:
		var f: Dictionary = fighters[id]
		var host = f.get("collision_host")
		if host == null or not f.enabled or not is_instance_valid(f.actor) or not f.actor.is_inside_tree(): continue
		var runtime = f.actor.runtime
		if f.get("collision_strike_id","") != f.activation_id:
			f.collision_strike_id = f.activation_id; f.collision_strike_start = runtime.tick
		var grab := {}; var caught := {}
		if f.grab != null: grab = {"activation_id":f.grab.activation_id,"phase":f.grab.phase,"elapsed":f.grab.elapsed,"facing":f.grab.facing}
		if f.caught_by != 0 and fighters.has(f.caught_by) and fighters[f.caught_by].grab != null:
			var g = fighters[f.caught_by].grab
			caught = {"activation_id":g.activation_id,"elapsed":g.elapsed}
		var context := {"entity_id":id,"generation":generation,"status":runtime.states.status,"locomotion":runtime.states.locomotion,"action":"" if runtime.states.action in ["neutral","landing_lock"] else runtime.states.action,"grounded":runtime.grounded,"facing":f.facing,"air_jumps_left":runtime.air_jumps_left,"velocity":runtime.velocity,
			"source_melee":true,"presentation":kit_telemetry(id).get("presentation",{}),"strike_id":f.activation_id if f.kit == null and f.force == null and f.recovery == null and f.grab == null else "","strike_move":f.move_id,"strike_elapsed":(runtime.tick-int(f.get("collision_strike_start",runtime.tick)))/60.0,
			"recovery_id":f.recovery.activation_id if f.recovery != null else "","recovery_elapsed":f.recovery.age/60.0 if f.recovery != null else 0.0,"force_id":f.force.activation_id if f.force != null else "","force_source_time":f.force.source_time(f.force.age/60.0) if f.force != null else 0.0,
			"grab":grab,"caught":caught,"hit_id":f.get("collision_hit_id","initial"),"stopped":_stopped.has(id),"frozen":f.frozen,"shielding":f.shield_command}
		context.support = top_support.snapshot(id).relation
		host.commit(context,runtime.tick,f.actor.global_transform,{"enabled":f.enabled,"eliminated":f.eliminated,"team_id":str(f.team)},phase)

func reset_with_body_profiles(spawns: Dictionary, body_profiles: Dictionary) -> bool:
	# A partial change cannot flip a previously opted-in, untouched endpoint.
	if fighter_interaction_mode == "grounded_jostle" and body_profiles.size() != fighters.size(): return false
	# Atomic validation before releasing any hold, relocating or replacing shape.
	for id in body_profiles:
		if not fighters.has(id) or not is_instance_valid(fighters[id].actor) or not fighters[id].actor.is_inside_tree(): return false
		if body_profiles[id] != null and not body_profiles[id] is Resource: return false
		if not fighters[id].actor.validate_body_profile(body_profiles[id]).is_empty(): return false
	var effective_spawns: Dictionary = rules.stage.spawns if rules != null else spawns
	for id in fighters:
		if not effective_spawns.has(id) or not effective_spawns[id] is Vector3 or not effective_spawns[id].is_finite(): return false
	reset(spawns)
	fighter_interaction_mode = "legacy_solid"
	for id in fighters: fighters[id].actor.set_body_contacts(true)
	for id in body_profiles:
		fighters[id].actor._commit_body_profile(body_profiles[id])
		fighters[id].top_support_profile = null
	return true
func reset(spawns: Dictionary) -> void:
	top_support.reset()
	if rules != null: spawns = rules.stage.spawns
	result.clear()
	lifecycle_events.clear()
	_next_lifecycle = 0
	generation += 1
	tick = 0
	_next_activation = 0
	resolver = Resolver.new()
	_hitstop_seen.clear()
	_defense_seen.clear()
	_stopped.clear()
	events.clear()
	projectiles.clear()
	ability_events.clear()
	# Release all ownership against OLD runtimes before replacing any actor.
	for id in fighters:
		expire_source(id, "reset")
		_invalidate_collision(id,"match reset")
	ledge_state = {}; ledge_events = {}; _ledge_intents.clear(); _ledge_landed.clear()
	ability_events.clear()
	# Keep the engine-frame guard: reset does not grant a second simulation tick.
	for id in fighters:
		var f: Dictionary = fighters[id]
		if not is_instance_valid(f.actor) or not f.actor.is_inside_tree():
			f.enabled = false
			continue
		f.actor.reset_at(spawns.get(id, f.actor.global_position))
		f.percent = 0.0
		f.facing = 1.0
		f.ready_tick = 0
		f.magic_ready_tick = 0; f.grab_immune_until = 0; f.manual_frozen = false; f.frozen = false; f.shield_command = false
		f.enabled = true
		f.eliminated = false
		f.stocks = rules.stock_count if rules != null else 0
		f.protection_until = 0
		f.buffer = Buffer.new()
		cancel_action(id, "reset")
		_reconcile_status(id)
		if f.defense != null: f.defense.reset(false)
func _body_overlap_directions(ids: Array) -> Dictionary:
	if fighter_interaction_mode == "grounded_jostle": return {}
	# Lifecycle overlaps have no contact normal at exact coincidence. Break
	# that symmetry before the one native movement call, never by translation.
	var directions := {}
	for i in ids.size():
		var a = fighters[ids[i]].actor
		if not is_instance_valid(a) or a.collision_layer == 0: continue
		var sa: CapsuleShape3D = a.get_node("CoreCapsule").shape
		for j in range(i + 1, ids.size()):
			var b = fighters[ids[j]].actor
			if not is_instance_valid(b) or b.collision_layer == 0 or b in a.get_collision_exceptions() or a in b.get_collision_exceptions(): continue
			var sb: CapsuleShape3D = b.get_node("CoreCapsule").shape
			var delta: Vector3 = b.get_node("CoreCapsule").global_transform.origin - a.get_node("CoreCapsule").global_transform.origin
			var spine_gap := maxf(0, absf(delta.y) - (sa.height + sb.height) * 0.5 + sa.radius + sb.radius)
			var radius: float = sa.radius + sb.radius - a.safe_margin - b.safe_margin
			if delta.x * delta.x + delta.z * delta.z + spine_gap * spine_gap >= radius * radius: continue
			var side := signf(delta.x) if absf(delta.x) > 0.01 else 1.0
			if not directions.has(ids[i]): directions[ids[i]] = -side
			if not directions.has(ids[j]): directions[ids[j]] = side
	return directions
func _resolve_native_ledge_pressure(id: int, start: Transform3D) -> void:
	# Native grounded wall/snap response can finish inside a rounded hanger.
	# Recover only the live mover, before ledge occupancy is evaluated. Keep
	# terrain, body masks and exceptions authoritative; never move the hanger.
	if fighter_interaction_mode != "legacy_solid" or _ledge_attached(id): return
	var actor = fighters[id].actor
	if actor.runtime.states.status != "normal": return
	var collider: CollisionShape3D = actor.get_node("CoreCapsule")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = collider.global_transform
	query.collision_mask = actor.collision_mask & 2
	query.margin = 0.0
	var exclude: Array[RID] = [actor.get_rid()]
	for body in actor.get_collision_exceptions():
		if is_instance_valid(body): exclude.append(body.get_rid())
	query.exclude = exclude
	for contact in actor.get_world_3d().direct_space_state.intersect_shape(query):
		for other in fighters:
			if _ledge_attached(other) and contact.collider == fighters[other].actor:
				query.transform = start * collider.transform
				# Initial/release overlaps are not a pressure transaction. They
				# remain owned by ordinary native overlap recovery / ledge rejection.
				if not actor.get_world_3d().direct_space_state.intersect_shape(query).is_empty(): return
				# Reject only this mover's newly penetrating native step, through
				# a real reverse sweep (including terrain), not a transform restore.
				actor.move_and_collide(start.origin - actor.global_position)
				return
func simulate(frames: Dictionary = {}) -> void:
	if Engine.get_physics_frames() == _last_physics_tick: return
	_last_physics_tick = Engine.get_physics_frames()
	events.clear()
	ability_events.clear()
	lifecycle_events.clear()
	if not result.is_empty(): return
	var ids := fighters.keys()
	ids.sort()
	_stopped.clear()
	_ledge_intents.clear()
	_ledge_landed.clear()
	ledge_events.clear()
	_sync_joint_hitstop()
	for id in ids:
		var f: Dictionary = fighters[id]
		if f.enabled and f.hitstop_left > 0:
			_stopped[id] = true
			f.hitstop_left -= 1
			for clock in ["ready_tick", "magic_ready_tick"]:
				if f[clock] > 0 and f[clock] >= tick: f[clock] += 1
			# Immunity is active strictly before its deadline; equality is expired.
			for clock in ["grab_immune_until", "protection_until"]:
				if f[clock] > tick: f[clock] += 1
	for id in ids:
		var f: Dictionary = fighters[id]
		if f.enabled and not _stopped.has(id): f.status_host.advance(1.0 / 60.0)
		_reconcile_status(id)
		# Status gates all kits before the world-projectile shield snapshot.
		if not is_instance_valid(f.actor) or f.actor.runtime.states.status != "normal":
			f.shield_command = false
			continue
		# Hitstop retains committed defense, never accepts a fresh held shield.
		if _stopped.has(id): continue
		f.shield_command = frames.get(id, Frame.new()).held.get("shield", false) and not _kit_locked(f)
	top_support.begin(_top_support_snapshots())
	_begin_top_support_motion(frames)
	var overlap_directions := _body_overlap_directions(ids)
	var strikes: Array[Dictionary] = []
	for id in ids:
		var f: Dictionary = fighters[id]
		var actor = f.actor
		_reconcile_status(id)
		if not f.enabled or not is_instance_valid(actor): continue
		var input = frames.get(id, Frame.new())
		input = Frame.from_dict(input.to_dict())
		input.tick = tick
		f.buffer.advance(input, _stopped.has(id))
		if _stopped.has(id):
			f.jump_release_pending = f.jump_release_pending or input.released.get("jump", false)
			continue
		input.released.jump = input.released.get("jump", false) or f.jump_release_pending
		f.jump_release_pending = false
		if (_kit_locked(f) or f.force != null or f.recovery != null or f.grab != null or f.caught_by != 0) and actor.runtime.hitstun_left > 0: cancel_action(id, "hitstun")
		if f.kit == null and tick >= f.ready_tick and not f.activation_id.is_empty(): cancel_action(id, "cooldown complete")
		if f.caught_by != 0:
			for action in ["attack", "special", "jump", "down", "shield"]:
				while not f.buffer.consume(action).is_empty(): pass
		if f.kit != null:
			f.kit.prepare(input.held.get("special", false))
			f.shield_command = input.held.get("shield", false) and not _kit_locked(f) and actor.runtime.states.status == "normal"
			if _kit_locked(f):
				input.held.shield = false
				f.shield_command = false
		var acceptance_facing: float = f.facing
		if not _kit_locked(f) and f.force == null and f.grab == null and f.caught_by == 0 and not is_zero_approx(input.axis.x): f.facing = signf(input.axis.x)
		var command := {"move_x": input.axis.x, "shield": input.held.get("shield", false),
			"jump_held": input.held.get("jump", false), "jump_released": input.released.get("jump", false)}
		if f.defense != null:
			var request_defense: Dictionary = f.buffer.peek("shield")
			var wants_dodge: bool = not request_defense.is_empty() and (not actor.runtime.grounded or request_defense.axis != Vector2.ZERO)
			var before: String = f.defense.state
			var allowed: bool = not _kit_locked(f) and not _ledge_attached(id) and tick >= f.ready_tick and actor.runtime.states.status == "normal" and actor.runtime.states.action != "landing_lock" and actor.runtime.states.locomotion != "jump_startup" and f.force == null and f.grab == null and f.caught_by == 0 and f.recovery == null and not actor.runtime.recovery_motion
			if actor.runtime.states.status != "normal": f.defense.interrupt("status")
			var defense: Dictionary = f.defense.advance({"shield_held": command.shield and not wants_dodge and allowed, "grounded": actor.runtime.grounded,
				"frozen": f.frozen, "dodge_requested": wants_dodge and allowed, "dodge_direction": Vector2(request_defense.axis.x, -request_defense.axis.y) if wants_dodge else Vector2.ZERO})
			if defense.state == "shield" and not request_defense.is_empty() and not wants_dodge: f.buffer.consume("shield")
			if defense.state == "dodge_startup" and before in ["idle", "shield"]: f.buffer.consume("shield")
			command.shield = defense.action_locked
			if before != "idle" and not defense.action_locked and actor.runtime.states.action == "movement_lock" and f.force == null and f.grab == null:
				actor.runtime.states.transition("action", "neutral", "defense released")
			if defense.state == "dodge_invulnerable": command.defense_velocity = Vector3(defense.motion_velocity.x, defense.motion_velocity.y, 0)
		if ledge_policy != null:
			var intent := "drop" if input.axis.y > 0.1 or not f.buffer.peek("down").is_empty() else ""
			if _ledge_attached(id):
				command.shield = true
				if not f.buffer.peek("jump").is_empty(): intent = "jump"
				elif intent != "drop":
					for anchor in ledge_anchors:
						if anchor.anchor_id == ledge_state.actors[id].anchor_id and (input.axis.y < -0.1 or input.axis.x * anchor.outward < -0.1): intent = "climb"
			_ledge_intents[id] = intent
		var request: Dictionary = f.buffer.peek("attack")
		if f.kit != null and not _kit_locked(f) and not request.is_empty() and actor.runtime.states.movement_allowed() and not command.shield:
			_next_activation += 1
			var identity := "%d:%d" % [generation, _next_activation]
			if f.kit.start_basic(identity, request.axis, not actor.runtime.grounded, acceptance_facing):
				f.buffer.consume("attack")
				f.activation_id = identity
				f.move_id = f.kit.snapshot().basic.clip
				f.facing = f.kit.snapshot().basic.facing
		if f.kit == null and not request.is_empty() and tick >= f.ready_tick and f.enabled and actor.runtime.states.movement_allowed() and not command.shield and f.force == null:
			f.buffer.consume("attack")
			# Restore nonzero press-time x even on delayed vertical diagonals.
			# Zero x retains acceptance-facing, matching existing core basics.
			# Freeze query facing below; later steering never rotates this contact.
			if not is_zero_approx(request.axis.x): f.facing = signf(request.axis.x)
			_next_activation += 1
			f.activation_id = "%d:%d" % [generation, _next_activation]
			var definition = _side if actor.runtime.grounded else _air
			if request.axis.y < -AIM_THRESHOLD.y:
				definition = _uppercut if actor.runtime.grounded else _up_air
			elif request.axis.y > AIM_THRESHOLD.y:
				definition = _low_sweep if actor.runtime.grounded else _down_strike
			f.move_id = definition.move_id
			f.ready_tick = tick + definition.cooldown_ticks()
			var strike := {"source": id, "activation_id": f.activation_id, "facing": f.facing, "definition": definition}
			strikes.append(strike)
			f.source_melee_strike = strike
			f.source_melee_victims = {}
		var special: Dictionary = f.buffer.peek("special")
		if f.kit != null and not _kit_locked(f) and not special.is_empty() and actor.runtime.states.movement_allowed() and not command.shield:
			_next_activation += 1
			var identity := "%d:%d" % [generation, _next_activation]
			if f.kit.start_special(identity, special.axis, acceptance_facing, not actor.runtime.recovery_spent):
				f.buffer.consume("special")
				f.activation_id = identity
				f.move_id = f.kit.snapshot().special.move
				f.facing = f.kit.snapshot().special.facing
				_commit_kit_intents(f.kit.initial_requests(id, actor.global_position), command)
		if f.kit == null and not special.is_empty() and special.axis.y < Recovery.UP_THRESHOLD.y and tick >= f.ready_tick and actor.runtime.states.movement_allowed() and not command.shield and f.force == null and not actor.runtime.recovery_spent:
			if not is_zero_approx(special.axis.x): f.facing = signf(special.axis.x)
			_next_activation += 1
			f.activation_id = "%d:%d" % [generation, _next_activation]
			f.recovery = Recovery.new(f.facing, f.activation_id)
			f.move_id = "RISING STRIKE"
			f.ready_tick = tick + Recovery.COOLDOWN_TICKS
			command.recovery_launch = true
			f.buffer.consume("special")
		if f.kit == null and not special.is_empty() and absf(special.axis.y) <= 0.1 and absf(special.axis.x) > 0.1 and tick >= f.ready_tick and actor.runtime.states.movement_allowed() and not command.shield and f.force == null:
			f.facing = signf(special.axis.x)
			_next_activation += 1
			f.activation_id = "%d:%d" % [generation, _next_activation]
			f.force = Force.new(f.facing, f.activation_id)
			f.move_id = "FORCE PUSH"
			f.ready_tick = tick + Force.COOLDOWN_TICKS
			f.buffer.consume("special")
		if f.kit == null and not special.is_empty() and special.axis == Vector2.ZERO and tick >= f.ready_tick and tick >= f.magic_ready_tick and actor.runtime.states.movement_allowed() and not command.shield and f.force == null and f.grab == null:
			_next_activation += 1
			f.activation_id = "%d:%d" % [generation, _next_activation]
			f.grab = Grab.new(f.facing, f.activation_id, grab_hold_duration)
			f.move_id = "ELECTRIC GRAB"
			f.ready_tick = tick + f.grab.cooldown_ticks()
			f.magic_ready_tick = tick + 210
			f.buffer.consume("special")
		if f.kit != null:
			f.kit.advance(input.held.get("special", false))
			if f.kit.braking(): command.move_x = 0.0
		if (f.force != null or f.grab != null) and actor.runtime.hitstun_left == 0: command.shield = true
		if f.caught_by != 0: command.restrained_velocity = _restrained_velocity(id)
		if not _kit_locked(f) and not command.get("recovery_launch", false) and not f.buffer.peek("jump").is_empty() and not command.shield and actor.can_accept_jump():
			f.buffer.consume("jump")
			command.jump = true
		if not _kit_locked(f) and not command.get("recovery_launch", false) and not f.buffer.peek("down").is_empty() and actor.runtime.states.movement_allowed() and not command.shield and (actor.runtime.grounded or actor.velocity.y <= 0):
			f.buffer.consume("down")
			command.down = true
		if _ledge_attached(id): command.ledge_hold = true
		if overlap_directions.has(id): command.body_overlap_direction = overlap_directions[id]
		var was_grounded: bool = actor.runtime.grounded
		var motion_start: Transform3D = actor.global_transform
		actor.simulate(command)
		_resolve_native_ledge_pressure(id, motion_start)
		if f.kit != null: f.kit.landed(actor.runtime.grounded)
		if not was_grounded and actor.runtime.grounded: _ledge_landed[id] = true
		_reconcile_defense_support(f)
		_reconcile_status(id)
		if f.recovery != null and actor.runtime.grounded and actor.runtime.velocity.y <= 0:
			f.recovery = null
	_end_top_support_motion()
	_advance_ground_jostle(ids)
	_advance_top_support()
	_advance_ledges(ids)
	for id in ids:
		var f: Dictionary = fighters[id]
		if f.force == null or _stopped.has(id): continue
		if f.force.advance():
			var shot := {"source": id, "activation_id": f.activation_id, "facing": f.force.facing, "position": f.force.origin(f.actor.global_position), "spawn_tick": tick, "ttl": 96}
			projectiles.append(shot)
			ability_events.append(shot.duplicate(true))
		if f.force.age >= Force.END_TICKS: cancel_action(id, "force complete")
	_commit_collision_poses(ids)
	for id in ids:
		if not _stopped.has(id): _advance_grab(id)
	for id in ids:
		var f: Dictionary = fighters[id]
		if f.kit == null or not f.enabled or _stopped.has(id): continue
		if f.kit_id == "turbofit":
			f.kit.basic.source_shapes = preload("res://scripts/core/combat/source_melee.gd").shapes(f.get("collision_host"),f.actor.global_transform)
		for contact in f.kit.collect(id, f.actor.global_position, _kit_targets(id), _reflectable_projectiles()):
			_commit_kit_intents([contact])
	# Snapshot all candidates before any hit can cancel a source.
	for source_id in ids:
		var source: Dictionary = fighters[source_id]
		if source.recovery == null or _stopped.has(source_id): continue
		var recovery = source.recovery
		recovery.advance()
		for victim_id in ids:
			var victim: Dictionary = fighters[victim_id]
			if victim_id == source_id or not victim.enabled or (source.team >= 0 and source.team == victim.team): continue
			var candidate: Dictionary = recovery.contact(source_id, victim_id, victim.actor.global_position - source.actor.global_position, tick, victim, source.actor.global_position)
			if not candidate.is_empty(): events.append(candidate)
		if recovery.age >= Recovery.ACTIVE_TICKS: source.recovery = null
	for source_id in ids:
		var f: Dictionary = fighters[source_id]
		var pending: Dictionary = f.get("source_melee_strike",{})
		if pending.is_empty() or f.get("collision_host") == null or not f.enabled or _stopped.has(source_id): continue
		if f.activation_id != pending.activation_id or f.actor.runtime.states.status != "normal": continue
		if not strikes.has(pending):
			var continuing := pending.duplicate()
			continuing.generated_only = true
			strikes.append(continuing)
	for strike in strikes:
		for id in ids:
			if id == strike.source: continue
			var source: Dictionary = fighters[strike.source]
			var victim: Dictionary = fighters[id]
			if not victim.enabled or (source.team >= 0 and source.team == victim.team): continue
			var offset: Vector3 = victim.actor.global_position - source.actor.global_position
			var recipient = preload("res://scripts/core/collision/recipient_queries.gd")
			var contact := {}
			if recipient.generated(victim):
				if source.get("source_melee_victims",{}).has(id): continue
				var melee = preload("res://scripts/core/combat/source_melee.gd")
				contact = melee.contact(victim,melee.shapes(source.get("collision_host"),source.actor.global_transform))
				if contact.is_empty(): continue
				source.source_melee_victims[id] = true
			elif strike.get("generated_only",false) or not strike.definition.contains(offset, strike.facing): continue
			events.append(recipient.annotate({"source": strike.source, "victim": id, "activation_id": strike.activation_id, "tick": tick, "damage": strike.definition.damage, "base_knockback": strike.definition.base_knockback, "direction": strike.definition.launch_direction(strike.facing)},victim,contact))
	var surviving: Array[Dictionary] = []
	for shot in projectiles:
		var outcome: Dictionary = preload("res://scripts/core/combat/force_projectile.gd").advance(shot, fighters, tick)
		if outcome.has("contact"): events.append(outcome.contact)
		if not outcome.get("consumed", false): surviving.append(shot)
	projectiles = surviving
	_advance_waves()
	_advance_host_projectiles()
	var percents: Dictionary = {}
	for id in ids: percents[id] = fighters[id].percent
	var vulnerable_events: Array[Dictionary] = []
	var ordered_contacts := events.duplicate()
	# Capture committed defense before ordered contacts can break a shield or
	# launches can interrupt dodge. Held intent is not finite shield eligibility.
	for contact in ordered_contacts:
		var target: Dictionary = fighters[contact.victim]
		contact.status_defense_eligible = target.defense.snapshot().damage_eligible if target.defense != null else not target.shield_command
	ordered_contacts.sort_custom(func(a, b):
		if a.source != b.source: return a.source < b.source
		if a.activation_id != b.activation_id: return a.activation_id < b.activation_id
		return a.victim < b.victim)
	for contact in ordered_contacts:
		var target: Dictionary = fighters[contact.victim]
		if target.defense != null:
			var key := "%s/%d" % [contact.activation_id, contact.victim]
			if _defense_seen.has(key): continue
			_defense_seen[key] = true
		if target.protection_until > tick or _ledge_protected(contact.victim): continue
		if contact.get("kind", "") == "shield_absorb":
			# Absorption was captured with collision. Spend in common contact
			# order, never let projectile iteration break a shield early.
			if target.defense != null: target.defense.on_shield_hit(contact.shield_damage)
			continue
		if target.defense != null and not target.defense.snapshot().damage_eligible:
			target.defense.on_shield_hit(contact.damage)
			continue
		vulnerable_events.append(contact)
	var resolved: Array = resolver.resolve(vulnerable_events, percents)
	for result in resolved:
		var victim: Dictionary = fighters[result.victim]
		victim.percent = result.percent
		victim.collision_hit_id = "hit:%d:%d:%d" % [generation,tick,result.victim]
		cancel_action(result.victim, "hit")
		victim.actor.apply_combat_launch(result.launch, result.hitstun_ticks)
	# All launches precede status commit so both halves of a trade survive.
	for resolved_hit in resolved:
		for contact in resolved_hit.accepted_hits:
			_commit_status_requests(contact, resolved_hit)
	# Contacts were snapshotted and resolved before freeze is committed.
	for contact in vulnerable_events:
		var key := "%s/%d" % [contact.activation_id, contact.victim]
		if _hitstop_seen.has(key): continue
		_hitstop_seen[key] = true
		if hitstop_profile == null: continue
		for id in [contact.source, contact.victim]:
			fighters[id].hitstop_left = maxi(fighters[id].hitstop_left, hitstop_profile.direct_hit_ticks)
	_sync_joint_hitstop()
	for id in ids: _reconcile_status(id)
	_commit_collision_poses(ids,"presentation")
	if rules != null: _commit_stocks(ids)
	tick += 1

func _commit_status_requests(contact: Dictionary, resolved_hit: Dictionary) -> void:
	var victim: Dictionary = fighters[contact.victim]
	if victim.status_host.shatter(contact.damage):
		_reconcile_status(contact.victim)
		victim.actor.apply_combat_launch(resolved_hit.launch, resolved_hit.hitstun_ticks)
		ability_events.append({"kind":"shatter","source":contact.source,"victim":contact.victim,"tick":tick,"generation":generation})
	for request in contact.get("status_requests",[]):
		if request.get("order", "") != "after_damage" or not request.get("requires_accepted_hit",false): continue
		if request.get("source",-1) != contact.source or request.get("victim",-1) != contact.victim: continue
		var source: Dictionary = fighters[contact.source]
		if not source.enabled or not victim.enabled or not is_instance_valid(source.actor) or not is_instance_valid(victim.actor): continue
		if source.team >= 0 and source.team == victim.team: continue
		if victim.frozen or not contact.status_defense_eligible: continue
		if not victim.status_host.apply(request): continue
		cancel_action(contact.victim,"status frozen")
		victim.actor.runtime.cancel_for_freeze()
		victim.actor.velocity = victim.actor.runtime.velocity
		victim.ready_tick = 0
		victim.shield_command = false
		_reconcile_status(contact.victim)
		ability_events.append({"kind":"freeze","source":contact.source,"victim":contact.victim,"tick":tick,"generation":generation})
func projectile_telemetry() -> Array:
	var snapshots: Array = projectile_host.snapshots()
	for shot in projectiles:
		var value: Dictionary = shot.duplicate(true)
		value.kind = "force"
		snapshots.append(value)
	for wave in waves:
		var value: Dictionary = wave.snapshot()
		value.kind = "sound_wave"
		snapshots.append(value)
	return snapshots
func _reflectable_projectiles() -> Array:
	var values: Array = []
	for shot in projectile_host.snapshots():
		values.append({"id": shot.activation_id, "owner": shot.source, "position": shot.position, "reflectable": shot.reflectable})
	for shot in projectiles:
		values.append({"id": shot.activation_id, "owner": shot.source, "position": shot.position, "reflectable": true})
	for wave in waves:
		values.append({"id": wave.activation_id, "owner": wave.source, "position": wave.position, "reflectable": wave.active})
	return values
func _commit_kit_intents(intents: Array, command: Dictionary = {}) -> void:
	for intent in intents:
		intent.tick = tick
		match intent.get("kind", "hit"):
			"hit": events.append(intent)
			"reflect":
				projectile_host.reflect(intent.projectile_id, intent.source, fighters[intent.source].team)
				for shot in projectiles:
					if shot.activation_id == intent.projectile_id:
						shot.source = intent.source
						shot.facing *= -1
				for wave in waves:
					if wave.activation_id == intent.projectile_id: wave.reflect(intent.source, fighters[intent.source].team)
				ability_events.append(intent)
			"spawn_projectile":
				intent.generation = generation
				if projectile_host.spawn(intent, fighters[intent.source].team): ability_events.append(intent)
			"spawn_wave":
				var wave = preload("res://scripts/core/kits/turbofit_wave.gd").new()
				wave.start(intent.activation_id, intent.source, fighters[intent.source].team, intent.position, intent.facing)
				waves.append(wave)
				ability_events.append(intent)
			"recovery_request":
				var f: Dictionary = fighters[intent.source]
				f.recovery = Recovery.new(intent.facing, intent.activation_id)
				command.recovery_launch = true
				ability_events.append(intent)
func set_projectile_absorbing(entity_id: int, active: bool) -> void:
	# Capability intent, not a character-name check. Interrupted/lifecycle clears it.
	fighters[entity_id].projectile_absorbing = active
func _advance_host_projectiles() -> void:
	var targets: Array = []
	var space: PhysicsDirectSpaceState3D
	for id in fighters:
		var f: Dictionary = fighters[id]
		if not is_instance_valid(f.actor) or not f.actor.is_inside_tree(): continue
		space = f.actor.get_world_3d().direct_space_state
		targets.append({"id": id, "body": f.actor, "position": f.actor.global_position, "team": f.team, "eligible": f.enabled,
			"shielding": f.defense.state == "shield" if f.defense != null else f.shield_command,
			"absorbing": f.projectile_absorbing and (f.defense == null or f.defense.snapshot().damage_eligible) and f.actor.runtime.states.status == "normal" and f.protection_until <= tick and not _ledge_protected(id)})
	for intent in projectile_host.advance(1.0 / 60.0, {"space": space, "targets": targets}):
		intent.tick = tick
		intent.generation = generation
		if intent.kind == "hit":
			var victim: Dictionary = fighters[intent.victim]
			if victim.defense == null and victim.shield_command:
				intent.damage_scale = .35
				intent.knockback_scale = .28
			events.append(intent)
		else:
			if intent.kind == "absorb": fighters[intent.victim].absorbed_damage += intent.payload_damage
			ability_events.append(intent)
func _advance_waves() -> void:
	var targets: Array = []
	for id in fighters:
		var f: Dictionary = fighters[id]
		if not is_instance_valid(f.actor) or not f.actor.is_inside_tree(): continue
		targets.append({"id": id, "body": f.actor, "team": f.team, "eligible": f.enabled, "collision_host":f.get("collision_host"),
			"shielding": f.defense.state == "shield" if f.defense != null else f.shield_command,
			"absorbing": f.projectile_absorbing and f.actor.runtime.states.status == "normal" and f.protection_until <= tick and not _ledge_protected(id)})
	for wave in waves:
		var owner: Dictionary = fighters[wave.source]
		if not is_instance_valid(owner.actor) or not owner.actor.is_inside_tree() or not owner.enabled:
			wave.cancel(); continue
		for intent in wave.tick(1.0 / 60.0, {"space": owner.actor.get_world_3d().direct_space_state, "targets": targets}):
			intent.tick = tick
			if intent.kind == "hit": events.append(intent)
			else:
				if intent.kind in ["shield_absorb", "absorb"]:
					var target: Dictionary = fighters[intent.victim]
					if target.protection_until > tick or _ledge_protected(intent.victim): continue
					if intent.kind == "shield_absorb":
						var consumed: Dictionary = intent.duplicate(true)
						consumed.shield_damage = 11.0
						events.append(consumed)
					if intent.kind == "absorb": target.absorbed_damage += intent.payload_damage
				ability_events.append(intent)
	waves = waves.filter(func(w): return w.active)
func _kit_targets(source_id: int) -> Array:
	var targets: Array = []
	var source: Dictionary = fighters[source_id]
	for id in fighters:
		var f: Dictionary = fighters[id]
		if not is_instance_valid(f.actor) or not f.actor.is_inside_tree(): continue
		var shape: CollisionShape3D = f.actor.get_node("CoreCapsule")
		targets.append({"id": id, "position": f.actor.global_position,
			"eligible": f.enabled and (source.team < 0 or source.team != f.team),
			"geometry_mode":"generated_hurtboxes" if f.get("collision_host") != null else "legacy_body_capsule",
			"hurtbox_snapshot":collision_telemetry(id),
			"capsules": [{"transform": shape.global_transform, "radius": shape.shape.radius, "height": shape.shape.height, "disabled": shape.disabled}]})
	return targets
func _reconcile_defense_support(f: Dictionary) -> void:
	# Post-move context commit, NOT a second defense timer tick. The standalone
	# policy accepts support at advance; the actor discovers it later this tick.
	var d = f.defense
	if d == null or f.frozen or f.caught_by != 0: return
	var grounded: bool = f.actor.runtime.grounded
	if grounded == d.grounded: return
	if grounded: d.air_charges = maxi(0, d.profile.air_dodges_per_flight)
	d.grounded = grounded
	if d.state in ["dodge_startup", "dodge_invulnerable"]:
		d.state = "dodge_recovery"
		d.remaining = maxi(1, d.profile.air_recovery_ticks if d.dodge_air else d.profile.ground_recovery_ticks)
	elif not grounded and d.state == "shield": d.interrupt("support lost")

func configure_rules(definition: Resource) -> void:
	assert(definition != null and definition.stock_count > 0)
	rules = definition.duplicate(true)
	for id in fighters:
		assert(rules.stage.spawns.has(id), "Stage must author every entity spawn")
		assert(not rules.stage.outside(rules.stage.spawns[id]), "Spawn must be inside blast bounds")

func rematch() -> void:
	assert(rules != null, "rematch requires explicit rules")
	reset(rules.stage.spawns)
	_publish_lifecycle("rematch")

func _publish_lifecycle(kind: String, payload: Dictionary = {}) -> void:
	_next_lifecycle += 1
	var event := payload.duplicate(true)
	event.merge({"kind": kind, "tick": tick, "generation": generation,
		"event_id": "%d:L%d" % [generation, _next_lifecycle]}, true)
	lifecycle_events.append(event)

func _clean_life(id: int, at: Vector3) -> void:
	var f: Dictionary = fighters[id]
	expire_source(id, "stock lifecycle")
	_invalidate_collision(id,"stock lifecycle")
	if ledge_state.has("actors"): ledge_state.actors.erase(id)
	ledge_events.erase(id)
	f.buffer = Buffer.new()
	f.percent = 0.0; f.ready_tick = 0; f.magic_ready_tick = 0
	f.grab_immune_until = 0; f.protection_until = 0
	f.manual_frozen = false; f.frozen = false; f.shield_command = false; f.facing = 1.0
	f.actor.reset_at(at)
	if f.defense != null: f.defense.reset(false)
	_reconcile_status(id)

func _commit_stocks(ids: Array) -> void:
	# Snapshot ALL blasts after combat, before any cleanup or relocation.
	var knocked: Array = []
	for id in ids:
		var f: Dictionary = fighters[id]
		if f.enabled and not f.eliminated and is_instance_valid(f.actor) and rules.stage.outside(f.actor.global_position): knocked.append(id)
	if knocked.is_empty(): return
	var supported_riders = top_support.relations.keys()
	for id in knocked:
		var f: Dictionary = fighters[id]
		f.stocks = maxi(0, f.stocks - 1)
		f.eliminated = f.stocks == 0
		_publish_lifecycle("ko", {"entity_id": id, "stocks": f.stocks, "position": f.actor.global_position})
	for id in knocked:
		var f: Dictionary = fighters[id]
		_clean_life(id, rules.stage.spawns[id])
		if f.eliminated:
			set_enabled(id, false)
			_publish_lifecycle("eliminated", {"entity_id": id, "stocks": 0})
		else:
			f.protection_until = tick + 1 + rules.respawn_protection_ticks if rules.respawn_protection_ticks > 0 else 0
			if rules.respawn_hitstun_ticks > 0: f.actor.apply_combat_launch(Vector3.ZERO, rules.respawn_hitstun_ticks)
			_publish_lifecycle("respawn", {"entity_id": id, "stocks": f.stocks, "position": f.actor.global_position})
	# Stocks run after the presentation commit. Reconcile only surviving riders
	# whose carrier life was retired, preserving their pre-contact witnesses.
	for rider in supported_riders:
		if rider not in knocked and not top_support.relations.has(rider): _commit_collision_poses([rider],"presentation")
	var survivors: Array = []
	for id in ids:
		if not fighters[id].eliminated and fighters[id].stocks > 0: survivors.append(id)
	if survivors.size() <= 1:
		result = {"kind": "DRAW" if survivors.is_empty() else "WIN", "winner_id": 0 if survivors.is_empty() else survivors[0], "tick": tick, "generation": generation}
		for id in ids:
			expire_source(id, "results")
			if fighters[id].defense != null: fighters[id].defense.reset(fighters[id].actor.runtime.grounded)
			fighters[id].buffer = Buffer.new()
		ledge_state = {}; ledge_events = {}; _ledge_intents.clear(); _ledge_landed.clear()
		_publish_lifecycle("result", {"result": result.duplicate(true)})

func _release_grab(id: int) -> void:
	var f: Dictionary = fighters[id]
	var g = f.grab
	if g == null or g.victim == 0: return
	var v: Dictionary = fighters[g.victim]
	if v.caught_by == id:
		v.caught_by = 0; v.grab_immune_until = tick + 60
		if is_instance_valid(v.actor):
			_reconcile_status(g.victim)
			v.actor.runtime.velocity = Vector3(0, minf(v.actor.velocity.y, 0), 0)
			v.actor.velocity = v.actor.runtime.velocity
		ability_events.append({"kind": "grab_release", "source": id, "victim": g.victim, "activation_id": g.activation_id})
	if is_instance_valid(f.actor) and is_instance_valid(v.actor):
		f.actor.remove_collision_exception_with(v.actor); v.actor.remove_collision_exception_with(f.actor)
		f.actor.clear_body_contacts(); v.actor.clear_body_contacts()
	g.victim = 0
func _cancel_grab(id: int) -> void:
	if not fighters.has(id): return
	var f: Dictionary = fighters[id]
	if f.grab == null: return
	_release_grab(id)
	f.grab = null; f.move_id = ""; f.activation_id = ""
	if is_instance_valid(f.actor) and f.actor.runtime.states.action == "movement_lock":
		f.actor.runtime.states.transition("action", "neutral", "grab complete")
func _restrained_velocity(id: int) -> Vector3:
	var v: Dictionary = fighters[id]
	var f: Dictionary = fighters[v.caught_by]
	if f.grab == null or not is_instance_valid(f.actor) or not f.enabled or f.frozen:
		cancel_action(id, "broken grab owner"); return Vector3.ZERO
	var anchor: Vector3 = f.grab.anchor(f.actor.global_position)
	var error: Vector3 = anchor - v.actor.global_position
	if error.length() > 0.8 or not Grab.clear_path(v.actor, v.actor.global_position + Vector3.UP, anchor + Vector3.UP, fighters):
		cancel_action(id, "broken grab anchor"); return Vector3.ZERO
	return (error * 60.0).limit_length(3.0)
func _advance_grab(id: int) -> void:
	var f: Dictionary = fighters[id]
	var g = f.grab
	if g == null: return
	if not f.enabled or f.frozen or f.caught_by != 0 or f.actor.runtime.hitstun_left > 0:
		_cancel_grab(id); return
	if g.victim != 0:
		var v: Dictionary = fighters[g.victim]
		if not is_instance_valid(v.actor) or not v.enabled or v.frozen or f.actor.global_position.distance_to(v.actor.global_position) > 2.1 or (f.team >= 0 and f.team == v.team):
			_cancel_grab(id); return
	g.age += 1
	g.elapsed += 1.0 / 60.0
	if g.age == 12:
		var eligible := {}
		for target_id in fighters:
			eligible[target_id] = fighters[target_id].duplicate()
			if fighters[target_id].protection_until > tick or _ledge_protected(target_id): eligible[target_id].enabled = false
			if fighters[target_id].defense != null:
				eligible[target_id].shield_command = false
				if not fighters[target_id].defense.snapshot().grab_eligible: eligible[target_id].enabled = false
		var target: int = g.closest(id, eligible, tick)
		if target != 0:
			cancel_action(target, "captured")
			var v: Dictionary = fighters[target]
			g.victim = target; v.caught_by = id
			v.actor.cancel_for_grab()
			g.anchor_offset = v.actor.global_position - f.actor.global_position
			g.hand_reference = Grab.sample("GrabStart", 13.0 / 24.0, g.facing)
			f.actor.add_collision_exception_with(v.actor); v.actor.add_collision_exception_with(f.actor)
			f.actor.clear_body_contacts()
			ability_events.append({"kind": "grab_capture", "source": id, "victim": target, "activation_id": g.activation_id, "geometry_mode":g.contact_geometry, "contact_evidence":g.contact_evidence.duplicate(true)})
	if g.phase == "startup" and g.elapsed + 0.000001 >= Grab.START_END:
		g.elapsed = maxf(0, g.elapsed - Grab.START_END)
		g.phase = "hold" if g.victim != 0 else "ending"
	if g.phase == "hold":
		var due := int(floor((minf(g.elapsed, g.hold_duration) + 0.000001) / 0.25))
		while g.ordinal < due:
			g.ordinal += 1
			fighters[g.victim].percent += 2.0
			ability_events.append({"kind": "grab_damage", "source": id, "victim": g.victim, "activation_id": g.activation_id, "ordinal": g.ordinal, "damage": 2.0})
		if g.elapsed + 0.000001 >= g.hold_duration:
			g.elapsed = maxf(0, g.elapsed - g.hold_duration); g.phase = "ending"
	if g.phase == "ending":
		if g.elapsed + 0.000001 >= 5.0 / 24.0: _release_grab(id)
		if g.elapsed + 0.000001 >= Grab.END_LENGTH: _cancel_grab(id)
