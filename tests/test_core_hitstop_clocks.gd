extends "res://tests/test_core_match_strikes.gd"
func run() -> void:
	var m = load("res://scripts/core/match/match_simulation.gd").new()
	var a = Actor.new(); root.add_child(a); a.reset_at(Vector3(0, 20, 0)); m.register_actor(1, a)
	var f = m.fighters[1]
	f.hitstop_left = 8; f.ready_tick = 20; f.magic_ready_tick = 60; f.grab_immune_until = 30; f.protection_until = 40
	var press = Frame.new(); press.pressed.jump = true; press.held.jump = true
	await tick(m, {1: press})
	check(not f.buffer.peek("jump").is_empty(), "stopped actor ingests input edges")
	var release = Frame.new(); release.released.jump = true
	await tick(m, {1: release})
	for i in 6: await tick(m)
	check(f.ready_tick == 28 and f.magic_ready_tick == 68 and f.grab_immune_until == 38 and f.protection_until == 48, "all live absolute fighter deadlines shift coherently")
	check(not f.buffer.peek("jump").is_empty() and f.buffer.peek("jump").age == 0, "buffer lifetime freezes beyond ordinary window")
	# Remove queued jump, then prove a release survives re-press during stop.
	f.buffer.consume("jump")
	a.runtime.velocity = Vector3(0, 15, 0); a.velocity = a.runtime.velocity
	var held = Frame.new(); held.held.jump = true
	await tick(m, {1: held})
	check(a.velocity.y < a.profile.short_jump_speed, "release latch cuts existing jump on resume even after re-press")
	check(f.buffer.peek("jump").is_empty(), "release does not synthesize a press")
	a.free()
	if not failures: print("PASS: core hitstop clocks (%d checks)" % checks)
	quit(1 if failures else 0)
