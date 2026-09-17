extends "res://tests/test_core_force_acceptance.gd"
func run():
	for facing in [1.0, -1.0]:
		var m = Match.new(); var a = Actor.new(); var b = Actor.new()
		root.add_child(a); root.add_child(b)
		var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
		box.size = Vector3(100, 1, 10); shape.shape = box; floor_body.add_child(shape); root.add_child(floor_body); floor_body.position.y = -0.5
		m.register_actor(1, a); m.register_actor(2, b)
		m.reset({1: Vector3.ZERO, 2: Vector3(2.4 * facing, 0, 0)})
		for i in 10: await step(m)
		await step(m, {1: press(Vector2(facing, 0))})
		for i in 14: await step(m)
		check(m.projectiles.size() == 1 and m.fighters[2].percent == 0, "event spawns without immediate damage both facings")
		var shot: Dictionary = m.projectiles[0].duplicate()
		var samples = JSON.parse_string(FileAccess.get_file_as_string("res://assets/teknium/magic_source_samples.json"))
		for sample in samples.ForcePush:
			if sample.frame == 46:
				var p: Array = sample.hands.RightHand
				check(shot.position.distance_to(a.position + Vector3(p[0] * facing, p[1], p[2] * facing)) < 0.002, "actual emitted origin agrees with immutable source fixture both facings")
		await step(m)
		check(m.projectiles.size() == 1 and is_equal_approx(m.projectiles[0].position.x - shot.position.x, facing * 0.25), "first travel is following tick at speed15")
		check(is_equal_approx(absf(m.projectiles[0].position.z), absf(shot.position.z) - 0.1), "off-plane z approaches zero6")
		for i in 12: await step(m)
		check(m.fighters[2].percent == 8 and m.projectiles.is_empty(), "real capsule sweep consumes and damages once")
		check(m.fighters[1].percent == 0, "caster excluded")
		a.free(); b.free(); floor_body.free()
	if not failures: print("PASS: force real world contact")
	quit(1 if failures else 0)
