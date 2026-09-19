extends RefCounted
## Match-owned relation solver. Bounded gameplay envelope, never animated bones.
var relations := {}
var starts := {}
var diagnostics := {}
var envelopes := {}
func envelope(id: int, definition: Resource, airborne: bool, advance: bool) -> Dictionary:
	if definition == null: return {}
	var value: Dictionary = envelopes.get(id,definition.geometry()).duplicate(true)
	if advance:
		value.pose_category = "airborne" if airborne else "upright"
		value.height = move_toward(float(value.height),definition.airborne_height if airborne else definition.height,0.08)
		envelopes[id] = value.duplicate(true)
	return value
func release(id: int) -> void:
	relations.erase(id)
	for rider in relations.keys():
		if relations[rider].carrier == id: relations.erase(rider)
func reset() -> void:
	relations.clear(); starts.clear(); diagnostics.clear(); envelopes.clear()
func begin(snapshots: Dictionary) -> void:
	starts = snapshots.duplicate(true)
func valid_snapshot(value: Dictionary) -> bool:
	if not value.get("eligible",false): return false
	if not value.get("position") is Vector3 or not value.position.is_finite(): return false
	if not value.get("velocity") is Vector3 or not value.velocity.is_finite(): return false
	var profile = value.get("profile")
	if not profile is Dictionary: return false
	for key in ["height","half_width","foot_radius"]:
		var number = profile.get(key)
		if not (number is float or number is int): return false
		if not is_finite(float(number)) or float(number) <= 0.0: return false
	return true
func solve(ends: Dictionary, generation: int) -> Dictionary:
	var proposals := {}; diagnostics.clear()
	var ids = ends.keys(); ids.sort()
	for id in ids:
		var rider: Dictionary = ends[id]
		if not starts.has(id) or not valid_snapshot(rider) or not valid_snapshot(starts[id]):
			release(id); continue
		var before: Dictionary = starts[id]
		var best := {}; var best_time := INF
		for carrier in ids:
			if carrier == id or not starts.has(carrier): continue
			var lower: Dictionary = ends[carrier]; var old: Dictionary = starts[carrier]
			if not valid_snapshot(lower) or not valid_snapshot(old): continue
			var plane0: float = old.position.y + old.profile.height
			var plane1: float = lower.position.y + lower.profile.height
			var gap0: float = before.position.y - plane0
			var gap1: float = rider.position.y - plane1
			var relation: Dictionary = relations.get(id,{})
			var retained: bool = relation.get("carrier",0) == carrier and relation.get("generation",0) == generation and absf(gap0) < 0.035
			# Acquisition sweeps the physical relative foot trajectory against the
			# start plane. Category growth is not carrier travel. Also require the
			# end envelope to be reached (a shrinking plane may escape the foot).
			var physical_gap1: float = rider.position.y-lower.position.y-old.profile.height
			var relative_descent: float = gap0-physical_gap1
			if rider.velocity.y > 0 and rider.velocity.y > lower.velocity.y + 0.01: continue
			var crossing: bool = gap0 >= -0.002 and physical_gap1 <= 0.002 and gap1 <= 0.002 and relative_descent > 0.000001
			# Existing relations may follow bounded category changes through the
			# same terrain-tested commit path; they do not need a fresh crossing.
			if not crossing and not (retained and gap1 <= 0.035): continue
			var t: float = 0.0
			if not retained:
				t = clampf(gap0/relative_descent,0,1)
				# Shrinkage can delay contact beyond the physical start-plane
				# crossing. Test the footprint only once both planes are reached.
				if gap0-gap1 > 0.000001: t = maxf(t,clampf(gap0/(gap0-gap1),0,1))
			var width: float = lower.profile.half_width + rider.profile.foot_radius
			var dx0: float = before.position.x-old.position.x
			var dx1: float = rider.position.x-lower.position.x
			if absf(lerpf(dx0,dx1,t)) > width or absf(dx1) > width + (0.025 if retained else 0.0): continue
			if t >= best_time: continue
			best_time = t
			best = {"carrier":carrier,"generation":generation,"plane":plane1,"crossing_fraction":t,"direction":relation.get("direction",signf(dx1) if absf(dx1)>0.01 else 1.0)}
		if best.is_empty(): relations.erase(id)
		else: proposals[id] = best
	return proposals
func commit(id: int, proposal: Dictionary, accepted: bool) -> void:
	diagnostics[id] = proposal.duplicate(true)
	diagnostics[id].accepted = accepted
	if accepted: relations[id] = proposal.duplicate(true)
	else: relations.erase(id)
func snapshot(id: int) -> Dictionary:
	return {"relation":relations.get(id,{}).duplicate(true),"last_proposal":diagnostics.get(id,{}).duplicate(true)}
