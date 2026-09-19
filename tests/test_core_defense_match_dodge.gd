extends "res://tests/test_core_defense_match.gd"
func run() -> void:
	var floor = floor_body(); var p = DefenseProfile.new()
	p.ground_startup_ticks = 1; p.ground_invulnerable_ticks = 2; p.ground_recovery_ticks = 2
	var m = setup_match(p); await settle(m)
	await tick(m, {2: shield(true, Vector2.LEFT)})
	check(m.defense_telemetry(2).state == "dodge_startup", "fresh shield direction enters vulnerable startup")
	check(m.fighters[2].buffer.peek("shield").is_empty(), "accepted dodge consumes edge")
	var x = m.fighters[2].actor.position.x
	await tick(m, {1: frame(true, 1), 2: shield(false, Vector2.RIGHT)})
	check(m.defense_telemetry(2).state == "dodge_invulnerable", "startup transitions on committed tick")
	check(m.fighters[2].percent == 0, "active dodge filters real strike")
	check(is_equal_approx(m.fighters[2].actor.position.x, x - 10.0/60), "latched velocity drives real collision mover")
	x = m.fighters[2].actor.position.x
	await tick(m, {2: shield(false, Vector2.RIGHT)})
	check(is_equal_approx(m.fighters[2].actor.position.x, x - 10.0/60), "persistent dodge direction ignores steering")
	await tick(m)
	check(m.defense_telemetry(2).state == "dodge_recovery", "finite vulnerable recovery")
	m.fighters[1].ready_tick = 0
	await tick(m, {1: frame(true, 1)})
	check(m.fighters[2].percent > 0, "recovery takes real hit")
	check(m.defense_telemetry(2).state == "idle", "incoming launch interrupts episode")
	check(m.defense_telemetry(2).shield_health < 100, "interrupt never refunds dodge cost")
	cleanup(m); floor.free()
	if not failures: print("PASS: core defense match dodge (%d checks)" % checks)
	quit(1 if failures else 0)
