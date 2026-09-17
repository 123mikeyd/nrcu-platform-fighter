extends RefCounted
## Pure fixed-60Hz policy. No Input, Node, wall clock, or render dependencies.
const Profile = preload("res://scripts/core/fighter/movement_profile.gd")
const Coordinator = preload("res://scripts/core/fighter/state_coordinator.gd")
const DT: float = 1.0 / 60.0
var _tuning: Resource
var states = Coordinator.new()
var velocity := Vector3.ZERO
var grounded: bool = false
var tick: int = 0
var _dash_left: int = 0
var air_jumps_left: int = 0
var _startup_left: int = 0
var _short_requested: bool = false
var _landing_left: int = 0
var _fast_fall: bool = false
var hitstun_left: int = 0
var _combat_layers_pending: bool = false
var recovery_spent: bool = false
var recovery_motion: bool = false
func _init(definition: Resource = null) -> void:
	_tuning = (definition if definition != null else Profile.new()).duplicate(true)
func reset(on_ground: bool = false) -> void:
	states.reset()
	recovery_spent = false
	recovery_motion = false
	hitstun_left = 0
	_combat_layers_pending = false
	velocity = Vector3.ZERO
	grounded = on_ground
	tick = 0
	_dash_left = 0
	_startup_left = 0
	_short_requested = false
	_landing_left = 0
	_fast_fall = false
	air_jumps_left = _tuning.air_jumps
	if not grounded: states.transition("locomotion", "falling", "air reset")
func reconcile_status(enabled: bool, frozen: bool, caught: bool) -> void:
	# Match owns constraints; runtime owns remaining stun and landing recovery.
	var status := "disabled" if not enabled else "frozen" if frozen else "caught" if caught else "hitstun" if hitstun_left > 0 else "normal"
	states.transition("status", status, "effective status")
	if status != "normal": return
	if _combat_layers_pending:
		_combat_layers_pending = false
		states.transition("action", "neutral", "deferred combat interruption")
		states.transition("locomotion", "falling", "deferred combat interruption")
		if grounded: states.transition("locomotion", "landing", "deferred combat contact")
	if _landing_left > 0:
		states.transition("action", "landing_lock", "deferred landing recovery")
func can_accept_jump() -> bool:
	return not recovery_spent and states.movement_allowed() and _startup_left == 0 and states.locomotion != "jump_startup" and (grounded or air_jumps_left > 0)
func reconcile_contact(on_ground: bool, body_velocity: Vector3) -> void:
	velocity = body_velocity
	if states.status == "caught": return
	# An upward takeoff can still report the previous support; it is not landing.
	if recovery_spent and velocity.y > 0: on_ground = false
	if on_ground and velocity.y <= 0:
		recovery_spent = false
		recovery_motion = false
	if on_ground and not grounded:
		air_jumps_left = _tuning.air_jumps
		_fast_fall = false
		_startup_left = 0
		_landing_left = maxi(0, _tuning.landing_ticks)
		states.transition("locomotion", "landing", "terrain landing")
		states.transition("action", "landing_lock" if _landing_left > 0 else "neutral", "terrain landing")
	if grounded and not on_ground:
		_startup_left = 0
		_landing_left = 0
		states.transition("action", "neutral", "support lost")
		states.transition("locomotion", "falling", "walkoff consumes ground opportunity")
	grounded = on_ground
	if not grounded and velocity.y <= 0 and states.locomotion == "rising":
		states.transition("locomotion", "falling", "upward motion blocked")
func cancel_for_grab() -> void:
	cancel_recovery_motion()
	_startup_left = 0; _landing_left = 0; _fast_fall = false; _short_requested = false; _dash_left = 0
	hitstun_left = 0; velocity = Vector3.ZERO
	_combat_layers_pending = false
	states.transition("status", "normal", "capture interruption")
	states.transition("action", "neutral", "capture interruption")
	states.transition("locomotion", "falling", "capture interruption")
	if grounded: states.transition("locomotion", "landing", "capture retains support")
	states.transition("status", "caught", "capture")
func cancel_for_freeze() -> void:
	cancel_recovery_motion()
	_startup_left = 0; _landing_left = 0; _fast_fall = false; _short_requested = false; _dash_left = 0
	hitstun_left = 0
	_combat_layers_pending = true
	velocity.x = 0
	velocity.y = minf(velocity.y,0)
func cancel_recovery_motion() -> void:
	# Release motion ownership, never refund resources or write velocity.
	recovery_motion = false
func apply_combat_launch(launch: Vector3, stun_ticks: int) -> void:
	cancel_recovery_motion()
	_startup_left = 0
	_landing_left = 0
	_fast_fall = false
	_short_requested = false
	# Never open a normal-status window beneath an external constraint.
	_combat_layers_pending = states.status in ["frozen", "disabled"]
	if not _combat_layers_pending:
		states.transition("status", "normal", "combat interruption")
		states.transition("action", "neutral", "combat interruption")
		states.transition("locomotion", "falling", "combat interruption")
	velocity = launch
	grounded = false
	hitstun_left = maxi(1, stun_ticks)
	if not _combat_layers_pending: states.transition("status", "hitstun", "damage launch")
