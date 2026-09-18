extends "res://tests/test_full_game_flow.gd"
## Real scene replacement, not a detached preview node with mocked navigation.
func run():
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/title.tscn")
	assert(change_scene_to_file("res://scenes/experimental_full_game.tscn") == OK)
	await frames(5)
	app = current_scene
	assert(app.state == "menu")
	var previous = weakref(app)
	await click("OriginalGame")
	await frames(6)
	assert(previous.get_ref() == null, "preview owner is actually released")
	assert(current_scene.scene_file_path == "res://scenes/home.tscn", "return uses upstream home")
	assert(root.get_node("FrontendInput").scope() == "frontend")
	assert(root.get_node("Cursor").hand.visible)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.verification/v03/original-return.png")
	print("PASS: experimental OriginalGame return restores upstream frontend ownership")
	quit()
