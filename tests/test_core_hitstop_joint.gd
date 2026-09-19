extends "res://tests/test_core_match_strikes.gd"
func run() -> void:
	var m = load("res://scripts/core/match/match_simulation.gd").new()
	var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1,a); m.register_actor(2,b)
	a.reset_at(Vector3(0,100,0)); b.reset_at(Vector3(1,100,0))
	var f = Frame.new(); f.pressed.special = true
	await tick(m,{1:f})
	for i in 11: await tick(m)
	check(m.fighters[2].caught_by == 1, "real grab relation established")
	var g = m.fighters[1].grab; var age = g.age; var elapsed = g.elapsed
	var at = a.position; var bt = b.position
	m.fighters[2].hitstop_left = 3
	for i in 3:
		await tick(m)
		check(a.position == at and b.position == bt and g.age == age and g.elapsed == elapsed, "joint relation stops both bodies and source clock")
	await tick(m)
	check(g.age == age + 1, "joint grab resumes once")
	a.free(); b.free()
	if not failures: print("PASS: core hitstop joint (%d checks)" % checks)
	quit(1 if failures else 0)
