extends "res://tests/test_core_force_acceptance.gd"
func run():
	for after in [false, true]:
		var m = Match.new(); var bodies: Array = []
		for id in [1, 2, 3]:
			var a = Actor.new(); root.add_child(a); bodies.append(a); m.register_actor(id, a)
		var ground := StaticBody3D.new(); var cs := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(50, 1, 10); cs.shape = box; ground.add_child(cs); root.add_child(ground); ground.position.y = -0.5
		m.reset({1: Vector3.ZERO, 2: Vector3(-1, 0, 0), 3: Vector3(3, 0, 0)})
		for i in 10: await step(m)
		await step(m, {1: press()})
		for i in (14 if after else 4): await step(m)
		await step(m, {2: press(Vector2.RIGHT, "attack")})
		check(m.fighters[1].percent == 8 and m.fighters[1].force == null, "real strike cancels force phase")
		check(m.projectiles.size() == (1 if after else 0), "emitted object lifetime differs from canceled anticipation")
		for i in 20: await step(m)
		check(m.fighters[3].percent == (8 if after else 0), "emitted shot still damages after caster hit")
		for body in bodies: body.free()
		ground.free()
	if not failures: print("PASS: force real hit interruption")
	quit(1 if failures else 0)
