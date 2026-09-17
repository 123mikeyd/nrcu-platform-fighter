extends "res://tests/test_core_turbo_match_routes.gd"
func run():
	var floor = floor_body(); var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b)
	for airborne in [false,true]:
		for aim in [Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN,Vector2.UP]:
			var y: float = 100 if airborne else .01
			m.reset({1:Vector3(0,y,0),2:Vector3(8,y,0)})
			if not airborne:
				for i in 12: await step(m)
			var input = press(aim); input.held.special = true
			await step(m,{1:input})
			var expected: String = "power_chord" if aim == Vector2.ZERO else ("sound_wave" if aim == Vector2.RIGHT else ("sound_orb" if aim == Vector2.DOWN else "rising_chord"))
			check(m.kit_telemetry(1).special.move == expected, "ground/air special dispatch "+expected)
			check(m.fighters[1].force == null and m.fighters[1].grab == null, "all routes exclude Teknium fallback")
			if aim == Vector2.ZERO:
				var hold = Frame.new(); hold.held.special = true
				for i in 100: await step(m,{1:hold})
				check(m.kit_telemetry(1).special.power == 1 and m.kit_telemetry(1).special.phase == "anticipation", "hold beyond cap remains charged")
				check(a.runtime.grounded != airborne, "charge release retains requested ground/air context")
				b.position = a.position + Vector3(2,0,0); b.runtime.velocity = a.runtime.velocity
				await step(m)
				check(m.fighters[2].percent == 26, "full charge release real damage in both contexts")
			elif aim == Vector2.UP:
				check(a.runtime.recovery_spent and a.runtime.air_jumps_left == 0 and a.velocity.y == 13.5, "both contexts share recovery resource")
	# Mixed kit trade: Teknium immediate strike meets Turbo's actual crossing tick.
	m.reset({1:Vector3(0,.01,0),2:Vector3(1.5,.01,0)})
	for i in 12: await step(m)
	await step(m,{1:press(Vector2.RIGHT,"attack")})
	for i in 15: await step(m)
	await step(m,{2:press(Vector2.LEFT,"attack")})
	check(m.fighters[1].percent == 8 and m.fighters[2].percent == 14, "mixed Teknium/Turbo trade preserves both source payloads")
	# Actual swept terrain, not elapsed-time-only wave simulation.
	var wall = StaticBody3D.new(); var shape = CollisionShape3D.new(); var box = BoxShape3D.new()
	box.size = Vector3(.02,4,4); shape.shape = box; wall.add_child(shape); wall.position = Vector3(1.8,2,0); root.add_child(wall)
	m.reset({1:Vector3(0,.01,0),2:Vector3(3,.01,0)})
	for i in 12: await step(m)
	await step(m,{1:press(Vector2.RIGHT)})
	var terrain_hit := false
	for i in 20:
		await step(m)
		for event in m.ability_events:
			if event.kind == "terrain": terrain_hit = true
	check(terrain_hit and m.projectile_telemetry().is_empty() and m.fighters[2].percent == 0, "thin terrain consumes swept wave before fighter")
	wall.free(); a.free(); b.free(); floor.free()
	if not failures: print("PASS: turbo match matrix (%d checks)" % checks)
	quit(1 if failures else 0)