func step(commands: Dictionary) -> void:
	tick += 1
	if states.status == "caught":
		velocity = commands.get("restrained_velocity", Vector3.ZERO)
		return
	if hitstun_left > 0:
		hitstun_left -= 1
		velocity.y = maxf(velocity.y - _tuning.gravity * DT, -_tuning.fall_speed)
		if states.status == "frozen": velocity.x = 0
		if hitstun_left == 0 and states.status == "hitstun":
			reconcile_status(true, false, false)
			states.transition("locomotion", "landing" if grounded else "falling", "hitstun complete")
		return
	if states.status == "frozen":
		# Freeze gates intent, not gravity or the stun clock above. Landing
		# recovery stays deferred until status actually permits action.
		velocity.x = 0
		if not grounded: velocity.y = maxf(velocity.y - _tuning.gravity * DT, -_tuning.fall_speed)
		return
	if commands.get("ledge_hold", false):
		velocity = Vector3.ZERO
		return
	if states.locomotion == "jump_startup":
		_short_requested = _short_requested or commands.get("jump_released", false) or not commands.get("jump_held", false)
	if _landing_left > 0:
		_landing_left -= 1
		velocity.x = 0
		if _landing_left == 0: states.transition("action", "neutral", "landing complete")
		return
	if commands.has("defense_velocity"):
		states.transition("action", "movement_lock", "defense motion")
		velocity = commands.defense_velocity
		return
	states.transition("action", "movement_lock" if commands.get("shield", false) else "neutral", "command lock")
	var axis: float = clampf(float(commands.get("move_x", 0.0)), -1.0, 1.0)
	if not states.movement_allowed():
		velocity.x = 0
		if not grounded: velocity.y = maxf(velocity.y - _tuning.gravity * DT, -_tuning.fall_speed)
		return
	if commands.get("recovery_launch", false) and not recovery_spent:
		recovery_spent = true
		recovery_motion = true
		air_jumps_left = 0
		_startup_left = 0
		_short_requested = false
		_fast_fall = false
		grounded = false
		velocity.y = 13.5
		states.transition("locomotion", "falling", "recovery takeoff")
		states.transition("locomotion", "rising", "recovery launch")
		return
	var launched := false
	if commands.get("jump", false) and can_accept_jump():
		_short_requested = not commands.get("jump_held", false) or commands.get("jump_released", false)
		if grounded:
			_startup_left = maxi(1, _tuning.jump_startup_ticks)
			states.transition("locomotion", "jump_startup", "accepted ground jump")
		else:
			air_jumps_left -= 1
			_fast_fall = false
			velocity.y = _tuning.air_jump_speed
			states.transition("locomotion", "rising", "accepted air jump")
			launched = true
	elif states.locomotion == "jump_startup":
		_short_requested = _short_requested or commands.get("jump_released", false) or not commands.get("jump_held", false)
		_startup_left -= 1
		if _startup_left <= 0:
			velocity.y = _tuning.short_jump_speed if _short_requested else _tuning.full_jump_speed
			grounded = false
			states.transition("locomotion", "rising", "short hop" if _short_requested else "full hop")
			launched = true
	if not grounded:
		velocity.x = move_toward(velocity.x, axis * _tuning.air_speed, _tuning.air_acceleration * DT)
		if not launched:
			if not recovery_motion and commands.get("jump_released", false) and velocity.y > _tuning.short_jump_speed:
				velocity.y = _tuning.short_jump_speed
			velocity.y -= _tuning.gravity * DT
		if commands.get("down", false) and velocity.y <= 0: _fast_fall = true
		if _fast_fall: velocity.y = -_tuning.fast_fall_speed
		else: velocity.y = maxf(velocity.y, -_tuning.fall_speed)
		states.transition("locomotion", "fast_fall" if _fast_fall else "rising" if velocity.y > 0 else "falling", "vertical motion")
		return
	if states.locomotion == "jump_startup": return
	var was_still: bool = is_zero_approx(velocity.x)
	var turning: bool = axis * velocity.x < 0
	if was_still and absf(axis) >= _tuning.run_threshold: _dash_left = _tuning.initial_dash_ticks
	var accel: float = _tuning.turn_acceleration if turning else _tuning.initial_dash_acceleration if _dash_left > 0 and absf(axis) >= _tuning.run_threshold else _tuning.ground_acceleration
	if is_zero_approx(axis): accel = _tuning.ground_friction
	velocity.x = move_toward(velocity.x, axis * _tuning.run_speed, accel * DT)
	var state := "idle"
	if turning: state = "turn"
	elif is_zero_approx(axis): state = "idle" if is_zero_approx(velocity.x) else "brake"
	elif absf(axis) < _tuning.run_threshold: state = "walk"
	elif _dash_left > 0: state = "initial_dash"
	else: state = "run"
	states.transition("locomotion", state, "ground intent")
	_dash_left = maxi(0, _dash_left - 1)
