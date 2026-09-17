extends "res://tests/test_full_game_stage_visual_geometry.gd"
## Real PlayerInputSource + Match. Toy Shelf is solid/flat in v0.2.
## Keep one-way capability tested separately on the authored debug layout;
## never install unseen old platforms in the production Toy Shelf.
func run():
	for layout in ["toy_room","debug"]:
		var session = load("res://scripts/experimental/full_game_session.gd").new()
		session.input_owner = "human"
		root.add_child(session)
		if layout == "debug":
			session.stage.free()
			session.stage = load("res://scripts/experimental/full_game_stage.gd").new()
			session.stage.layout_id = "debug"
			session.add_child(session.stage)
			session.simulation.configure_ledges(session.stage.anchors(),load("res://scripts/core/stage/ledge_policy.gd").new())
			session.reset_inputs()
		await frames(45)
		for actor in session.actors:
			check(actor.runtime.grounded and absf(actor.position.y+0.05)<0.04,layout+" real initial main-floor support")
		key(KEY_SPACE,true); key(KEY_ENTER,true)
		var crossed := [false,false]
		for i in 100:
			if i == 16: key(KEY_SPACE,false); key(KEY_ENTER,false)
			if i == 19: key(KEY_SPACE,true); key(KEY_ENTER,true)
			await frames(1)
			for slot in 2: crossed[slot] = crossed[slot] or session.actors[slot].position.y > 3.3
		key(KEY_SPACE,false); key(KEY_ENTER,false)
		for slot in 2:
			var actor = session.actors[slot]
			var top := 3.225 if layout == "debug" else -0.05
			check(crossed[slot],"kit %d %s accepted double jump clears upper height" % [slot,layout])
			check(actor.runtime.grounded and absf(actor.position.y-top)<0.04,"kit %d %s lands on actual support" % [slot,layout])
		key(KEY_S,true); key(KEY_DOWN,true); await frames(60)
		key(KEY_S,false); key(KEY_DOWN,false)
		for slot in 2:
			var actor = session.actors[slot]
			check(actor.runtime.grounded and absf(actor.position.y+0.05)<0.04,"kit %d %s one-way drop (debug) / solid refusal (Toy Shelf)" % [slot,layout])
		session.free(); await frames(2)
	if not failures: print("PASS: both kits current solid Toy Shelf and separate authored one-way fixture")
	quit(1 if failures else 0)
