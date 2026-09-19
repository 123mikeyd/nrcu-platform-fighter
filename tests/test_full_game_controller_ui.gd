extends "res://tests/test_full_game_selectors.gd"
func pad(button_code,device=7):
	for down in [true,false]:
		var event := InputEventJoypadButton.new()
		event.device = device; event.button_index = button_code; event.pressed = down
		root.push_input(event,true)
		await frames(2)
func run():
	app = load("res://scenes/experimental_full_game.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	await click("ExperimentalPlay")
	if app.find_child("Device1",true,false) == null:
		printerr("FAIL: human device selectors absent from production frontend")
		app.free(); quit(1); return
	assert(app.find_child("Device1",true,false).get_selected_metadata() == -1)
	assert(app.find_child("Device2",true,false).disabled,"AI owns P2 without a human device")
	await choose("OpponentOwner","human")
	assert(not app.find_child("Device2",true,false).disabled)
	await click("StartMatch")
	assert(app.state == "ready")
	await frames(85)
	assert(app.session.selected_devices == [-1,-1])
	# Route synthetic Start only after assignment, without pretending pad is connected.
	app.session.sources[0].device = 7
	await pad(JOY_BUTTON_START,8)
	assert(app.state == "match","unassigned pad cannot pause")
	await pad(JOY_BUTTON_START)
	assert(app.state == "paused","assigned controller Start pauses")
	var tick = app.session.simulation.tick
	await frames(5)
	assert(app.session.simulation.tick == tick)
	# A disconnected assigned device cannot silently resume an unattended fighter.
	await pad(JOY_BUTTON_START)
	assert(app.state == "paused")
	app.session.sources[0].device = -1
	await click("Resume")
	assert(app.state == "match")
	key(KEY_ESCAPE,true); await frames(2); key(KEY_ESCAPE,false)
	await click("ChangeFighters")
	await pad(JOY_BUTTON_B)
	assert(app.state == "menu","controller B returns from select")
	await click("ExperimentalPlay")
	app.selected_devices = [7,-1]
	await click("StartMatch")
	assert(app.state == "select" and app.session == null,"disconnected device cannot start a live match")
	app.free(); await frames(2)
	print("PASS: full game device selector ownership controller pause back and disconnected resume gate")
	quit()
