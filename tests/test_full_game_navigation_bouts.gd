extends "res://tests/test_core_stage_navigation_native.gd"
func run():
	for kind in ["sparring_easy","repo_easy","repo_normal","repo_hard"]:
		for character in ["teknium","turbofit"]:
			await bout(kind,character)
	if not failures: print("PASS: full session debug-layout fixture all owners upper pursuit then real damage")
	quit(1 if failures else 0)
func bout(kind: String, character: String):
	var session = load("res://scripts/experimental/full_game_session.gd").new()
	session.input_owner = kind; session.selected_fighters = ["teknium",character]
	root.add_child(session)
	# Preserve this upper-pursuit integration contract on the authored debug
	# fixture. Current upstream Toy Shelf deliberately has no upper supports.
	session.stage.free()
	session.stage = load("res://scripts/experimental/full_game_stage.gd").new()
	session.stage.layout_id = "debug"
	session.add_child(session.stage)
	session.simulation.configure_ledges(session.stage.anchors(),load("res://scripts/core/stage/ledge_policy.gd").new())
	session.reset_inputs()
	check(session.error.is_empty(),"production session ready")
	session.simulation.rules.stage.spawns = {1:Vector3(-1.4,6.25,0),2:Vector3(4,-0.01,0)}
	check(session.simulation.reset_with_collision_profiles({1:Vector3(-1.4,6.25,0),2:Vector3(4,-0.01,0)},{1:fitted("teknium"),2:fitted(character)},"grounded_jostle"),"initial actual upper fixture")
	session.reset_inputs()
	key(KEY_E,true)
	var arrived := false; var damaged := false; var before := 0.0
	var arrival_tick := -1; var damage_tick := -1; var jumps := 0; var min_air := 1
	for i in 1800:
		await physics_frame
		var bot = session.actors[1]
		min_air = mini(min_air,bot.runtime.air_jumps_left)
		if session.inputs._frames.get(2) != null and session.inputs._frames[2].pressed.get("jump",false): jumps += 1
		if not arrived and bot.runtime.grounded and session.inputs.navigation.support(bot.position)=="Platform3":
			arrived = true; arrival_tick = i; before = session.simulation.fighters[1].percent
			key(KEY_E,false)
		if arrived and session.simulation.fighters[1].percent > before:
			damaged = true
			if damage_tick < 0: damage_tick = i
		# Keep the real session alive well after the arrival/contact prerequisite.
		if i >= 900 and damaged: break
	print("SESSION ",kind," ",character," arrived=",arrived," arrival_tick=",arrival_tick," damage_after_arrival=",damaged," damage_tick=",damage_tick," damage=",session.simulation.fighters[1].percent," jumps=",jumps," min_air=",min_air," ticks=",session.simulation.tick)
	check(arrived,"production upper pursuit "+kind+" "+character)
	check(damaged,"production attack after arrival causes damage "+kind+" "+character)
	check(min_air>=0,"never negative jump resources")
	key(KEY_E,false); session.free()
