extends "res://tests/test_core_grab_slice.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1, a); m.register_actor(2, b)
	check(m.has_method("set_frozen"), "incoming freeze seam exists")
	if not m.has_method("set_frozen"): a.free(); b.free(); quit(1); return
	for endpoint in [1, 2]:
		for reason in ["utility", "freeze", "disable", "reset", "removal"]:
			m.reset({1: Vector3(0, 10, 0), 2: Vector3(1, 10, 0)})
			var f = Frame.new(); f.pressed.special = true
			await step(m, {1: f})
			for i in 11: await step(m)
			check(m.fighters[2].caught_by == 1, "air capture before " + reason)
			b.runtime.recovery_spent = true; b.runtime.air_jumps_left = 0
			match reason:
				"utility": m.cancel_action(endpoint, "utility")
				"freeze": m.set_frozen(endpoint, true)
				"disable": m.set_enabled(endpoint, false)
				"reset": m.reset({1: Vector3.ZERO, 2: Vector3.RIGHT})
				"removal":
					var actor = m.fighters[endpoint].actor
					actor.free()
			check(m.fighters[2].caught_by == 0 and m.fighters[1].grab == null, "synchronous two-ended " + reason)
			if is_instance_valid(b):
				check(b.get_collision_exceptions().is_empty(), "collision cleanup " + reason)
				if reason != "reset": check(b.runtime.recovery_spent and b.runtime.air_jumps_left == 0, "no resource refund " + reason)
			if reason == "reset":
				check(m.fighters[2].grab_immune_until == 0 and m.fighters[1].magic_ready_tick == 0, "reset cooldowns and immunity")
			if reason == "removal":
				m.reset({1: Vector3.ZERO, 2: Vector3.RIGHT})
				check(not m.fighters[endpoint].enabled, "reset does not resurrect removed actor")
				if endpoint == 1: a = Actor.new(); root.add_child(a); m.fighters.erase(1); m.register_actor(1, a)
				else: b = Actor.new(); root.add_child(b); m.fighters.erase(2); m.register_actor(2, b)
	a.free(); b.free()
	if not failures: print("PASS: grab lifecycle (%d checks)" % checks)
	quit(1 if failures else 0)
