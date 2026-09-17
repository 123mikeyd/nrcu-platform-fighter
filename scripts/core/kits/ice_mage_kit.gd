extends RefCounted
## Analytic source contact, independent of presentation and victim state.
const IMPACT := .2
const DURATION := .55
const DAMAGE := 8.0
const KNOCKBACK := 3.8
const RANGE := 2.5
var activation_id := ""
var clip := ""
var elapsed := 0.0
var facing := 1.0
var direction := Vector3.RIGHT
var _pending := false
var _struck := false
var _cooldown := 0.0
func start(id: String, aim: Vector2, airborne: bool, input_facing: float) -> bool:
	if id.is_empty() or not clip.is_empty(): return false
	activation_id = id
	clip = "IceStrike"
	_cooldown = DURATION
	elapsed = 0
	facing = input_facing
	direction = Vector3(facing,0,0)
	if aim.y < -.1: direction = Vector3.UP
	elif aim.y > .1: direction = Vector3.DOWN if airborne else Vector3(facing,-.25,0).normalized()
	else:
		if absf(aim.x) > .1: facing = signf(aim.x)
		direction = Vector3(facing,0,0)
	_pending = false
	_struck = false
	return true
func tick(delta: float, advance_cooldown: bool = true) -> void:
	_pending = false
	if advance_cooldown: _cooldown = maxf(0,_cooldown-maxf(0,delta))
	if clip.is_empty() or delta <= 0: return
	elapsed += delta
	if not _struck and elapsed + .000001 >= IMPACT:
		_struck = true
		_pending = true
		_cooldown = maxf(0,DURATION-elapsed)
	# Keep a crossed event until collection even when this step ends the clip.
	if elapsed >= DURATION: clip = ""
func contacts(source: int, origin: Vector3, targets: Array) -> Array:
	var result: Array = []
	if not _pending: return result
	_pending = false
	var ordered := targets.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return a.id < b.id)
	var seen := {}
	for target in ordered:
		if target.id == source or seen.has(target.id) or not target.get("eligible",true): continue
		seen[target.id] = true
		var offset: Vector3 = target.position - origin
		if absf(offset.z) >= 1.5 or offset.length() > RANGE or offset.normalized().dot(direction) <= .4: continue
		var launch := direction
		if absf(direction.y) < .5: launch.y = .35
		result.append({"kind":"hit", "source":source, "victim":target.id, "activation_id":activation_id, "hit_ordinal":0, "damage":DAMAGE, "base_knockback":KNOCKBACK, "direction":launch})
	return result
func cancel() -> void:
	clip = ""
	activation_id = ""
	_cooldown = 0
	elapsed = 0
	_pending = false
	_struck = false
func snapshot() -> Dictionary:
	return {"clip":clip,"active":not clip.is_empty(),"elapsed":elapsed,"remaining":_cooldown,"activation_id":activation_id,"facing":facing,"phase":"idle" if clip.is_empty() else ("recovery" if _struck else "windup"),"presentation":{"clip":clip,"elapsed":elapsed,"duration":DURATION,"facing":facing,"activation_id":activation_id}}
