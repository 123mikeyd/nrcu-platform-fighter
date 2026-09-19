extends "res://tests/test_full_game_selectors.gd"
## Connection inventory is synthetic; normalization remains the shared source.
## Native keyboard events below still use Input.parse_input_event.
var pads: Array = []
func connected_pads(): return pads.duplicate()
func check(ok: bool, message: String):
	if not ok:
		printerr("FAIL: " + message)
		quit(1)
		return false
	return true
func run():
	var rejected = load("res://scripts/experimental/full_game_session.gd").new()
	rejected.selected_devices = [2147483647,-1]
	root.add_child(rejected)
	if not check(not rejected.error.is_empty() and rejected.actors.is_empty(),"absent pad refuses session before actor construction"): return
	rejected.free()
	var deferred_session = load("res://scripts/experimental/full_game_session.gd").new()
	deferred_session.selected_devices = [7,8]
	deferred_session.input_owner = "human"
	deferred_session.connected_devices = connected_pads
	pads = [7,8]
	root.add_child.call_deferred(deferred_session)
	# Lose a pad after queuing startup but before _ready validates configuration.
	pads.erase(8)
	await deferred_session.ready
	if not check(not deferred_session.error.is_empty() and deferred_session.actors.is_empty(),"queued startup validates latest inventory before creating actors"): return
	deferred_session.queue_free()
	pads.clear()
	app = load("res://scenes/experimental_full_game.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	await click("ExperimentalPlay")
	await click("StartMatch")
	if not check(app.state == "ready", "keyboard start reaches ready"): return
	app.session.sources[0].device = 2147483647
	# Exercise the result UI boundary without claiming a played stock outcome.
	app.show_results({"kind":"DRAW"})
	await click("Rematch")
	if not check(app.state == "results", "absent controller refuses results rematch"): return
	app.session.connected_devices = connected_pads
	app.session.sources[0].device = 7
	app.session.sources[1].device = 8
	app.session.input_owner = "human"
	pads = [7,8]
	await click("Rematch")
	if not check(app.state == "ready", "reconnected inventory allows rematch"): return
	for slot in 2:
		var device = 7 + slot
		pads.erase(device)
		Input.joy_connection_changed.emit(device,false)
		if not check(app.state == "paused" and app.paused_from == "ready", "disconnect pauses READY for either slot"): return
		var remaining = app.ready_ticks
		var tick = app.session.simulation.tick
		await click("Resume")
		if not check(app.state == "paused" and app.ready_ticks == remaining and app.session.simulation.tick == tick,"absent pad refuses resume without advancing clocks"): return
		Input.joy_connection_changed.emit(device,false)
		if not check(app.state == "paused" and app.ready_ticks == remaining,"disconnect while paused preserves queued READY"): return
		pads.append(device)
		Input.joy_connection_changed.emit(device,true)
		if not check(app.state == "paused", "reconnect does not auto resume"): return
		var source = app.session.sources[slot]
		var held = source.sample_snapshot(tick,{}, {JOY_BUTTON_A:true,JOY_BUTTON_X:true,JOY_BUTTON_B:true,JOY_BUTTON_LEFT_SHOULDER:true},Vector2.ZERO,true)
		for action in ["jump","attack","special","shield"]:
			if not check(not held.pressed.get(action,false) and not held.held.get(action,false),"reconnect suppresses held " + action + " slot " + str(slot)): return
		source.sample_snapshot(tick,{}, {},Vector2.ZERO,true)
		var fresh = source.sample_snapshot(tick,{}, {JOY_BUTTON_A:true},Vector2.ZERO,true)
		if not check(fresh.pressed.get("jump",false), "release then new pad press is accepted"): return
		# A snapshot fixture does not make this device visible to live Input.
		if not check(not Input.get_connected_joypads().has(device) and source.sample(tick).axis == Vector2.ZERO and not source.connected,"snapshot connectivity never alters native device getter"): return
		await click("Resume")
		if not check(app.state == "ready", "reconnected inventory resumes queued READY"): return
	# Loss at results must not clear the result or start a new round.
	app.show_results({"kind":"DRAW"})
	for device in [7,8]:
		pads.erase(device)
		Input.joy_connection_changed.emit(device,false)
		if not check(app.state == "results", "disconnect preserves results"): return
		await click("Rematch")
		if not check(app.state == "results", "either absent slot refuses rematch"): return
		pads.append(device)
		Input.joy_connection_changed.emit(device,true)
		if not check(app.state == "results", "results reconnect never auto restarts"): return
	app.free()
	await frames(2)
	print("PASS: full game controller startup queued ready pause results and both-slot reconnect boundaries")
	quit()
