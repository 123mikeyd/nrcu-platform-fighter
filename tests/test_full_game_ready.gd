extends "res://tests/test_full_game_flow.gd"
func run():
	app = load("res://scenes/experimental_full_game.tscn").instantiate()
	root.add_child(app); await frames(3)
	await click("ExperimentalPlay"); await click("StartMatch")
	if app.state != "ready":
		printerr("FAIL: match starts live before a clean ready gate")
		app.free(); quit(1); return
	var tick = app.session.simulation.tick
	key(KEY_G,true)
	await frames(12)
	assert(app.session.simulation.tick == tick,"ready does not simulate AI or human moves")
	key(KEY_ESCAPE,true); await frames(2); key(KEY_ESCAPE,false)
	assert(app.state == "paused")
	var remaining = app.ready_ticks
	await frames(8)
	assert(app.ready_ticks == remaining,"pause freezes ready gate")
	await click("Resume")
	assert(app.state == "ready")
	await frames(90)
	assert(app.state == "match")
	assert(app.session.simulation.fighters[1].grab == null,"held menu/ready special must not activate")
	key(KEY_G,false)
	app.free(); await frames(3)
	print("PASS: full game ready gate pause resume and held action suppression")
	quit()
