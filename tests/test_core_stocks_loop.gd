extends "res://tests/test_core_grab_slice.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1, a); m.register_actor(2, b)
	check(m.has_method("configure_rules"), "explicit opt-in rules seam")
	if not m.has_method("configure_rules"): a.free(); b.free(); quit(1); return
	var rules = load("res://scripts/core/match/match_rules.gd").new()
	check(rules.stock_count == 3 and rules.respawn_protection_ticks == 0 and rules.respawn_hitstun_ticks == 33, "source-backed defaults")
	m.configure_rules(rules); m.rematch()
	check(a.position == Vector3(-4, 1, 0) and b.position == Vector3(4, 1, 0), "stage spawns")
	a.reset_at(Vector3(0, 3, 0)); b.reset_at(Vector3(1, 3, 0))
	var f = Frame.new(); f.pressed.attack = true; f.axis.x = 1
	await step(m, {1: f})
	check(m.fighters[2].percent > 0, "two actors actually fight")
	b.position.y = -9
	await step(m)
	check(m.fighters[2].stocks == 2 and b.position == Vector3(4, 1, 0), "KO commits stock and stage respawn")
	check(m.fighters[2].percent == 0 and b.runtime.hitstun_left == 33 and not b.runtime.grounded, "air respawn resets damage and retains source stun")
	check(m.lifecycle_events.size() == 2 and m.lifecycle_events[0].kind == "ko" and m.lifecycle_events[1].kind == "respawn", "once ordered lifecycle events")
	for i in 2:
		b.position.y = -9; await step(m)
	check(m.result.kind == "WIN" and m.result.winner_id == 1 and m.fighters[2].stocks == 0, "final stock produces winner")
	check(m.fighters[2].eliminated and not m.fighters[2].enabled, "terminal elimination")
	var end_tick = m.tick
	await step(m, {1: f, 2: f})
	check(m.tick == end_tick and m.lifecycle_events.is_empty(), "results stop actions and duplicate events")
	var generation = m.generation
	m.rematch()
	check(m.result.is_empty() and m.tick == 0 and m.generation > generation, "rematch new generation and clock")
	check(m.fighters[2].stocks == 3 and m.fighters[2].enabled and not m.fighters[2].eliminated, "rematch restores roster")
	await step(m)
	check(m.fighters[1].activation_id == "" and m.fighters[2].percent == 0, "result commands never replay")
	a.free(); b.free()
	if not failures: print("PASS: stocks loop (%d checks)" % checks)
	quit(1 if failures else 0)
