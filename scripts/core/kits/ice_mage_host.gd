extends RefCounted
## Per-actor adapter. A host must support spawn_projectile + ordered status intents.
const STEP := 1.0 / 60.0
const CAST_BUDGET := 1.6
var basic = preload("res://scripts/core/kits/ice_mage_kit.gd").new()
var cast_cooldown := 0.0
var interrupted_cooldown := 0.0
var _action_remaining := 0.0
var _move := ""
var _identity := ""
var _age := 0.0
var _facing := 1.0
var _new_basic := false
var _new_special := false
var _spawn_pending := false
var _recovery_pending := false
var _emitted := false
func locked() -> bool:
	return basic.snapshot().active or basic.snapshot().remaining > 0 or _action_remaining > 0 or interrupted_cooldown > 0
func braking() -> bool:
	return false
func start_basic(id: String, aim: Vector2, airborne: bool, facing: float) -> bool:
	if locked() or not basic.start(id,aim,airborne,facing): return false
	_new_basic = true
	return true
func start_special(id: String, aim: Vector2, facing: float, recovery_available: bool) -> bool:
	if id.is_empty() or locked(): return false
	var rise := aim.y < -.1
	if (rise and not recovery_available) or (not rise and cast_cooldown > 0): return false
	_identity = id
	_move = "frost_rise" if rise else "frost_bolt"
	_age = 0
	_facing = facing
	if not rise and absf(aim.x) > .1: _facing = signf(aim.x)
	_action_remaining = .65 if rise else .5
	if not rise: cast_cooldown = CAST_BUDGET
	_recovery_pending = rise
	_spawn_pending = false
	_emitted = false
	_new_special = true
	return true
func initial_requests(source: int, _origin: Vector3) -> Array:
	if not _recovery_pending: return []
	_recovery_pending = false
	return [{"kind":"recovery_request","source":source,"activation_id":_identity,"facing":_facing,"ability_script":"res://scripts/core/combat/recovery_ability.gd","vertical_speed":13.5,"active_seconds":.38,"cooldown_seconds":.65,"spend_recovery":true,"jumps_used":2}]
func prepare(_held: bool) -> void:
	cast_cooldown = maxf(0,cast_cooldown-STEP)
	interrupted_cooldown = maxf(0,interrupted_cooldown-STEP)
	_action_remaining = maxf(0,_action_remaining-STEP)
	basic.tick(STEP)
	_tick_special()
func advance(_held: bool) -> void:
	if _new_basic: basic.tick(STEP,false)
	if _new_special: _tick_special()
	_new_basic = false
	_new_special = false
func _tick_special() -> void:
	if _move.is_empty(): return
	_age += STEP
	if not _emitted and _age + .000001 >= .2:
		_emitted = true
		_spawn_pending = _move == "frost_bolt"
	if _action_remaining <= 0: _move = ""
func landed(_grounded: bool) -> void:
	pass # Source IceStrike is not a landing-cancelled foot attack.
func collect(source: int, origin: Vector3, targets: Array, _projectiles: Array = []) -> Array:
	var result: Array = basic.contacts(source,origin,targets)
	if _spawn_pending:
		_spawn_pending = false
		result.append({"kind":"spawn_projectile","projectile_kind":"frost_bolt","source":source,"activation_id":_identity,"position":origin+Vector3(_facing*.85,1.5,0),"facing":_facing})
	return result
func cancel(reset: bool = false) -> void:
	interrupted_cooldown = 0.0 if reset else maxf(interrupted_cooldown,maxf(basic.snapshot().remaining,_action_remaining))
	if reset: cast_cooldown = 0
	basic.cancel()
	_action_remaining = 0
	_move = ""
	_identity = ""
	_age = 0
	_new_basic = false
	_new_special = false
	_spawn_pending = false
	_recovery_pending = false
	_emitted = false
func cancel_for_status(status: String) -> void:
	# Source apply_freeze clears attack_cooldown; receive_hit does not.
	cancel()
	if status == "frozen": interrupted_cooldown = 0
func advance_inactive(delta: float = STEP) -> void:
	# Optional shared host hook after status cancellation, instead of prepare.
	# Omit during actor hitstop/global pause; never advance an attack episode.
	cast_cooldown = maxf(0,cast_cooldown-maxf(0,delta))
	interrupted_cooldown = maxf(0,interrupted_cooldown-maxf(0,delta))
func snapshot() -> Dictionary:
	var special := {"move":_move,"activation_id":_identity,"age":_age,"phase":"idle" if _move.is_empty() else ("windup" if _age < .2 else "recovery"),"facing":_facing,"cooldown":_action_remaining}
	var presentation: Dictionary = basic.snapshot().presentation
	if not _move.is_empty(): presentation = {"clip":"IceCast" if _age < .5 else "","elapsed":_age,"duration":.5,"facing":_facing,"activation_id":_identity}
	return {"kit_id":"ice_mage","basic":basic.snapshot(),"special":special,"presentation":presentation,"action_locked":locked(),"cast_cooldown":cast_cooldown,"interrupted_cooldown":interrupted_cooldown}
