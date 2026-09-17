extends "res://tests/test_core_grab_slice.gd"
func run():
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 10); shape.shape = box; floor_body.add_child(shape); floor_body.position.y = -0.5; root.add_child(floor_body)
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1, a); m.register_actor(2, b)
	for duration in [0.0, 0.25, 0.26, 1.25, 2.5, 5.0]:
		for whiff in [false, true]:
			m.reset({1: Vector3.ZERO, 2: Vector3(5 if whiff else 1, 0, 0)})
			for i in 10: await step(m)
			m.grab_hold_duration = duration
			var start: int = m.tick; var f = Frame.new(); f.pressed.special = true
			await step(m, {1: f})
			var bounded := clampf(duration, 0.25, 2.5)
			check(m.fighters[1].ready_tick == start + int(ceil((0.2 + 4.0/24 + bounded + 13.0/24 + 0.25)*60 - 0.000001)), "source shared cooldown")
			check(m.fighters[1].magic_ready_tick == start + 210, "separate magic cooldown")
			var release_age := int(ceil((0.2 + 4.0/24 + (0 if whiff else bounded) + 5.0/24)*60 - 0.000001))
			var end_age := int(ceil((0.2 + 4.0/24 + (0 if whiff else bounded) + 13.0/24)*60 - 0.000001))
			var count := 0
			for age in range(2, end_age + 1):
				var caught_input = Frame.new(); caught_input.held.attack = true; caught_input.held.jump = true
				if age == release_age - 1: caught_input.pressed.attack = true; caught_input.pressed.jump = true
				await step(m, {2: caught_input})
				for event in m.ability_events:
					if event.get("kind") == "grab_damage": count += 1; check(event.ordinal == count, "status ordinal once")
				if age == 22: check(m.fighters[1].grab.phase == ("ending" if whiff else "hold"), "startup exact endpoint")
				if not whiff and age == release_age - 1: check(m.fighters[2].caught_by == 1, "retained before release boundary")
				if age == release_age: check(m.fighters[2].caught_by == 0, "release crossing source boundary")
				if age < end_age: check(m.fighters[1].grab != null, "ending not early")
			check(m.fighters[1].grab == null, "ending exact ceiling")
			check(count == (0 if whiff else int(floor(bounded / 0.25))), "bounded electric tick count")
			check(m.fighters[2].percent == count * 2, "no finisher")
			if not whiff: check(m.fighters[2].move_id == "" and m.fighters[2].buffer.debug_pending().is_empty(), "caught fresh edges discarded not replayed")
	# Small nonzero axes must not become neutral grab.
	for axis in [Vector2(0.01, 0), Vector2(0, 0.01), Vector2.DOWN]:
		m.reset({1: Vector3.ZERO, 2: Vector3.RIGHT})
		var f = Frame.new(); f.pressed.special = true; f.axis = axis
		await step(m, {1: f}); check(m.fighters[1].grab == null, "exact zero selector")
	a.free(); b.free(); floor_body.free()
	if not failures: print("PASS: grab clocks input (%d checks)" % checks)
	quit(1 if failures else 0)
