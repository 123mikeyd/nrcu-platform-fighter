extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var p = load("res://scripts/core/combat/defense_profile.gd").new()
	if p.get("ground_startup_ticks") == null:
		check(false, "finite dodge windows exist")
		quit(1)
		return
	p.ground_startup_ticks = 2
	p.ground_invulnerable_ticks = 2
	p.ground_recovery_ticks = 2
	p.air_startup_ticks = 2
	p.air_invulnerable_ticks = 2
	p.air_recovery_ticks = 2
	p.dodge_cooldown_ticks = 3
	p.dodge_shield_cost = 10.0
	var Policy = load("res://scripts/core/combat/defense_policy.gd")
	for grounded in [true, false]:
		var d = Policy.new(p)
		var out = d.advance({"grounded": grounded, "dodge_requested": true, "dodge_direction": Vector2(3, 4)})
		check(out.state == "dodge_startup" and out.damage_eligible and out.grab_eligible, "startup first vulnerable")
		check(out.shield_health == 90.0, "cost exactly once")
		check(out.motion_velocity == Vector2.ZERO, "no startup motion")
		check(d.advance({"grounded": grounded}).state == "dodge_startup", "startup last endpoint")
		out = d.advance({"grounded": grounded})
		check(out.state == "dodge_invulnerable" and not out.damage_eligible and not out.grab_eligible, "active first filters")
		check(out.motion_velocity.length() > 0.0, "active returns motion intent")
		check(d.advance({"grounded": grounded}).state == "dodge_invulnerable", "active last endpoint")
		out = d.advance({"grounded": grounded})
		check(out.state == "dodge_recovery" and out.damage_eligible and out.grab_eligible and out.motion_velocity == Vector2.ZERO, "recovery first vulnerable")
		check(d.advance({"grounded": grounded}).state == "dodge_recovery", "recovery last endpoint")
		check(d.advance({"grounded": grounded}).state == "idle", "episode finite endpoint")
		check(d.advance({"grounded": grounded, "dodge_requested": true}).state == "idle", "cooldown rejects repeat")
		for i in range(3): d.advance({"grounded": grounded})
		out = d.advance({"grounded": grounded, "dodge_requested": true})
		check(out.state == ("dodge_startup" if grounded else "idle"), "ground reusable but air exhausted")
		if not grounded:
			check(d.advance({"grounded": false, "head_contact": true}).air_charges == 0, "head contact not a landing")
			check(d.advance({"grounded": true}).air_charges == 1, "real landing restores air resource")
			check(d.advance({"grounded": false, "dodge_requested": true}).state == "dodge_startup", "new flight can dodge")
	var poor = Policy.new(p)
	poor.shield_health = 9.0
	check(poor.advance({"dodge_requested": true}).state == "idle", "insufficient shield resource rejects dodge")
	var edge = Policy.new(p)
	edge.shield_health = 10.0
	check(edge.advance({"dodge_requested": true}).state == "dodge_startup", "exact cost admits without shield break")
	if failures == 0: print("PASS: core defense dodge (%d checks)" % checks)
	quit(1 if failures else 0)
