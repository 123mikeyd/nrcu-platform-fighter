extends "res://tests/test_full_game_flow.gd"
const AUTHORED_LAYOUTS = preload("res://scripts/stage_layouts.gd")
func menu_key(code):
	for down in [true,false]:
		var event = InputEventKey.new()
		event.physical_keycode = code; event.keycode = code; event.pressed = down
		root.push_input(event,true)
	await frames(2)
func choose(id, metadata):
	await click(id)
	var control = app.find_child(id,true,false)
	var index = -1
	for i in control.item_count:
		if control.get_item_metadata(i) == metadata: index = i
	assert(index >= 0 and not control.is_item_disabled(index))
	control.get_popup().set_focused_item(index)
	await menu_key(KEY_ENTER)
	assert(control.get_selected_metadata() == metadata)
func run():
	root.gui_embed_subwindows = true
	app = load("res://scenes/experimental_full_game.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	await click("ExperimentalPlay")
	var fighter = app.find_child("Fighter1",true,false)
	for i in fighter.item_count:
		assert(fighter.is_item_disabled(i) == (fighter.get_item_metadata(i) not in ["teknium","turbofit"]))
	await choose("Fighter1","turbofit")
	await choose("Fighter2","teknium")
	for input_owner in ["human","repo_easy","repo_normal","repo_hard","sparring_easy"]:
		await choose("OpponentOwner",input_owner)
		await click("StartMatch")
		assert(app.state == "ready")
		await frames(85)
		assert(app.state == "match")
		assert(app.session.input_owner == input_owner)
		assert(app.session.simulation.fighters[1].kit_id == "turbofit")
		assert(app.session.simulation.fighters[2].kit_id == "teknium")
		assert(app.session.inputs.enabled == (input_owner != "human"))
		var authored_surfaces: Array = AUTHORED_LAYOUTS.surfaces("toy_room")
		assert(authored_surfaces.size() == 1)
		var center: Vector3 = authored_surfaces[0][0]
		var size: Vector3 = authored_surfaces[0][1]
		assert(is_equal_approx(center.x - size.x * 0.5, -12.0))
		assert(is_equal_approx(center.x + size.x * 0.5, 12.0))
		assert(is_equal_approx(app.session.inputs.stage_bounds.left, center.x - size.x * 0.5))
		assert(is_equal_approx(app.session.inputs.stage_bounds.right, center.x + size.x * 0.5))
		assert(is_equal_approx(app.session.inputs.stage_bounds.top, center.y + size.y * 0.5))
		await frames(45)
		key(KEY_SPACE,true); key(KEY_ENTER,true)
		await frames(6)
		key(KEY_SPACE,false); key(KEY_ENTER,false)
		assert(app.session.actors[0].velocity.y > 0,"P1 jump after production selector")
		assert(app.session.sources[1]._previous.get("jump",false) == (input_owner == "human"))
		key(KEY_ESCAPE,true); await frames(3); key(KEY_ESCAPE,false)
		assert(app.state == "paused")
		await click("ChangeFighters")
	assert(app.state == "select")
	app.free()
	await frames(3)
	print("PASS: full game real selector swapped kits and five input owners")
	quit()
