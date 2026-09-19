extends SceneTree
var app
func _initialize(): call_deferred("run")
func frames(n):
	for i in n: await physics_frame
func click(id):
	var button = app.find_child(id, true, false)
	assert(button != null, "missing control " + id)
	await frames(2)
	var point = button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
		await frames(2)
func key(code, pressed):
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func capture(label):
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.verification/core/full-game-stage-acceptance/flow-" + label + ".png")
func run():
	var path = "res://scenes/experimental_full_game.tscn"
	if not ResourceLoader.exists(path):
		print("FAIL: isolated full-game frontend scene is missing")
		quit(1)
		return
	app = load(path).instantiate()
	root.add_child(app)
	await frames(3)
	assert(app.state == "menu")
	await capture("menu")
	await click("ExperimentalPlay")
	assert(app.state == "select")
	assert(app.find_child("OpponentOwner",true,false).get_selected_metadata() == "sparring_easy")
	await capture("select")
	await click("StartMatch")
	assert(app.state == "ready")
	await frames(85)
	assert(app.state == "match")
	assert(app.session.simulation.fighter_interaction_mode == "grounded_jostle")
	assert(app.session.simulation.rules.stock_count == 3)
	assert(app.session.simulation.fighters[2].kit_id == "turbofit")
	assert(app.find_child("CollisionDebugOverlay",true,false) == null)
	await frames(65)
	var before = app.session.actors[0].position
	key(KEY_SPACE, true)
	await frames(8)
	key(KEY_SPACE, false)
	assert(app.session.actors[0].position.y > before.y + 0.2, "real gameplay jump after menu")
	await capture("match")
	key(KEY_A, true)
	var saw_respawn = false
	for i in 1800:
		await physics_frame
		if app.session.simulation.fighters[1].stocks < 3: saw_respawn = true
		if app.state == "results": break
	key(KEY_A, false)
	assert(saw_respawn and app.state == "results", "three stock native input result")
	assert(app.session.simulation.fighters[1].stocks == 0)
	var tick = app.session.simulation.tick
	await frames(5)
	assert(app.session.simulation.tick == tick, "results freeze")
	await capture("results")
	await click("Rematch")
	assert(app.state == "ready")
	await frames(85)
	assert(app.state == "match")
	assert(app.session.simulation.fighters[1].stocks == 3)
	assert(app.session.simulation.result.is_empty())
	key(KEY_ESCAPE, true)
	await frames(3)
	key(KEY_ESCAPE, false)
	assert(app.state == "paused")
	await click("ChangeFighters")
	assert(app.state == "select" and app.session == null)
	await click("BackMenu")
	assert(app.state == "menu")
	app.queue_free()
	await frames(3)
	print("PASS: full game native-input menu/select/3-stock results/rematch/back")
	quit()
