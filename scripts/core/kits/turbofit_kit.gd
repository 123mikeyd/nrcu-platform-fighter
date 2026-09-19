extends RefCounted
## Caller owns eligibility, world movement, clocks and resolution. No scene nodes.
const Pose = preload("res://scripts/core/kits/turbofit_contact_pose.gd")
var _pose = Pose.new()
var activation_id := ""
var clip := ""
var elapsed := 0.0
var facing := 1.0
var aim := Vector2.ZERO
var _duration := 0.0
var _paused := false
var _impact := false
var _struck := false
var _victims: Dictionary = {}
# Match supplies frozen canonical attack geometry; empty is fail-closed.
var source_shapes: Array = []

func start(id: String, input_aim: Vector2, airborne: bool, input_facing: float) -> bool:
	if not clip.is_empty() or id.is_empty(): return false
	activation_id = id
	if input_aim.y < -0.1:
		clip = "MeleeBackhand"
	elif airborne:
		clip = "AirDownKick" if input_aim.y > 0.1 else "AirSideKick"
	else:
		clip = "GoalkeeperKick" if input_aim.y > 0.1 else "MeleeHorizontal"
	elapsed = 0.0
	aim = input_aim
	facing = signf(input_aim.x) if absf(input_aim.x) > 0.1 and clip != "MeleeBackhand" else input_facing
	_duration = {"GoalkeeperKick": 59.0 / 60.0, "AirSideKick": 0.5, "AirDownKick": 38.0 / 30.0, "MeleeHorizontal": 0.8, "MeleeBackhand": 0.8}[clip]
	_struck = false
	_impact = false
	_victims.clear()
	source_shapes.clear()
	return true

func tick(delta: float, context: Dictionary = {}) -> Dictionary:
	if context.get("interrupted", false) or context.get("disabled", false):
		cancel()
		return snapshot()
	if context.get("grounded", false) and clip in ["AirSideKick", "AirDownKick"]:
		cancel()
	_paused = context.get("paused", false) or context.get("frozen", false) or context.get("hitstop", false)
	if _paused or delta <= 0: return snapshot()
	source_shapes.clear()
	_impact = false
	if not clip.is_empty():
		elapsed += maxf(delta, 0)
		var guitar := clip in ["MeleeHorizontal", "MeleeBackhand"]
		if (clip == "GoalkeeperKick" or guitar) and not _struck and elapsed + 0.000001 >= (0.28 if guitar else 0.45):
			_struck = true
			_impact = true
			if guitar: _duration = elapsed + 0.5
		if elapsed + 0.000001 >= _duration: cancel()
	return snapshot()

func cancel() -> void:
	_paused = false
	clip = ""
	activation_id = ""
	elapsed = 0.0
	_duration = 0.0
	_impact = false
	_struck = false
	_victims.clear()
	source_shapes.clear()

func snapshot() -> Dictionary:
	var phase := "idle"
	if not clip.is_empty():
		phase = "recovery" if _struck else "windup"
		if _impact: phase = "active"
		if clip in ["AirSideKick", "AirDownKick"]:
			var first := 0.4 if clip == "AirDownKick" else 5.0 / 30.0
			var last := 0.5 if clip == "AirDownKick" else 0.2
			phase = "windup" if elapsed + 0.000001 < first else ("active" if elapsed <= last + 0.000001 else "recovery")
	return {"active": not clip.is_empty(), "clip": clip, "elapsed": elapsed,
		"duration": _duration, "remaining": maxf(0, _duration - elapsed), "phase": phase, "facing": facing, "aim": aim, "activation_id": activation_id,
		"action": "basic" if not clip.is_empty() else "", "motion": {},
		"presentation": {"clip": clip, "elapsed": elapsed, "duration": 0.8 if clip in ["MeleeHorizontal", "MeleeBackhand"] else _duration, "facing": facing, "activation_id": activation_id}}

func contacts(source: int, origin: Vector3, targets: Array) -> Array:
	var result: Array = []
	if _paused or clip.is_empty(): return result
	var air := clip in ["AirSideKick", "AirDownKick"]
	var first := 0.4 if clip == "AirDownKick" else 5.0 / 30.0
	var last := 0.5 if clip == "AirDownKick" else 0.2
	if air and (elapsed + 0.000001 < first or elapsed > last + 0.000001): return result
	var direction := Vector3(facing, -0.25, 0).normalized()
	var attack_range := 2.5
	if clip in ["MeleeHorizontal", "MeleeBackhand"]:
		attack_range = 2.8
		direction = Vector3.UP if clip == "MeleeBackhand" else Vector3(facing, 0, 0)
	for target in targets:
		if target.id == source or _victims.has(target.id) or not target.get("eligible", true): continue
		var offset: Vector3 = target.position - origin
		var geometry_mode := "legacy_origin_cone"
		var evidence := {}
		if air:
			if clip == "AirSideKick" and offset.x * facing <= 0: continue
			if clip == "AirDownKick" and offset.y >= 0: continue
			var center: Vector3 = origin + _pose.center(clip, elapsed, facing)
			geometry_mode = target.get("geometry_mode","legacy_body_capsule")
			if geometry_mode == "generated_hurtboxes":
				evidence = preload("res://scripts/core/collision/recipient_queries.gd").sphere(target,center,center,.22)
				if evidence.is_empty(): continue
				evidence.source_id = activation_id; evidence.victim_id = str(target.id)
			elif geometry_mode == "legacy_body_capsule":
				if not _capsule_contact(center,target.get("capsules",[])): continue
			else: continue
		elif preload("res://scripts/core/collision/recipient_queries.gd").generated(target):
			geometry_mode = "generated_hurtboxes"
			evidence = preload("res://scripts/core/combat/source_melee.gd").contact(target,source_shapes)
			if evidence.is_empty(): continue
		elif not _impact or absf(offset.z) >= 1.5 or offset.length() > attack_range or offset.normalized().dot(direction) <= 0.4: continue
		_victims[target.id] = true
		var launch := direction
		if absf(direction.y) < 0.5: launch.y = 0.35
		if air: launch = Vector3.DOWN if clip == "AirDownKick" else Vector3(facing, 0.35, 0)
		result.append({"source": source, "victim": target.id, "activation_id": activation_id,
			"damage": 14.0, "base_knockback": 5.5, "direction": launch,"geometry_mode":geometry_mode,"contact_evidence":evidence})
	return result

func _capsule_contact(center: Vector3, capsules: Array) -> bool:
	for capsule in capsules:
		if capsule.get("disabled", false): continue
		var transform: Transform3D = capsule.transform
		var radius: float = capsule.radius
		var half_axis := maxf(0, float(capsule.height) * 0.5 - radius)
		var a := transform * Vector3(0, -half_axis, 0)
		var b := transform * Vector3(0, half_axis, 0)
		var world_radius := radius * maxf(transform.basis.x.length(), transform.basis.z.length())
		var nearest := Geometry3D.get_closest_point_to_segment(center, a, b)
		if center.distance_squared_to(nearest) <= pow(0.22 + world_radius, 2): return true
	return false
