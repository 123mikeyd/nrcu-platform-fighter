extends RefCounted
const Profile = preload("res://scripts/core/combat/defense_profile.gd")
var profile: Resource
var state := "idle"
var shield_health: float
var remaining := 0
var regen_wait := 0
var cooldown := 0
var air_charges := 0
var grounded := true
var dodge_air := false
var direction := Vector2.ZERO
func _init(settings: Resource = null) -> void:
	profile = settings.duplicate(true) if settings != null else Profile.new()
	shield_health = maxf(0.001, profile.shield_max)
	air_charges = maxi(0, profile.air_dodges_per_flight)
func snapshot() -> Dictionary:
	var invulnerable := state == "dodge_invulnerable"
	var speed: float = profile.air_dodge_speed if dodge_air else profile.ground_dodge_speed
	return {"delegate_legacy": profile.policy_id == "legacy", "state": state, "shield_health": shield_health, "remaining_ticks": remaining,
		"regen_wait_ticks": regen_wait, "cooldown_ticks": cooldown, "air_charges": air_charges,
		"grounded": grounded, "dodge_air": dodge_air,
		"damage_eligible": state != "shield" and not invulnerable, "grab_eligible": not invulnerable,
		"motion_velocity": direction * maxf(0.0, speed) if invulnerable else Vector2.ZERO,
		"action_locked": state != "idle"}
func advance(intent: Dictionary = {}) -> Dictionary:
	if profile.policy_id == "legacy" or intent.get("paused", false) or intent.get("hitstop", false) or intent.get("uncommitted", false):
		return snapshot()
	if intent.get("disabled", false) or intent.get("frozen", false):
		return interrupt("disabled" if intent.get("disabled", false) else "frozen")
	var next_grounded: bool = intent.get("grounded", grounded)
	if next_grounded and not grounded:
		air_charges = maxi(0, profile.air_dodges_per_flight)
		if dodge_air and state in ["dodge_startup", "dodge_invulnerable"]:
			grounded = true
			state = "dodge_recovery"
			remaining = maxi(1, profile.air_recovery_ticks)
			return snapshot()
	if grounded and not next_grounded and not dodge_air and state in ["dodge_startup", "dodge_invulnerable"]:
		grounded = false
		state = "dodge_recovery"
		remaining = maxi(1, profile.ground_recovery_ticks)
		return snapshot()
	grounded = next_grounded
	if cooldown > 0: cooldown -= 1
	if state == "break":
		remaining -= 1
		if remaining <= 0:
			state = "idle"
			shield_health = maxf(0.001, profile.shield_max) * clampf(profile.break_restore_fraction, 0.0, 1.0)
		return snapshot()
	if state.begins_with("dodge_"):
		remaining -= 1
		if remaining <= 0:
			if state == "dodge_startup":
				state = "dodge_invulnerable"
				remaining = maxi(1, profile.air_invulnerable_ticks if dodge_air else profile.ground_invulnerable_ticks)
			elif state == "dodge_invulnerable":
				state = "dodge_recovery"
				remaining = maxi(1, profile.air_recovery_ticks if dodge_air else profile.ground_recovery_ticks)
			else:
				state = "idle"
				direction = Vector2.ZERO
				cooldown = maxi(1, profile.dodge_cooldown_ticks)
		return snapshot()
	if intent.get("dodge_requested", false) and cooldown == 0 and shield_health >= maxf(0.0, profile.dodge_shield_cost) and (grounded or air_charges > 0):
		state = "dodge_startup"
		dodge_air = not grounded
		direction = intent.get("dodge_direction", Vector2.ZERO).limit_length(1.0)
		if grounded: direction = Vector2(signf(direction.x), 0.0)
		if dodge_air: air_charges -= 1
		shield_health -= maxf(0.0, profile.dodge_shield_cost)
		regen_wait = maxi(0, profile.regen_delay_ticks)
		remaining = maxi(1, profile.air_startup_ticks if dodge_air else profile.ground_startup_ticks)
		return snapshot()
	state = "shield" if intent.get("shield_held", false) and grounded else "idle"
	if state == "shield":
		_spend_shield(maxf(0.0, profile.shield_drain))
	elif regen_wait > 0:
		regen_wait -= 1
	else:
		shield_health = minf(maxf(0.001, profile.shield_max), shield_health + maxf(0.0, profile.shield_regen))
	return snapshot()
func on_shield_hit(damage: float) -> Dictionary:
	if state == "shield":
		_spend_shield(maxf(0.0, profile.shield_hit_base) + maxf(0.0, damage) * maxf(0.0, profile.shield_hit_scale))
	return snapshot()
func interrupt(_reason: String = "hit") -> Dictionary:
	if state.begins_with("dodge_"):
		cooldown = maxi(cooldown, maxi(1, profile.dodge_cooldown_ticks))
	if state != "break":
		state = "idle"
		remaining = 0
	direction = Vector2.ZERO
	dodge_air = false
	return snapshot()
func reset(on_ground: bool = true) -> Dictionary:
	state = "idle"
	remaining = 0
	regen_wait = 0
	cooldown = 0
	grounded = on_ground
	dodge_air = false
	direction = Vector2.ZERO
	shield_health = maxf(0.001, profile.shield_max)
	air_charges = maxi(0, profile.air_dodges_per_flight)
	return snapshot()
func _spend_shield(cost: float) -> void:
	regen_wait = maxi(0, profile.regen_delay_ticks)
	shield_health = maxf(0.0, shield_health - cost)
	if shield_health <= 0.0:
		state = "break"
		remaining = maxi(1, profile.break_ticks)
