extends "res://tests/test_full_game_flow.gd"
func run():
	var session = load("res://scripts/experimental/full_game_session.gd").new()
	session.input_owner = "human"
	root.add_child(session)
	await frames(40)
	key(KEY_D,true); key(KEY_G,true)
	await frames(2)
	key(KEY_D,false); key(KEY_G,false)
	var seen := false
	for i in 65:
		await frames(1)
		for shot in session.simulation.projectile_telemetry():
			seen = true
			if session.get("effects") == null:
				print("FAIL: committed match projectile has no frontend visual")
				session.free(); quit(1); return
			assert(session.effects.visuals.has(shot.activation_id))
			var mesh = session.effects.visuals[shot.activation_id]
			assert(mesh is MeshInstance3D and mesh.global_position.is_equal_approx(shot.position))
	assert(seen,"real special emitted a projectile")
	session.rematch()
	assert(session.effects.visuals.is_empty(),"rematch clears effects")
	session.free()
	await frames(2)
	print("PASS: full game committed projectile presentation and rematch cleanup")
	quit()
