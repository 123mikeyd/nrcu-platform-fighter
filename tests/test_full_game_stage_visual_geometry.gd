extends "res://tests/test_full_game_flow.gd"
## Regression: old traversal asserted collider heights, never visible geometry.
## This checks the current upstream layout against actual native supports/art.
var failures := 0
func _initialize():
	if "--compact" in OS.get_cmdline_user_args():
		root.size = Vector2i(960,540)
		root.content_scale_size = Vector2i(960,540)
	call_deferred("run")
func check(ok: bool, message: String):
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures += 1
func capture(label):
	if DisplayServer.get_name() == "headless": return
	var running: bool = app.session.is_physics_processing()
	app.session.set_physics_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var prefix := "red" if "--red" in OS.get_cmdline_user_args() else "green"
	if "--compact" in OS.get_cmdline_user_args(): prefix += "-960"
	root.get_texture().get_image().save_png("res://.verification/core/stage-visual-fix/"+prefix+"-"+label+".png")
	app.session.set_physics_process(running)
func run():
	app = load("res://scenes/experimental_full_game.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	await click("ExperimentalPlay")
	var help_text := ""
	for label in app.find_children("*","Label",true,false): help_text += label.text
	check(not help_text.contains("original four platforms") and not help_text.contains("Down drops through upper platforms"),"selection help does not advertise removed Toy Shelf platforms")
	app.input_owner = "human"
	await click("StartMatch")
	await frames(130)
	var stage = app.session.stage
	var authored: Array = load("res://scripts/stage_layouts.gd").surfaces("toy_room")
	var actual: Array = stage.navigation_surfaces()
	check(actual.size() == authored.size(), "no invisible obsolete upper supports: current Toy Shelf has one authored floor")
	for i in mini(actual.size(), authored.size()):
		var p: Vector3 = authored[i][0]
		var size: Vector3 = authored[i][1]
		check(absf(actual[i].rect.position.x - (p.x-size.x/2)) < 0.001, "LEFT actual support ends at visible authored edge")
		check(absf(actual[i].rect.end.x - (p.x+size.x/2)) < 0.001, "RIGHT actual support ends at visible authored edge")
		var visible_matches := 0
		for mesh in stage.find_children("*","MeshInstance3D",true,false):
			if not mesh.is_visible_in_tree() or not mesh.mesh is BoxMesh: continue
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			if bounds.position.is_equal_approx(p-size/2) and bounds.size.is_equal_approx(size):
				visible_matches += 1
				var camera: Camera3D = stage.get_viewport().get_camera_3d()
				check(camera != null and (camera.cull_mask & mesh.layers) != 0,"authored surface is on actual camera render layer")
				for corner in 8:
					var pixel := camera.unproject_position(bounds.get_endpoint(corner))
					var viewport_size := camera.get_viewport().get_visible_rect().size
					check(Rect2(Vector2(8,65),Vector2(viewport_size.x-16,viewport_size.y-190)).has_point(pixel),"complete authored floor corner visible between HUD panels")
		check(visible_matches == 1,"exactly one visible full-size authored surface mesh matches collider")
	await capture("floor")
	# Both real player samplers double-jump. Previously they landed on invisible
	# side platforms at 3.225 rather than returning to the rendered shelf.
	key(KEY_SPACE,true); key(KEY_ENTER,true); await frames(16)
	key(KEY_SPACE,false); key(KEY_ENTER,false); await frames(3)
	key(KEY_SPACE,true); key(KEY_ENTER,true); await frames(80)
	key(KEY_SPACE,false); key(KEY_ENTER,false)
	for slot in 2:
		var actor = app.session.actors[slot]
		check(actor.runtime.grounded and absf(actor.position.y+0.05)<0.04,"kit %d double jump lands on VISIBLE floor, not ghost platform" % slot)
	await capture("double-jump-land")
	app.free(); await frames(3)
	if failures == 0: print("PASS: authored Toy Shelf visual/native support parity")
	quit(1 if failures else 0)
