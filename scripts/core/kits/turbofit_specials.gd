extends RefCounted
## Caller-ticked special episodes. Host owns eligibility and commits effects.
const MAX_CHARGE := 1.5
const ORB_DURATION := 0.55
const ORB_RADIUS := 1.15
const ORB_KNOCKBACK := 7.0
var activation_id := ""
var move := ""
var phase := "idle"
var age := 0.0
var power := 0.0
var facing := 1.0
var cooldown := 0.0
var _release_pending := false
var _request_pending := false
var _paused := false
var _targets: Dictionary = {}
var _projectiles: Dictionary = {}

func start(id: String, aim: Vector2, input_facing: float) -> bool:
	if id.is_empty() or phase != "idle" or cooldown > .000001: return false
	if aim != Vector2.ZERO and absf(aim.x) <= .1 and absf(aim.y) <= .1: return false
	activation_id = id
	move = "power_chord"
	phase = "anticipation"
	facing = input_facing
	if aim.y < -.1:
		move = "rising_chord"
		phase = "recovery"
		cooldown = .65
		_request_pending = true
	elif aim.y > .1:
		move = "sound_orb"
		phase = "active"
		cooldown = .75
	elif absf(aim.x) > .1:
		move = "sound_wave"
		phase = "recovery"
		cooldown = .55
		facing = signf(aim.x)
		_request_pending = true
	age = 0.0
	power = 0.0
	_paused = false
	return true

func tick(delta: float, context: Dictionary = {}) -> Dictionary:
	if context.get("interrupted", false) or context.get("disabled", false) or context.get("frozen", false):
		cancel(context.get("reason", "") in ["reset", "stock", "result", "exit", "rematch"])
		return snapshot()
	_paused = not context.get("advance", true) or context.get("paused", false) or context.get("hitstop", false)
	if _paused or delta <= 0.0: return snapshot()
	if phase == "idle": cooldown = maxf(0.0, cooldown - delta)
	if phase == "anticipation":
		if context.get("held", true):
			age += delta
			power = minf(age / MAX_CHARGE, 1.0)
		else:
			phase = "release"
			age = 0.0
			cooldown = 0.7
			_release_pending = true
	elif phase in ["release", "active", "recovery"]:
		age += delta
		cooldown = maxf(0.0, cooldown - delta)
		if move == "sound_orb" and age >= ORB_DURATION:
			phase = "recovery"
			_targets.clear()
			_projectiles.clear()
		if cooldown <= 0.000001: cancel()
	return snapshot()

func collect(source: int, origin: Vector3, targets: Array, projectiles: Array = []) -> Array:
	var result: Array = []
	if _paused: return result
	if _request_pending:
		_request_pending = false
		if move == "sound_wave":
			return [{"kind":"spawn_wave", "source":source, "activation_id":activation_id, "position":origin + Vector3(facing*.8,1,0), "facing":facing}]
		return [{"kind":"recovery_request", "source":source, "activation_id":activation_id, "facing":facing, "ability_script":"res://scripts/core/combat/recovery_ability.gd", "vertical_speed":13.5, "active_seconds":.38, "cooldown_seconds":.65, "spend_recovery":true, "jumps_used":2}]
	if move == "sound_orb" and phase == "active":
		return _collect_orb(source, origin, targets, projectiles)
	if not _release_pending: return result
	_release_pending = false
	var ordered := targets.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return a.id < b.id)
	for target in ordered:
		if target.id == source or not target.get("eligible", true): continue
		var offset: Vector3 = target.position - origin
		var recipient = preload("res://scripts/core/collision/recipient_queries.gd")
		var contact := {}
		if recipient.generated(target):
			contact = recipient.cone(target,origin,Vector3(facing,0,0),3.0)
			if contact.is_empty(): continue
		elif not (absf(offset.z) < 1.5 and offset.length() <= 3.0 and offset.normalized().dot(Vector3(facing,0,0)) > .4): continue
		result.append(recipient.annotate({"kind": "hit", "source": source, "victim": target.id, "activation_id": activation_id, "hit_ordinal": 0, "damage": lerpf(10,26,power), "base_knockback": lerpf(4,9,power), "direction": Vector3(facing,.35,0)},target,contact))
	return result

func _collect_orb(source: int, origin: Vector3, targets: Array, projectiles: Array) -> Array:
	var result: Array = []
	var ordered := targets.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return a.id < b.id)
	for target in ordered:
		if target.id == source or not target.get("eligible", true) or _targets.has(target.id): continue
		var offset: Vector3 = target.position - origin
		var recipient = preload("res://scripts/core/collision/recipient_queries.gd")
		var contact := {}
		if recipient.generated(target):
			contact = recipient.sphere(target,origin,origin,ORB_RADIUS)
			if contact.is_empty(): continue
		elif offset.length() > ORB_RADIUS: continue
		_targets[target.id] = true
		var direction := offset.normalized() if offset.length() > .001 else Vector3(facing,.25,0).normalized()
		result.append(recipient.annotate({"kind":"hit", "source":source, "victim":target.id, "activation_id":activation_id, "hit_ordinal":0, "damage":0.0, "base_knockback":ORB_KNOCKBACK, "direction":direction},target,contact))
	ordered = projectiles.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return a.id < b.id)
	for shot in ordered:
		if shot.owner == source or not shot.get("reflectable", false) or _projectiles.has(shot.id): continue
		if (origin + Vector3.UP).distance_to(shot.position) <= ORB_RADIUS:
			_projectiles[shot.id] = true
			result.append({"kind":"reflect", "source":source, "projectile_id":shot.id, "activation_id":activation_id})
	return result

func snapshot() -> Dictionary:
	return {"activation_id": activation_id, "move": move, "phase": phase, "age": age, "power": power, "facing": facing, "cooldown": cooldown}

func cancel(reset_cooldown: bool = true) -> void:
	activation_id = ""
	move = ""
	phase = "idle"
	age = 0.0
	power = 0.0
	if reset_cooldown: cooldown = 0.0
	_release_pending = false
	_request_pending = false
	_paused = false
	_targets.clear()
	_projectiles.clear()
