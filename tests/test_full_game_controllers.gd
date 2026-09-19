extends "res://tests/test_full_game_flow.gd"
## Bounded synthetic pad snapshots through the existing native bindings.
## No connected hardware or OS gamepad events are claimed by this test.
func run():
	var session = load("res://scripts/experimental/full_game_session.gd").new()
	if session.get("selected_devices") == null:
		printerr("FAIL: full game cannot assign a native controller to a human slot")
		session.free(); quit(1); return
	session.selected_devices = [7,8]
	# Explicit inventory fixture: sample_snapshot(present=true) never connects OS pads.
	session.connected_devices = func(): return [7,8]
	session.input_owner = "human"
	root.add_child(session)
	session.set_physics_process(false)
	assert(session.error.is_empty())
	assert(session.sources[0].device == 7 and session.sources[1].device == 8)
	for i in 45:
		await physics_frame
		var frames_by_id := {}
		for slot in 2: frames_by_id[slot+1] = session.sources[slot].sample_snapshot(session.simulation.tick,{}, {},Vector2.ZERO,true)
		session.simulation.simulate(frames_by_id)
	var before: float = session.actors[0].position.y
	for i in 8:
		await physics_frame
		session.simulation.simulate({1:session.sources[0].sample_snapshot(session.simulation.tick,{}, {JOY_BUTTON_A:true},Vector2.RIGHT,true),2:session.sources[1].sample_snapshot(session.simulation.tick,{}, {},Vector2.ZERO,true)})
	assert(session.actors[0].position.y > before+0.2,"pad A jumps through live match")
	assert(session.actors[0].velocity.x > 0,"pad stick moves")
	session.set_paused(true)
	var held = session.sources[0].sample_snapshot(session.simulation.tick,{}, {JOY_BUTTON_A:true},Vector2.ZERO,true)
	assert(not held.pressed.get("jump",false) and not held.held.get("jump",false),"pause suppresses held pad A")
	var missing = session.sources[0].sample_snapshot(session.simulation.tick,{}, {},Vector2.RIGHT,false)
	assert(missing.axis == Vector2.ZERO and not session.sources[0].connected)
	session.free()
	var bad = load("res://scripts/experimental/full_game_session.gd").new()
	bad.input_owner = "human"; bad.selected_devices = [7,7]
	root.add_child(bad)
	assert(not bad.error.is_empty(),"duplicate native controller rejected")
	bad.free()
	await frames(2)
	print("PASS: full game controller assignment synthetic native bindings and pause/disconnect suppression")
	quit()
