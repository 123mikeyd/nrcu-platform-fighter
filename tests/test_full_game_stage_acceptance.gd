extends "res://tests/test_full_game_flow.gd"
## Real native-key traversal; no actor teleport, stock edits, or replacement floor.
func capture(label):
	if DisplayServer.get_name() != "headless":
		# Freeze only rendering wait: don't let held-inward catch auto-climb
		# while the evidence capture awaits the GPU frame.
		var running: bool = is_instance_valid(app.session) and app.session.is_physics_processing()
		if running: app.session.set_physics_process(false)
		await process_frame
		await RenderingServer.frame_post_draw
		var prefix := "960-" if "--compact" in OS.get_cmdline_user_args() else ""
		root.get_texture().get_image().save_png("res://.verification/core/full-game-stage-acceptance/"+prefix+label+".png")
		if running: app.session.set_physics_process(true)
func run():
	if "--compact" in OS.get_cmdline_user_args():
		root.size = Vector2i(960,540)
		root.content_scale_size = Vector2i(960,540)
	app = load("res://scenes/experimental_full_game.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	await click("ExperimentalPlay")
	app.input_owner = "human"
	await capture("select-1280")
	await click("StartMatch")
	assert(app.state == "ready")
	await frames(85)
	await frames(45)
	var a = app.session.actors[0]
	var b = app.session.actors[1]
	key(KEY_SPACE,true); key(KEY_ENTER,true)
	await frames(16)
	key(KEY_SPACE,false); key(KEY_ENTER,false)
	await frames(3)
	key(KEY_SPACE,true); key(KEY_ENTER,true)
	await frames(80)
	key(KEY_SPACE,false); key(KEY_ENTER,false)
	assert(a.runtime.grounded and absf(a.position.y-3.225)<0.04,"left authored platform")
	assert(b.runtime.grounded and absf(b.position.y-3.225)<0.04,"right authored platform")
	await capture("both-side-platforms")
	await frames(3)
	key(KEY_SPACE,true); key(KEY_D,true)
	for i in 100:
		if i == 16: key(KEY_SPACE,false)
		if i == 19: key(KEY_SPACE,true)
		await frames(1)
		if a.position.x >= -0.5: key(KEY_D,false)
	key(KEY_D,false)
	key(KEY_SPACE,false)
	print("TOP foot=",a.position)
	assert(a.runtime.grounded and absf(a.position.y-6.2)<0.04,"top authored platform reached by real double jump")
	await capture("top-platform")
	key(KEY_S,true); await frames(80); key(KEY_S,false)
	assert(a.runtime.grounded and absf(a.position.y+0.05)<0.04,"top drops to real main floor")
	for side in [-1,1]:
		app.session.rematch()
		await frames(45)
		var away = KEY_A if side == -1 else KEY_D
		var toward = KEY_D if side == -1 else KEY_A
		key(away,true)
		var left_floor := false
		for i in 160:
			await frames(1)
			if a.position.x * side > 8.65:
				key(away,false)
				await frames(18)
				key(away,true)
				for j in 30:
					await frames(1)
					if not a.runtime.grounded: break
				left_floor = not a.runtime.grounded
				break
		key(away,false); key(toward,true)
		var caught := false
		for i in 20:
			await frames(1)
			if not app.session.simulation.ledge_telemetry(1).anchor_id.is_empty(): caught = true; break
		key(toward,false)
		print("LEDGE side=",side," left_floor=",left_floor," caught=",caught," foot=",a.position)
		assert(left_floor and caught,"actual Toy Shelf catch both mirrors")
		await capture("ledge-left" if side == -1 else "ledge-right")
		key(KEY_W,true); await frames(3); key(KEY_W,false)
		await frames(20)
		assert(a.runtime.grounded and absf(a.position.y+0.05)<0.04,"ledge climb lands on real main floor")
		await capture("climb-left" if side == -1 else "climb-right")
	app.free(); await frames(3)
	print("PASS: full game authored four-platform traversal and both ledge catch/climb via real input")
	quit()
