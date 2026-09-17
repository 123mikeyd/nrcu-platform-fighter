extends "res://tests/test_full_game_flow.gd"
## Actual Toy Shelf bodies and real player sampler; no substitute floor.
func run():
	var session = load("res://scripts/experimental/full_game_session.gd").new()
	session.input_owner = "human"
	root.add_child(session)
	await frames(45)
	var actor = session.actors[0]
	assert(actor.runtime.grounded and absf(actor.position.y + 0.05) < 0.04)
	# Default spawn is directly beneath the authored left platform.
	key(KEY_SPACE,true)
	var crossed := false
	var landed := false
	for i in 100:
		if i == 16: key(KEY_SPACE,false)
		if i == 19: key(KEY_SPACE,true)
		await frames(1)
		crossed = crossed or actor.position.y > 3.3
		landed = landed or (actor.runtime.grounded and absf(actor.position.y - 3.225) < 0.04)
	key(KEY_SPACE,false)
	print("Toy Shelf ascending=",crossed," landed=",landed," foot=",actor.position)
	if not crossed or not landed:
		printerr("FAIL: actual left Toy Shelf platform must catch descent after underside ascent")
		session.free(); quit(1); return
	key(KEY_S,true)
	await frames(60)
	key(KEY_S,false)
	assert(actor.runtime.grounded and absf(actor.position.y + 0.05) < 0.04,"drop returns to actual main floor")
	key(KEY_S,true); await frames(12); key(KEY_S,false)
	assert(actor.runtime.grounded,"main floor cannot drop")
	session.free()
	await frames(2)
	print("PASS: full game real Toy Shelf ascent landing drop solid floor")
	quit()
