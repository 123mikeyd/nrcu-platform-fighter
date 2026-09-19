extends RefCounted
## Match-owned finite hazards. Surface is a weak physics reference, never a view.
const DURATION := 3.0
const SPEED_MULTIPLIER := .65
const RADIUS := .85
const MAX_PER_OWNER := 3
var _live: Array = []
var _seen := {}
func spawn(request: Dictionary) -> bool:
	var surface: Node3D = request.get("surface")
	var key := "%s:%s" % [request.get("source",-1),request.get("activation_id","")]
	if not is_instance_valid(surface) or request.get("normal",Vector3.ZERO).y <= .6 or request.get("activation_id","").is_empty() or _seen.has(key): return false
	_seen[key] = true
	_live.append({"source":request.source,"team":request.get("team",-1),"activation_id":request.activation_id,"position":request.position,"remaining":DURATION,"surface":weakref(surface),"key":key})
	var owned: Array = _live.filter(func(p): return p.source==request.source)
	while owned.size() > MAX_PER_OWNER: _live.erase(owned.pop_front())
	return true
func _valid(pool: Dictionary, owners: Dictionary) -> bool:
	if pool.remaining <= 0 or pool.surface.get_ref() == null: return false
	if owners.is_empty(): return true
	if not owners.has(pool.source): return false
	var owner: Dictionary = owners[pool.source]
	return owner.get("enabled",true) and owner.get("valid",true) and owner.get("stocks",1)>0
func tick(delta: float, context: Dictionary = {}) -> void:
	var owners: Dictionary = context.get("owners",{})
	_live = _live.filter(func(p): return _valid(p,owners))
	if delta <= 0 or context.get("paused",false) or not context.get("advance",true): return
	for pool in _live: pool.remaining -= delta
	_live = _live.filter(func(p): return _valid(p,owners))
func collect(targets: Array, owners: Dictionary = {}) -> Array:
	var result: Array = []
	var ordered := targets.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary): return a.id < b.id)
	for pool in _live:
		if not _valid(pool,owners): continue
		var seen := {}
		for target in ordered:
			if seen.has(target.id): continue
			seen[target.id] = true
			if target.id == pool.source or not target.get("eligible",true) or not target.get("enabled",true) or target.get("stocks",1)<=0: continue
			var team: int = target.get("team",-1)
			if team>=0 and pool.team>=0 and team==pool.team: continue
			if not target.get("grounded",false) or target.get("velocity",Vector3.ZERO).y > 0: continue
			if target.get("support_surface") != pool.surface.get_ref(): continue
			var offset: Vector3 = target.position-pool.position
			if absf(offset.y)>=.16 or Vector2(offset.x,offset.z).length()>RADIUS: continue
			result.append({"kind":"ground_speed_modifier","source":pool.source,"victim":target.id,"activation_id":pool.activation_id,"multiplier":SPEED_MULTIPLIER,"combination":"minimum","scope":"this_support_sample"})
	return result
func expire_source(owner: int) -> void:
	_live = _live.filter(func(p): return p.source!=owner)
func reset() -> void:
	_live.clear()
	_seen.clear()
func snapshots() -> Array:
	var result: Array = []
	for pool in _live:
		var surface = pool.surface.get_ref()
		result.append({"kind":"goo_puddle","source":pool.source,"team":pool.team,"activation_id":pool.activation_id,"position":pool.position,"remaining":pool.remaining,"surface_id":surface.get_instance_id() if surface != null else 0})
	return result
