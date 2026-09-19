extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b,-1,"turbofit")
	m.reset({1:Vector3(-10,20,0),2:Vector3(10,20,0)})
	await step(m,{1:press(Vector2.RIGHT)})
	var first: Dictionary = m.projectile_telemetry()[0]
	b.position = first.position - Vector3.UP + Vector3(.9,0,0)
	b.runtime.velocity = a.runtime.velocity
	a.position.x = -30
	await step(m,{2:press(Vector2.DOWN)})
	check(m.projectile_telemetry().size() == 1, "Orb reflects before wave collision")
	if not m.projectile_telemetry().is_empty():
		var reflected: Dictionary = m.projectile_telemetry()[0]
		check(reflected.source == 2 and reflected.facing == -1, "Orb transfers current wave owner and reverses direction")
		check(reflected.age > first.age and reflected.distance > first.distance, "reflection preserves finite budgets")
		m.expire_source(1,"stock lifecycle")
		check(m.projectile_telemetry().size() == 1, "old owner reset preserves reflected projectile")
		m.expire_source(2,"stock lifecycle")
		check(m.projectile_telemetry().is_empty(), "new owner reset removes reflected projectile")
	m.configure_actor_kit(2,"teknium")
	m.reset({1:Vector3(-10,20,0),2:Vector3(10,20,0)})
	await step(m,{2:press(Vector2.LEFT)})
	for i in 30:
		if not m.projectiles.is_empty(): break
		await step(m)
	check(not m.projectiles.is_empty(), "real Teknium Force emitted")
	if not m.projectiles.is_empty():
		var shot: Dictionary = m.projectiles[0]
		a.position = shot.position - Vector3.UP + Vector3(-.6,0,0)
		a.runtime.velocity = b.runtime.velocity
		b.position.x = 30
		await step(m,{1:press(Vector2.DOWN)})
		check(not m.projectiles.is_empty() and m.projectiles[0].source == 1 and m.projectiles[0].facing == 1, "Turbofit Orb reflects Teknium Force across kits")
	a.free(); b.free()
	if not failures: print("PASS: turbo match reflection (%d checks)" % checks)
	quit(1 if failures else 0)
