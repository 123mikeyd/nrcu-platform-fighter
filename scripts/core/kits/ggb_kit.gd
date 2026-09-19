extends RefCounted
## Caller-committed GGB actions; no scene ownership or victim mutation.
const STEP := 1.0 / 60.0
var cooldown := 0.0
var move := ""
var identity := ""
var facing := 1.0
var direction := Vector3.RIGHT
var _pending := false
func locked() -> bool:
	return cooldown > 0
func start_basic(id: String, aim: Vector2, airborne: bool, input_facing: float) -> bool:
	if id.is_empty() or locked(): return false
	identity = id
	facing = input_facing
	direction = Vector3(facing,0,0)
	if aim.y < -.1:
		direction = Vector3.UP
		move = "UP AIR" if airborne else "UPPERCUT"
	elif aim.y > .1:
		direction = Vector3.DOWN if airborne else Vector3(facing,-.25,0).normalized()
		move = "DOWN STRIKE" if airborne else "LOW SWEEP"
	else:
		if absf(aim.x) > .1: facing = signf(aim.x)
		direction = Vector3(facing,0,0)
		move = "AIR STRIKE" if airborne else "SIDE STRIKE"
	cooldown = .32
	_pending = true
	return true
func prepare(_held: bool) -> void:
	cooldown = maxf(0,cooldown-STEP)
func collect(source: int, origin: Vector3, targets: Array, _projectiles: Array = []) -> Array:
	if not _pending: return []
	_pending = false
	return _cone(source,origin,targets,8,3.8,2.5)
func _cone(source: int, origin: Vector3, targets: Array, damage: float, knockback: float, reach: float) -> Array:
	var result: Array = []
	var ordered := targets.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary): return a.id < b.id)
	var seen := {}
	for target in ordered:
		if target.id == source or seen.has(target.id) or not target.get("eligible",true): continue
		seen[target.id] = true
		var offset: Vector3 = target.position-origin
		if absf(offset.z) >= 1.5 or offset.length() > reach or offset.normalized().dot(direction) <= .4: continue
		var launch := direction
		if absf(direction.y) < .5: launch.y = .35
		result.append(_hit(source,target.id,damage,knockback,launch))
	return result
func _hit(source: int, victim: int, damage: float, knockback: float, launch: Vector3) -> Dictionary:
	return {"kind":"hit","source":source,"victim":victim,"activation_id":identity,"hit_ordinal":0,"damage":damage,"base_knockback":knockback,"direction":launch}
func cancel(reset: bool = false) -> void:
	_pending = false
	move = ""
	identity = ""
	if reset: cooldown = 0
func snapshot() -> Dictionary:
	return {"kit_id":"ggb","basic":{"clip":move,"remaining":cooldown},"action_locked":locked()}
