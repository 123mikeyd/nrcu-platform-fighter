extends "res://tests/test_core_defense_match.gd"
func special(axis: Vector2):
	var f = Frame.new(); f.axis = axis; f.pressed.special = true; return f
func run():
	var floor = floor_body(); var p = DefenseProfile.new(); p.shield_drain = 0; p.shield_regen = 0
	var m = setup_match(p); m.configure_actor_kit(1,"turbofit")
	await settle(m)
	await tick(m,{1:frame(true,1),2:shield(true)})
	for i in 16: await tick(m,{2:shield()})
	check(m.fighters[2].percent == 0 and m.defense_telemetry(2).shield_health == 84, "timed guitar shield consumes full 14+2")
	m.reset({1:Vector3(0,.01,0),2:Vector3(3,.01,0)})
	await settle(m)
	await tick(m,{1:special(Vector2.RIGHT),2:shield(true)})
	for i in 20: await tick(m,{2:shield()})
	check(m.fighters[2].percent == 0, "finite shield absorbs wave")
	check(m.defense_telemetry(2).shield_health == 87, "wave absorption consumes finite shield budget 11+2")
	check(m.projectile_telemetry().is_empty(), "shield consumes projectile once")
	check(m.has_method("set_projectile_absorbing"), "host validates explicit absorption intent")
	if m.has_method("set_projectile_absorbing"):
		m.reset({1:Vector3(0,.01,0),2:Vector3(3,.01,0)})
		await settle(m); m.set_projectile_absorbing(2,true)
		await tick(m,{1:special(Vector2.RIGHT)})
		var absorbed := false
		for i in 20:
			await tick(m)
			for event in m.ability_events:
				if event.kind == "absorb": absorbed = event.payload_damage == 11
		check(absorbed and m.fighters[2].percent == 0, "validated absorption emits atomic payload without hit")
		check(m.fighters[2].absorbed_damage == 11, "match records absorbed payload once")
	cleanup(m); floor.free()
	if not failures: print("PASS: turbo match defense (%d checks)" % checks)
	quit(1 if failures else 0)
