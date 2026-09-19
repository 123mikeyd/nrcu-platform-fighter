extends "res://tests/test_core_grab_slice.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1, a); m.register_actor(2, b)
	m.reset({1: Vector3(0, -100, 0), 2: Vector3(0, 100, 0)})
	await step(m)
	check(m.result.is_empty() and a.position.y < -100 and m.lifecycle_events.is_empty(), "no rules preserves sandbox")
	var rules = load("res://scripts/core/match/match_rules.gd").new()
	m.configure_rules(rules); rules.stock_count = 99; rules.stage.spawns[1] = Vector3(9, 9, 0)
	m.reset({1: Vector3(0, -100, 0)})
	check(a.position == Vector3(-4, 1, 0) and b.position == Vector3(4, 1, 0) and m.fighters[1].stocks == 3, "opted reset uses private authoritative stage")
	m.set_enabled(2, false); b.position.y = -100
	a.position.y = -9; await step(m)
	check(m.fighters[2].stocks == 3 and not m.fighters[2].eliminated and m.result.is_empty(), "temporary disabled not eliminated or KO target")
	m.set_enabled(2, true); b.reset_at(Vector3(4, 1, 0))
	check(m.fighters[2].enabled, "temporary disabled can resume")
	for at in [Vector3(-16, 0, 0), Vector3(16, 0, 0), Vector3(0, -8, 0), Vector3(0, 15, 0)]:
		check(not m.rules.stage.outside(at), "strict source blast endpoint")
	for at in [Vector3(-16.1, 0, 0), Vector3(16.1, 0, 0), Vector3(0, -8.1, 0), Vector3(0, 15.1, 0)]:
		check(m.rules.stage.outside(at), "all four source blast directions")
	a.free(); b.free()
	if not failures: print("PASS: stock rules (%d checks)" % checks)
	quit(1 if failures else 0)
