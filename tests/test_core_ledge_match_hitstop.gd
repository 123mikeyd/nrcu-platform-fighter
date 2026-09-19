extends "res://tests/test_core_ledge_match.gd"
func run() -> void:
	var terrain = body(Vector3(2,-0.5,0),Vector3(4,1,4))
	var p = LedgePolicy.new(); p.protection_ticks = 3; p.max_hang_ticks = 4
	var m = setup_ledge(p)
	# Isolate logical anchor occupancy; real live/stopped body obstruction is in test_core_body_ledge.
	m.fighters[1].actor.add_collision_exception_with(m.fighters[2].actor)
	m.fighters[2].actor.add_collision_exception_with(m.fighters[1].actor)
	m.fighters[1].actor.position = Vector3(-1.1,-1,0); m.fighters[2].actor.position = Vector3(-1,-1,0)
	await tick(m,{1:frame(false,1),2:frame(false,1)})
	check(m.ledge_telemetry(1).anchor_id == "left" and m.ledge_telemetry(2).anchor_id == "", "atomic snapshot stable ID wins contest")
	var entry = m.ledge_telemetry(1); var at = m.fighters[1].actor.position
	m.fighters[1].hitstop_left = 6
	for i in 6:
		m.fighters[2].actor.position = Vector3(-1,-1,0); m.fighters[2].actor.runtime.velocity = Vector3(1,-1,0)
		await tick(m,{2:frame(false,1)})
		check(m.ledge_telemetry(1).anchor_id == "left" and m.ledge_telemetry(2).anchor_id == "", "stopped occupant retained through live contest")
		check(m.fighters[1].actor.position == at, "stopped ledge actor body stasis")
		check(m.ledge_telemetry(1).caught_at == entry.caught_at+i+1 and m.ledge_telemetry(1).protected_until == entry.protected_until+i+1, "actor-local ledge clocks shift once per stop")
		var snap = m.ledge_state.duplicate(true); m.simulate()
		check(m.ledge_state == snap, "duplicate engine frame cannot advance ledge state")
	await tick(m)
	check(m.ledge_telemetry(1).anchor_id == "left", "normal hang resumes after hitstop")
	m.set_frozen(1,true)
	check(m.ledge_telemetry(1).anchor_id == "", "explicit freeze releases unlike hitstop")
	cleanup(m)
	m = setup_ledge(); m.fighters[1].hitstop_left = 1
	m.fighters[1].actor.runtime.velocity = Vector3(1,-1,0); m.fighters[1].actor.velocity = Vector3(1,-1,0)
	await tick(m,{1:frame(false,1)})
	check(m.ledge_telemetry(1).anchor_id == "", "stopped unoccupied actor cannot newly catch")
	await tick(m,{1:frame(false,1)})
	check(m.ledge_telemetry(1).anchor_id == "left", "eligible resumed actor catches")
	m.fighters[1].hitstop_left = 2
	var jump = Frame.new(); jump.pressed.jump = true
	await tick(m,{1:jump}); await tick(m)
	check(m.ledge_telemetry(1).anchor_id == "left" and not m.fighters[1].buffer.peek("jump").is_empty(), "hitstop buffers ledge departure without accepting it")
	await tick(m)
	check(m.ledge_telemetry(1).anchor_id == "" and m.fighters[1].actor.velocity == Vector3(-4,10,0), "buffered ledge departure accepts once on resume")
	cleanup(m)
	m = setup_ledge(); m.fighters = {2:m.fighters[2],1:m.fighters[1]}
	# Same logical contest with reversed dictionary insertion, not a blocked-body route.
	m.fighters[1].actor.add_collision_exception_with(m.fighters[2].actor)
	m.fighters[2].actor.add_collision_exception_with(m.fighters[1].actor)
	m.fighters[2].actor.position = Vector3(-1,-1,0)
	await tick(m,{1:frame(false,1),2:frame(false,1)})
	check(m.ledge_telemetry(1).anchor_id == "left" and m.ledge_telemetry(2).anchor_id == "", "contest winner independent of dictionary insertion")
	cleanup(m); terrain.free()
	if not failures: print("PASS: core ledge match hitstop (%d checks)" % checks)
	quit(1 if failures else 0)
