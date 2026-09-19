extends "res://tests/test_core_grab_slice.gd"
func run():
	for protection in [0, 12]:
		var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
		m.register_actor(1, a); m.register_actor(2, b)
		var rules = load("res://scripts/core/match/match_rules.gd").new(); rules.respawn_protection_ticks = protection
		rules.stage.spawns = {1: Vector3(0, 10, 0), 2: Vector3(1, 10, 0)}
		m.configure_rules(rules); m.rematch(); b.position.y = -9; await step(m)
		var f = Frame.new(); f.pressed.attack = true; f.axis.x = 1
		await step(m, {1: f})
		check((m.fighters[2].percent == 0) == (protection > 0), "configured protection gates damage; legacy zero does not")
		m.rematch(); b.position.y = -9; await step(m)
		f = Frame.new(); f.pressed.special = true
		await step(m, {1: f})
		for i in 11: await step(m)
		check((m.fighters[2].caught_by == 0) == (protection > 0), "protection gates grab through exact last protected tick")
		if protection > 0:
			check(m.tick == m.fighters[2].protection_until, "protection interval exclusive upper bound")
			m.cancel_action(1, "test"); m.fighters[1].ready_tick = 0
			f = Frame.new(); f.pressed.attack = true; f.axis.x = 1
			await step(m, {1: f})
			check(m.fighters[2].percent > 0, "first unprotected tick accepts damage")
		m.rematch()
		check(m.fighters[2].protection_until == 0 and m.fighters[2].grab_immune_until == 0, "rematch clears both immunities")
		a.free(); b.free()
	if not failures: print("PASS: stock protection (%d checks)" % checks)
	quit(1 if failures else 0)
