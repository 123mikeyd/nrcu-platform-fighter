extends RefCounted
## Value-only detached projectile factory/lifecycle adapter; match supplies physics.
var factories := {"frost_bolt": preload("res://scripts/core/kits/ice_frost_projectile.gd")}
var live: Array = []
func register_factory(kind: String, factory: Script) -> void:
	assert(not kind.is_empty() and factory != null)
	factories[kind] = factory
func spawn(request: Dictionary, team: int) -> bool:
	if not factories.has(request.projectile_kind): return false
	var shot = factories[request.projectile_kind].new()
	if not shot.start(request.activation_id, request.source, team, request.position, request.facing): return false
	live.append(shot)
	return true
func expire_source(id: int) -> void:
	for shot in live: shot.expire_source(id)
	live = live.filter(func(s): return s.active)
func snapshots() -> Array:
	var values: Array = []
	for shot in live: values.append(shot.snapshot())
	return values
func reflect(id: String, source: int, team: int) -> void:
	for shot in live:
		if shot.activation_id == id: shot.reflect(source, team)
func advance(delta: float, context: Dictionary) -> Array:
	var values: Array = []
	for shot in live: values.append_array(shot.tick(delta,context))
	live = live.filter(func(s): return s.active)
	return values
