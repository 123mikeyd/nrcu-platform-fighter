extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	check(m.kit_registry.contains("ice_mage"), "Ice Mage registered only with functional host")
	if not m.kit_registry.contains("ice_mage"):
		a.free(); b.free(); quit(1); return
	m.register_actor(1,a,-1,"ice_mage"); m.register_actor(2,b)
	m.reset({1:Vector3(0,20,0),2:Vector3(10,20,0)})
	await step(m,{1:press(Vector2.RIGHT)})
	check(m.fighters[1].buffer.peek("special").is_empty(), "cast accepted and consumed")
	for i in 10: await step(m)
	check(m.projectile_telemetry().is_empty(), "no bolt before .2 event")
	await step(m)
	check(m.projectile_telemetry().size() == 1, "generic spawn_projectile emits at .2")
	check(not m.ability_events.is_empty() and m.ability_events[0].get("generation",-1) == m.generation and m.ability_events[0].tick == m.tick-1, "generic spawn carries host generation and contact tick")
	if not m.projectile_telemetry().is_empty():
		var shot = m.projectile_telemetry()[0]
		check(shot.kind == "frost_bolt", "not Force or Wave substitution")
		check(is_equal_approx(shot.position.y,a.position.y+1.5), "post movement authored origin")
		check(is_equal_approx(shot.age,1.0/60), "world advance once on spawn")
	m.set_frozen(1,true)
	for i in 3: await step(m)
	check(not m.projectile_telemetry().is_empty(), "emitted bolt survives attached freeze")
	m.set_enabled(1,false)
	check(m.projectile_telemetry().is_empty(), "disable expires current owned bolt")
	a.free(); b.free()
	if not failures: print("PASS: ice match cast (%d checks)" % checks)
	quit(1 if failures else 0)
