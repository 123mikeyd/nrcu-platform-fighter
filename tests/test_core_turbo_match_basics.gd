extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	check(m.has_method("configure_actor_kit"), "match exposes per-actor kit selection")
	if not m.has_method("configure_actor_kit"):
		a.free(); b.free(); quit(1); return
	m.register_actor(1, a); m.register_actor(2, b)
	check(m.configure_actor_kit(1, "turbofit"), "registered Turbofit factory")
	m.reset({1: Vector3(0,20,0), 2: Vector3(1.5,20,0)})
	await step(m, {1: press(Vector2.ZERO, "attack")})
	check(m.fighters[2].percent == 0, "Turbofit windup is not Teknium instant hit")
	check(m.kit_telemetry(1).basic.clip == "AirSideKick", "air route committed")
	m.reset({1: Vector3(0,20,0), 2: Vector3(0,21.5,0)})
	await step(m, {1: press(Vector2.UP, "attack")})
	for i in 16: await step(m)
	check(m.fighters[2].percent == 14, "timed upward guitar uses 14 damage through shared resolver")
	check(m.kit_telemetry(1).basic.phase == "active", "committed crossing phase")
	check(m.fighters[1].grab == null and m.fighters[1].force == null, "no fallback abilities")
	a.free(); b.free()
	if not failures: print("PASS: turbo match basics (%d checks)" % checks)
	quit(1 if failures else 0)
