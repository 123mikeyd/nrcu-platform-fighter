extends "res://tests/test_core_match_strikes.gd"
func run() -> void:
	var m = load("res://scripts/core/match/match_simulation.gd").new()
	var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1,a); m.register_actor(2,b)
	m.configure_hitstop(load("res://scripts/core/combat/hitstop_profile.gd").new())
	m.reset({1:Vector3(0,5,0),2:Vector3(1,5,0)})
	await tick(m,{1:frame(true,1)})
	m.fighters[1].jump_release_pending = true
	m.set_enabled(1,false)
	check(m.fighters[1].hitstop_left == 0 and not m.fighters[1].jump_release_pending, "disable clears stop and release")
	m.reset({1:Vector3(0,5,0),2:Vector3(1,5,0)})
	check(m.fighters[2].hitstop_left == 0 and not m.hitstop_telemetry(2).stopped_this_tick, "reset clears old stop")
	await tick(m,{1:frame(true,1)})
	check(m.fighters[2].hitstop_left == 4, "new generation contacts still trigger")
	var rules = load("res://scripts/core/match/match_rules.gd").new(); rules.stock_count = 2
	m.configure_rules(rules); m.rematch()
	m.fighters[2].hitstop_left = 8; b.position.y = -9
	await tick(m)
	check(m.fighters[2].stocks == 1 and m.fighters[2].hitstop_left == 0, "KO clears stop before respawn")
	m.fighters[1].hitstop_left = 9; m.fighters[1].jump_release_pending = true; b.position.y = -9
	await tick(m)
	check(not m.result.is_empty() and m.fighters[1].hitstop_left == 0 and not m.fighters[1].jump_release_pending, "results clear surviving fighter stop")
	a.free(); b.free()
	if not failures: print("PASS: core hitstop lifecycle (%d checks)" % checks)
	quit(1 if failures else 0)
