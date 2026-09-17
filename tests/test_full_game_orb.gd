extends "res://tests/test_full_game_flow.gd"
func run():
	var session = load("res://scripts/experimental/full_game_session.gd").new()
	session.input_owner = "human"
	root.add_child(session)
	await frames(40)
	key(KEY_DOWN,true); key(KEY_L,true)
	await frames(2)
	key(KEY_DOWN,false); key(KEY_L,false)
	var special: Dictionary = session.simulation.kit_telemetry(2).special
	assert(special.move == "sound_orb" and special.phase == "active")
	if not session.effects.visuals.has(special.activation_id):
		print("FAIL: active Turbofit orb is invisible in frontend")
		session.free(); quit(1); return
	var visual = session.effects.visuals[special.activation_id]
	assert(visual.global_position.is_equal_approx(session.actors[1].global_position + Vector3.UP))
	session.set_paused(true)
	await frames(10)
	assert(is_instance_valid(visual))
	session.rematch()
	assert(session.effects.visuals.is_empty())
	session.free()
	await frames(2)
	print("PASS: full game attached orb visibility pause and reset")
	quit()
