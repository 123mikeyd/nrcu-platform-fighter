extends "res://tests/test_core_grab_slice.gd"
func run():
	for endpoint in [1, 2]:
		for operation in ["ko", "reset"]:
			var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
			m.register_actor(1, a); m.register_actor(2, b)
			var rules = load("res://scripts/core/match/match_rules.gd").new()
			rules.stage.spawns = {1: Vector3(0, 10, 0), 2: Vector3(1, 10, 0)}
			m.configure_rules(rules); m.rematch()
			var f = Frame.new(); f.pressed.special = true
			await step(m, {1: f})
			for i in 11: await step(m)
			check(m.fighters[2].caught_by == 1, "actual grab established")
			if operation == "ko":
				# Keep relation valid through combat, then both cross lower bound.
				a.position.y = -9; b.position.y = -9
				await step(m)
			else: m.rematch()
			check(m.fighters[1].grab == null and m.fighters[2].caught_by == 0, "both endpoints released " + operation)
			check(a.get_collision_exceptions().is_empty() and b.get_collision_exceptions().is_empty(), "collision relation removed")
			check(m.fighters[1].grab_immune_until == 0 and m.fighters[2].grab_immune_until == 0, "no old release immunity survives fresh life")
			if operation == "reset": check(m.ability_events.is_empty() and m.events.is_empty(), "reset discards cleanup telemetry queue")
			m.rematch()
			# Active recovery and force on separate actors, no contact across separation.
			a.reset_at(Vector3(-5, 5, 0)); b.reset_at(Vector3(5, 5, 0))
			var up = Frame.new(); up.axis.y = -1; up.pressed.special = true
			var side = Frame.new(); side.axis.x = 1; side.pressed.special = true
			await step(m, {1: up, 2: side})
			check(m.fighters[1].recovery != null and m.fighters[2].force != null, "real simultaneous ability ownership")
			if operation == "reset": m.rematch()
			else:
				a.position.y = -9; b.position.y = -9; await step(m)
			check(m.fighters[1].recovery == null and m.fighters[2].force == null and not a.runtime.recovery_spent, "ability resources cleaned " + operation)
			m.rematch(); a.reset_at(Vector3(-5, 5, 0)); b.reset_at(Vector3(5, 5, 0))
			await step(m, {2: side})
			for i in 23: await step(m)
			check(m.projectiles.size() == 1, "real source-owned shot emitted")
			if operation == "reset": m.rematch()
			else: b.position.y = -9; await step(m)
			check(m.projectiles.is_empty(), "source shot expired " + operation)
			m.rematch()
			await step(m, {1: f})
			for i in 11: await step(m)
			check(m.fighters[2].caught_by == 1, "capture before single-endpoint cleanup")
			if operation == "reset":
				m.set_frozen(endpoint, true); m.rematch()
			else:
				m.fighters[endpoint].actor.position.y = -9; await step(m)
			check(m.fighters[1].grab == null and m.fighters[2].caught_by == 0, "single endpoint releases relation")
			check(a.get_collision_exceptions().is_empty() and b.get_collision_exceptions().is_empty(), "single endpoint collision cleanup")
			check(not m.fighters[endpoint].frozen and m.fighters[endpoint].actor.runtime.states.status != "caught", "fresh life removes constraints")
			a.free(); b.free()
	if not failures: print("PASS: stock cleanup (%d checks)" % checks)
	quit(1 if failures else 0)
