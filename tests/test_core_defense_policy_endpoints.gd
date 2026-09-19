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
	var Policy = load("res://scripts/core/combat/defense_policy.gd")
	var p = load("res://scripts/core/combat/defense_profile.gd").new()
	p.ground_startup_ticks = 1
	var d = Policy.new(p)
	d.advance({"dodge_requested": true, "dodge_direction": Vector2.RIGHT})
	d.advance({})
	var out = d.advance({"grounded": false})
	check(out.state == "dodge_recovery" and out.damage_eligible and out.motion_velocity == Vector2.ZERO, "walking off edge cancels ground invulnerability")
	p.shield_max = 10.0
	p.shield_drain = 1.0
	p.shield_hit_base = 2.0
	p.shield_hit_scale = 0.5
	d = Policy.new(p)
	d.advance({"shield_held": true})
	check(d.on_shield_hit(4.0).shield_health == 5.0, "configured base plus scale uses source damage without changing it")
	check(d.on_shield_hit(6.0).state == "break", "exact shield zero breaks")
	d.reset()
	for i in range(9): check(d.advance({"shield_held": true}).state == "shield", "held finite before drain endpoint")
	check(d.advance({"shield_held": true}).state == "break", "held drain exact endpoint")
	d.reset()
	check(d.on_shield_hit(500.0).shield_health == 10.0, "hit cost applies only to admitted shield contacts")
	d.advance({"shield_held": true})
	check(d.advance({"grounded": false, "shield_held": true}).damage_eligible, "shield cannot persist in air")
	p.ground_startup_ticks = 0
	p.ground_invulnerable_ticks = 0
	p.ground_recovery_ticks = 0
	p.dodge_cooldown_ticks = 0
	p.dodge_shield_cost = 0
	d = Policy.new(p)
	for i in range(30):
		out = d.advance({"dodge_requested": true})
		if out.state == "dodge_invulnerable":
			check(d.advance({"dodge_requested": true}).damage_eligible, "even zero tuning cannot chain permanent invulnerability")
	if failures == 0: print("PASS: core defense endpoints (%d checks)" % checks)
	quit(1 if failures else 0)
