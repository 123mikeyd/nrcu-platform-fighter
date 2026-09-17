extends "res://tests/test_core_directional_up.gd"
func run() -> void:
	for grounded in [false, true]:
		for facing in [-1.0, 1.0]:
			var m = Match.new()
			var a = Actor.new(); var b = Actor.new(); var c = Actor.new()
			for actor in [a, b, c]: root.add_child(actor)
			m.register_actor(1, a); m.register_actor(2, b); m.register_actor(3, c)
			# Ground sweep reaches the lower cone but not the upward launch cone.
			var offset := Vector3(facing * 0.7, -1.5, 0) if grounded else Vector3(0, -2, 0)
			var miss := Vector3(facing * 0.7, 1.5, 0) if grounded else Vector3(0, 2, 0)
			m.reset({1: Vector3(0, 30, 0), 2: Vector3(0, 30, 0) + offset, 3: Vector3(0, 30, 0) + miss})
			a.runtime.grounded = grounded
			await tick(m, {1: aim(Vector2(facing, 1))})
			check(m.fighters[1].move_id == ("LOW SWEEP" if grounded else "DOWN STRIKE"), "down basic selects acceptance grounded context")
			check(m.fighters[2].percent == 8 and m.fighters[3].percent == 0, "mirrored downward query not upward launch cone")
			var launch := Vector3.DOWN
			if grounded:
				launch = Vector3(facing, -0.25, 0).normalized()
				launch.y = 0.35
			check(b.velocity.is_equal_approx(launch.normalized() * (3.8 + 8 * 0.065 + 8 * 0.12)), "exact source launch: normalized sweep x retained before y overwrite")
			check(m.fighters[1].ready_tick == 20, "down basic cooldown 20")
			for actor in [a, b, c]: actor.free()
	if not failures: print("PASS: directional down (%d checks)" % checks)
	quit(1 if failures else 0)
