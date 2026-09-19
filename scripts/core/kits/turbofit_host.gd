extends RefCounted
## Value-only per-actor adapter; match owns movement, eligibility and resolution.
var basic = preload("res://scripts/core/kits/turbofit_kit.gd").new()
var special = preload("res://scripts/core/kits/turbofit_specials.gd").new()
var interrupted_cooldown := 0.0
var _basic_started := false
func braking() -> bool:
	return special.phase == "anticipation"
func locked() -> bool:
	return basic.snapshot().active or special.phase != "idle" or special.cooldown > .000001 or interrupted_cooldown > .000001
func start_basic(id: String, aim: Vector2, airborne: bool, facing: float) -> bool:
	if locked() or not basic.start(id, aim, airborne, facing): return false
	_basic_started = true
	return true
func start_special(id: String, aim: Vector2, facing: float, recovery_available: bool) -> bool:
	if locked() or (aim.y < -.1 and not recovery_available): return false
	return special.start(id, aim, facing)
func initial_requests(source: int, origin: Vector3) -> Array:
	return special.collect(source, origin, [])
func prepare(held: bool) -> void:
	# Legacy attack cooldown advances before acceptance. Charge entry itself is
	# not a held interval. Orb age alone must wait for the post-move query.
	interrupted_cooldown = maxf(0, interrupted_cooldown - 1.0 / 60.0)
	basic.tick(1.0 / 60.0)
	if special.move == "sound_orb":
		special.cooldown = maxf(0, special.cooldown - 1.0 / 60.0)
		if special.cooldown <= .000001: special.cancel()
	else: special.tick(1.0 / 60.0, {"held": held})
func advance(_held: bool) -> void:
	# Newly accepted basics advance their source windup in the acceptance tick.
	if _basic_started: basic.tick(1.0 / 60.0)
	_basic_started = false
func landed(grounded: bool) -> void:
	basic.tick(0, {"grounded": grounded})
func collect(source: int, origin: Vector3, targets: Array, projectiles: Array = []) -> Array:
	var contacts: Array = basic.contacts(source, origin, targets) + special.collect(source, origin, targets, projectiles)
	if special.move == "sound_orb":
		var cooldown: float = special.cooldown
		special.tick(1.0 / 60.0)
		# Cooldown already advanced before acceptance; query-before-decrement is
		# the independent Orb active clock, not a second attack cooldown tick.
		special.cooldown = cooldown
	return contacts
func cancel(reset: bool = false) -> void:
	interrupted_cooldown = 0.0 if reset else maxf(interrupted_cooldown, basic.snapshot().remaining)
	basic.cancel()
	_basic_started = false
	special.cancel(reset)
func cancel_for_status(status: String) -> void:
	# Source apply_freeze clears the attack budget; ordinary hits retain it.
	# Detached projectiles are owned by match, not this adapter.
	cancel(status == "frozen")
func snapshot() -> Dictionary:
	return {"kit_id": "turbofit", "basic": basic.snapshot(), "special": special.snapshot(),
		"presentation": special.snapshot() if special.phase != "idle" else basic.snapshot().presentation,
		"action_locked": locked(), "interrupted_cooldown": interrupted_cooldown}
