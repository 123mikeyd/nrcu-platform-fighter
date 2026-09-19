extends "res://tests/test_core_match_strikes.gd"
func run() -> void:
	var Match = load("res://scripts/core/match/match_simulation.gd")
	var m = Match.new()
	check(m.has_method("configure_hitstop"), "match exposes opt-in configurable hitstop")
	if not m.has_method("configure_hitstop"): quit(1); return
	var policy = load("res://scripts/core/combat/hitstop_profile.gd").new()
	check(policy.direct_hit_ticks == 4, "four ticks is explicit initial tuning")
	m.configure_hitstop(policy)
	var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	a.reset_at(Vector3(0, 5, 0)); b.reset_at(Vector3(1, 5, 0))
	m.register_actor(1, a); m.register_actor(2, b)
	await tick(m, {1: frame(true, 1.0)})
	check(m.fighters[2].percent == 8, "real direct hit commits")
	var at = a.position; var bt = b.position; var av = a.velocity; var bv = b.velocity
	var age = a.runtime.tick; var stun = b.runtime.hitstun_left
	check(m.hitstop_telemetry(1).remaining_ticks == 4 and m.hitstop_telemetry(2).remaining_ticks == 4, "symmetric freeze committed after hit")
	for i in 4:
		await tick(m, {1: frame(false, -1.0)})
		check(a.position == at and b.position == bt and a.velocity == av and b.velocity == bv, "real physics stasis")
		check(a.runtime.tick == age and b.runtime.hitstun_left == stun, "runtime and stun clocks stop")
		m.simulate()
		check(m.hitstop_telemetry(1).remaining_ticks == 3-i, "one stop decrement per engine frame")
	await tick(m)
	check(b.position != bt and a.runtime.tick == age + 1, "resume exactly after four skipped ticks")
	a.free(); b.free()
	if not failures: print("PASS: core hitstop (%d checks)" % checks)
	quit(1 if failures else 0)
