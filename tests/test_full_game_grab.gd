extends "res://tests/test_full_game_flow.gd"
func run():
	var session = load("res://scripts/experimental/full_game_session.gd").new()
	session.input_owner = "human"
	session.selected_fighters = ["teknium","teknium"]
	root.add_child(session); await frames(45)
	key(KEY_D,true); key(KEY_LEFT,true)
	for i in 80:
		await frames(1)
		if session.actors[1].position.x-session.actors[0].position.x < 2.7: break
	key(KEY_D,false); key(KEY_LEFT,false)
	await frames(18)
	print("GRAB actual approach distance=",session.actors[1].position.x-session.actors[0].position.x)
	key(KEY_G,true); await frames(2); key(KEY_G,false)
	var caught := false
	for i in 35:
		await frames(1)
		var f: Dictionary = session.simulation.fighters[1]
		if f.grab != null and f.grab.phase == "hold" and f.grab.victim == 2:
			caught = true
			if session.get("grab_effects") == null:
				printerr("FAIL: committed full-game grab hold has no visible arcs")
				session.free(); quit(1); return
			assert(session.grab_effects.visuals.has(f.grab.activation_id))
			var mesh = session.grab_effects.visuals[f.grab.activation_id]
			assert(mesh.visible and mesh.mesh.get_surface_count() > 0)
			var previous_mesh = mesh.mesh
			session.set_paused(true); await frames(4)
			assert(mesh.mesh == previous_mesh,"paused committed arc clock")
			var committed = [session.simulation.tick,session.actors[0].position,session.actors[1].position,session.simulation.fighters[2].percent]
			session.grab_effects.visible = false
			session.present()
			session.grab_effects.visible = true
			session.present()
			assert(committed == [session.simulation.tick,session.actors[0].position,session.actors[1].position,session.simulation.fighters[2].percent],"visual toggling cannot advance gameplay")
			if DisplayServer.get_name() != "headless":
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://.verification/core/full-game-stage-acceptance/grab-hold.png")
			session.simulation.cancel_action(1,"test release")
			session.present()
			assert(session.grab_effects.visuals.is_empty(),"same-tick relation release removes arcs")
			break
	assert(caught,"real approach and neutral G must capture before checking effects")
	session.rematch()
	assert(session.grab_effects.visuals.is_empty())
	session.free(); await frames(2)
	print("PASS: full game real grab visible committed arcs pause release rematch")
	quit()
