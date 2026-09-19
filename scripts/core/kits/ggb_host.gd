extends "res://scripts/core/kits/ggb_kit.gd"
## Existing adapter protocol plus explicit pre_move_requests terrain-motion seam.
var special_move := ""
var charging := false
var charge_time := 0.0
var age := 0.0
var drop_committed := false
var landing_lag := 0.0
var _initial := false
var _release := false
var _slam := false
var air = preload("res://scripts/core/kits/ggb_air.gd").new()
func start_basic(id: String, aim: Vector2, airborne: bool, input_facing: float) -> bool:
	if not super.start_basic(id,aim,airborne,input_facing): return false
	special_move = ""
	age = 0
	return true
func locked() -> bool:
	return super.locked() or charging or drop_committed or landing_lag > 0
func braking() -> bool:
	return charging or landing_lag > 0
func start_special(id: String, aim: Vector2, input_facing: float, recovery_available: bool) -> bool:
	if id.is_empty() or locked(): return false
	if aim.y < -.1 and (not recovery_available or air.recovery_spent): return false
	if absf(aim.y) <= .1 and absf(aim.x) <= .1 and aim != Vector2.ZERO: return false
	identity = id
	facing = input_facing
	age = 0
	move = ""
	if aim.y < -.1:
		special_move = "rising_strike"
		air.commit_recovery()
		cooldown = .65
		_initial = true
	elif aim.y > .1:
		special_move = "heavy_drop"
		drop_committed = true
	elif absf(aim.x) > .1:
		special_move = "sticky_goo"
		facing = signf(aim.x)
		cooldown = .55
		_initial = true
	else:
		special_move = "charge"
		charging = true
		charge_time = 0
	return true
func initial_requests(source: int, origin: Vector3) -> Array:
	if not _initial: return []
	_initial = false
	if special_move == "sticky_goo":
		return [{"kind":"spawn_projectile","projectile_kind":"sticky_goo","source":source,"activation_id":identity,"position":origin+Vector3(facing*.8,1,0),"facing":facing}]
	return [{"kind":"recovery_request","source":source,"activation_id":identity,"facing":facing,"vertical_speed":13.5,"active_seconds":.38,"cooldown_seconds":.65,"spend_recovery":true,"jumps_used":2}]
func prepare(held: bool) -> void:
	super.prepare(held)
	landing_lag = maxf(0,landing_lag-STEP)
	if not special_move.is_empty(): age += STEP
	if charging:
		# fighter.gd advances charge before testing released input, even on release.
		charge_time = minf(1.5,charge_time+STEP)
		if not held:
			charging = false
			_release = true
			cooldown = .7
			direction = Vector3(facing,0,0)
func advance(_held: bool) -> void:
	pass # All source GGB attacks are immediate; no authored animation windup.
func pre_move_requests(source: int) -> Array:
	if not drop_committed: return []
	return [{"kind":"motion_request","source":source,"activation_id":identity,"owner_token":identity,"mode":"velocity_override","velocity":Vector3(0,-24,0)}]
func landed(terrain_grounded: bool) -> void:
	air.landed(terrain_grounded)
	if not terrain_grounded or not drop_committed: return
	drop_committed = false
	_slam = true
	cooldown = .65
	landing_lag = .65
func collect(source: int, origin: Vector3, targets: Array, projectiles: Array = []) -> Array:
	var result: Array = super.collect(source,origin,targets,projectiles)
	if _release:
		_release = false
		var power := charge_time/1.5
		result.append_array(_cone(source,origin,targets,lerpf(10,26,power),lerpf(4,9,power),3))
	if _slam:
		_slam = false
		result.append({"kind":"presentation_event","event":"ggb_dust_impact","source":source,"activation_id":identity,"position":origin})
		var seen := {}
		var ordered := targets.duplicate()
		ordered.sort_custom(func(a: Dictionary,b: Dictionary): return a.id < b.id)
		for target in ordered:
			if target.id == source or seen.has(target.id) or not target.get("eligible",true): continue
			seen[target.id] = true
			if origin.distance_to(target.position) < 2.8:
				result.append(_hit(source,target.id,18,6,Vector3(signf(target.position.x-origin.x),.8,0)))
	return result
func cancel(reset: bool = false) -> void:
	super.cancel(reset)
	special_move = ""
	charging = false
	charge_time = 0
	age = 0
	drop_committed = false
	if reset:
		landing_lag = 0
		air.reset()
	_initial = false
	_release = false
	_slam = false
func cancel_for_status(status: String) -> void:
	cancel()
	if status == "frozen": cooldown = 0 # Neither freeze nor hit refunds air/landing lag.
func advance_inactive(delta: float = STEP) -> void:
	cooldown = maxf(0,cooldown-maxf(0,delta))
	landing_lag = maxf(0,landing_lag-maxf(0,delta))
func commit_jump(source: int, context: Dictionary) -> Dictionary:
	var committed := context.duplicate()
	committed.drop_committed = drop_committed
	committed.charging = charging
	committed.landing_lag = landing_lag
	return air.commit_jump(source,committed)
func motion_requests(source: int, delta: float, context: Dictionary) -> Array:
	for key in ["stopped","paused","frozen","caught","disabled","hitstun"]:
		if context.get(key,false): return []
	if drop_committed: return pre_move_requests(source)
	var request: Dictionary = air.float_request(source,delta,context)
	return [] if request.is_empty() else [request]
func snapshot() -> Dictionary:
	var value := super.snapshot()
	value.air = air.snapshot()
	value.special = {"move":special_move,"activation_id":identity,"age":age,"power":charge_time/1.5,"facing":facing,"cooldown":cooldown,"phase":"charge" if charging else ("drop" if drop_committed else "recovery")}
	value.presentation = {"clip":"","move":special_move if not special_move.is_empty() else move,"activation_id":identity,"elapsed":age,"facing":facing,"lead":drop_committed,"landing_lag":landing_lag}
	return value
