extends "res://tests/test_core_defense_match.gd"
func run() -> void:
	var floor = floor_body(); var p = DefenseProfile.new(); p.shield_drain = 0
	for dodge in [false, true]:
		var m = setup_match(p); await settle(m)
		m.fighters[2].actor.position.x = 1
		var grab = Frame.new(); grab.pressed.special = true
		await tick(m, {1: grab, 2: shield(true)})
		for i in 7: await tick(m, {2: shield()})
		await tick(m, {2: shield(dodge, Vector2(0, 1) if dodge else Vector2.ZERO)})
		for i in 3: await tick(m, {2: shield()})
		check(m.fighters[2].caught_by == (0 if dodge else 1), "finite dodge excludes grab; finite shield explicitly permits grab")
		if not dodge:
			check(m.defense_telemetry(2).state == "idle", "capture interrupts shield")
			await tick(m, {2: shield(true, Vector2.LEFT)})
			check(m.fighters[2].buffer.peek("shield").is_empty() and m.defense_telemetry(2).state == "idle", "caught edges drain without escape")
		cleanup(m)
	floor.free()
	if not failures: print("PASS: core defense match grab (%d checks)" % checks)
	quit(1 if failures else 0)
