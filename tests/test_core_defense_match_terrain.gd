extends "res://tests/test_core_defense_match.gd"
func run() -> void:
	var p = DefenseProfile.new(); p.air_startup_ticks = 1; p.air_invulnerable_ticks = 10
	var m = setup_match(p)
	m.fighters[1].actor.reset_at(Vector3(0, 6, 0)); m.fighters[2].actor.reset_at(Vector3(5, 6, 0))
	await tick(m, {2: shield(true)})
	check(m.defense_telemetry(2).state == "dodge_startup" and m.defense_telemetry(2).air_charges == 0, "neutral airborne shield edge spends air dodge")
	await tick(m)
	check(m.defense_telemetry(2).state == "dodge_invulnerable" and m.fighters[2].actor.velocity == Vector3.ZERO, "neutral air dodge has zero authored velocity")
	m.cancel_action(2, "interrupt")
	for i in 25: await tick(m, {2: shield()})
	check(m.defense_telemetry(2).state == "idle" and m.defense_telemetry(2).air_charges == 0, "held shield cannot repeat or refund airborne charge")
	cleanup(m)
	var floor = floor_body()
	m = setup_match(p); await settle(m)
	m.fighters[2].actor.reset_at(Vector3(1.5, 0.05, 0))
	await tick(m, {2: shield(true, Vector2.DOWN)})
	await tick(m)
	check(m.fighters[2].actor.runtime.grounded, "air dodge collides with real terrain")
	check(m.defense_telemetry(2).state == "dodge_recovery" and m.defense_telemetry(2).air_charges == 1, "landing ends invulnerability and refreshes charge before contacts")
	m.reset({1: Vector3(0,0.01,0),2: Vector3(19.9,0.01,0)})
	await settle(m)
	m.fighters[2].defense.profile.ground_startup_ticks = 1
	await tick(m, {2: shield(true, Vector2.RIGHT)})
	var observed_support_loss := false
	for i in 8:
		await tick(m)
		if not m.fighters[2].actor.runtime.grounded:
			observed_support_loss = true
			check(m.defense_telemetry(2).state == "dodge_recovery", "real support loss cancels ground dodge before contacts")
			break
	check(observed_support_loss, "fixture actually leaves terrain support")
	cleanup(m); floor.free()
	# Another fighter's head is not authoritative terrain floor.
	m = setup_match(p)
	m.fighters[1].actor.reset_at(Vector3(0, 5, 0)); m.fighters[2].actor.reset_at(Vector3(0, 6.8, 0))
	m.fighters[2].defense.air_charges = 0; m.fighters[2].defense.grounded = false
	for i in 4: await tick(m)
	check(not m.fighters[2].actor.runtime.grounded and m.defense_telemetry(2).air_charges == 0, "fighter head never refreshes air defense")
	cleanup(m)
	if not failures: print("PASS: core defense match terrain (%d checks)" % checks)
	quit(1 if failures else 0)
