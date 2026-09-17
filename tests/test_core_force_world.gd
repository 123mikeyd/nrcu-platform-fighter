extends "res://tests/test_core_force_acceptance.gd"
func run():
	for scenario in ["closest", "team", "disabled", "terrain", "thin", "trade"]:
		var m = Match.new(); var bodies: Array = []
		for id in [3, 2, 1]:
			var a = Actor.new(); root.add_child(a); bodies.append(a)
			m.register_actor(id, a, 7 if scenario == "team" and id != 3 else -1)
		var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
		box.size = Vector3(100, 1, 10); shape.shape = box; floor_body.add_child(shape); root.add_child(floor_body); floor_body.position.y = -0.5
		m.reset({1: Vector3.ZERO, 2: Vector3(2 if scenario == "trade" else 3, 0, 0), 3: Vector3(4, 0, 0)})
		for i in 10: await step(m)
		if scenario == "disabled": m.set_enabled(2, false)
		if scenario == "thin":
			var capsule: CapsuleShape3D = m.fighters[2].actor.get_node("CoreCapsule").shape
			capsule.radius = 0.02
		var wall: StaticBody3D
		if scenario == "terrain":
			wall = StaticBody3D.new(); var ws := CollisionShape3D.new(); var wb := BoxShape3D.new()
			wb.size = Vector3(0.03, 4, 4); ws.shape = wb; wall.add_child(ws); root.add_child(wall); wall.position = Vector3(2, 1, 0)
		var frames := {1: press()}
		if scenario == "trade": frames[3] = press(Vector2.LEFT)
		await step(m, frames)
		for i in 14: await step(m)
		var samples = JSON.parse_string(FileAccess.get_file_as_string("res://assets/teknium/magic_source_samples.json"))
		var expected: Vector3
		for sample in samples.ForcePush:
			if sample.frame == 46:
				var p: Array = sample.hands.RightHand; expected = Vector3(p[0], p[1], p[2])
		check(m.projectiles[0].position.distance_to(m.fighters[1].actor.position + expected) < 0.002, "actual simulation spawn matches independent oracle")
		check(m.fighters[1].actor.runtime.grounded and absf(m.fighters[1].actor.position.x) < 0.001, "grounded magic holds real floor and horizontal lock")
		if scenario == "trade": check(m.projectiles.size() == 2 and m.projectiles[0].activation_id != m.projectiles[1].activation_id, "independent sources/activations")
		var payload_seen := false
		for i in 20:
			await step(m)
			for event in m.events:
				if event.source == 1:
					payload_seen = true
					check(event.base_knockback == 6 and event.direction == Vector3(1, 0.12, 0), "force payload preserves authored basepush and direction")
		match scenario:
			"closest", "thin": check(m.fighters[2].percent == 8 and m.fighters[3].percent == 0 and payload_seen, "closest actual swept body contact " + scenario)
			"team", "disabled": check(m.fighters[2].percent == 0 and m.fighters[3].percent == 8, "ineligible body does not block " + scenario)
			"terrain": check(m.fighters[2].percent == 0 and m.fighters[3].percent == 0 and m.projectiles.is_empty(), "thin terrain blocks before body")
			"trade": check(m.fighters[2].percent == 16, "independent simultaneous incoming projectiles retain both contacts")
		if wall: wall.free()
		for body in bodies: body.free()
		floor_body.free()
	if not failures: print("PASS: force world eligibility and sweep matrix")
	quit(1 if failures else 0)
