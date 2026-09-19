extends "res://tests/test_full_game_selectors.gd"
## Real preview UI and parsed keyboard events; no actor/contact state injection.
func run():
	root.gui_embed_subwindows = true
	app = load("res://scenes/experimental_full_game.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	await click("ExperimentalPlay")
	await choose("OpponentOwner", "human")
	await click("StartMatch")
	assert(app.state == "ready")
	await frames(130)
	assert(app.state == "match")
	var before: float = app.session.simulation.fighters[2].percent
	key(KEY_D, true)
	for i in 180:
		await frames(1)
		if app.session.actors[1].position.x - app.session.actors[0].position.x < 3.0: break
	key(KEY_D, false)
	await frames(12)
	assert(app.session.actors[1].position.x - app.session.actors[0].position.x < 3.0, "real approach prerequisite")
	key(KEY_D, true); key(KEY_G, true)
	await frames(2)
	key(KEY_D, false); key(KEY_G, false)
	var saw_projectile := false
	for i in 90:
		await frames(1)
		if not app.session.simulation.projectile_telemetry().is_empty(): saw_projectile = true
		if app.session.simulation.fighters[2].percent > before: break
	assert(saw_projectile, "parsed special emits committed projectile")
	assert(app.session.simulation.fighters[2].percent > before, "real combat causes opponent damage")
	await capture("combat")
	key(KEY_ESCAPE, true); await frames(2); key(KEY_ESCAPE, false)
	assert(app.state == "paused")
	var tick: int = app.session.simulation.tick
	await frames(8)
	assert(app.session.simulation.tick == tick, "pause freezes combat clock")
	await click("Resume")
	assert(app.state == "match")
	await frames(3)
	assert(app.session.simulation.tick > tick, "GUI resume advances combat clock")
	app.free(); await frames(3)
	print("PASS: preview UI READY real-input projectile damage pause resume")
	quit()
