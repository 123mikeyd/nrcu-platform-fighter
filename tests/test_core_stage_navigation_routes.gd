extends "res://tests/test_core_stage_navigation_native.gd"
var trace_route := false
func run():
	for kind in ["repo_easy","sparring_easy"]:
		for id in ["teknium","turbofit"]:
			for mode in ["grounded_jostle","legacy_solid"]:
				for trip in ["main_left","main_top","left_top","left_right","left_main","top_main"]:
					await journey(kind,id,mode,trip)
	if not failures: print("PASS: both owners characters interaction modes actual four-platform routes")
	quit(1 if failures else 0)
func journey(kind: String,id: String,mode: String,trip: String):
	var stage = load("res://scripts/experimental/full_game_stage.gd").new()
	# v0.2 Toy Shelf is flat; retain multi-support policy coverage on the
	# unchanged authored debug layout, not invisible Toy Shelf geometry.
	stage.layout_id = "debug"
	root.add_child(stage)
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"teknium"); m.register_actor(2,b,-1,id)
	m.configure_defense(load("res://scripts/core/combat/defense_profile.gd").new())
	var cases := {
		"main_left":[Vector3(-7,3.3,0),Vector3(-4,-0.01,0),"Platform1"],
		"main_top":[Vector3(-1.4,6.25,0),Vector3(4,-0.01,0),"Platform3"],
		"left_top":[Vector3(1.4,6.25,0),Vector3(-5.2,3.3,0),"Platform3"],
		"left_right":[Vector3(6.7,3.3,0),Vector3(-5.2,3.3,0),"Platform2"],
		"left_main":[Vector3(0,0,0),Vector3(-5.2,3.3,0),"MainPlatform"],
		"top_main":[Vector3(6,0,0),Vector3(0,6.25,0),"MainPlatform"]}
	var c: Array = cases[trip]
	check(m.reset_with_collision_profiles({1:c[0],2:c[1]},{1:fitted("teknium"),2:fitted(id)},mode),"native mode installed")
	var owner = load("res://scripts/core/input/sparring_match_input.gd" if kind == "sparring_easy" else "res://scripts/core/input/repo_ai_match_input.gd").new()
	owner.configure(2,true,"easy" if kind=="sparring_easy" else kind.trim_prefix("repo_")); owner.stage_bounds=stage.ai_bounds()
	check(owner.configure_navigation(geometry(stage)),"geometry accepted")
	var human = Source.new()
	# Parsed human shield keeps the observation target on its authored support;
	# real finite defense, no invulnerability or terrain override.
	key(KEY_A,false); key(KEY_SPACE,false); key(KEY_E,true)
	var landed := false; var jumped := 0; var dropped := 0; var used_top := false
	var ticks := 0
	for i in 850:
		await physics_frame
		var frames = owner.sample_all(m,{1:human.sample(m.tick)})
		if frames[2].pressed.get("jump",false): jumped += 1
		if frames[2].pressed.get("down",false): dropped += 1
		var copy = owner.sample_all(m)
		check(copy[2].to_dict() == frames[2].to_dict(),"same tick cached input")
		m.simulate(frames); ticks += 1
		if trace_route and i % 10 == 0: print("TRACE ",i," ",b.position," v=",b.velocity," air=",b.runtime.air_jumps_left," leg=",owner.navigation._leg," held=",frames[2].held," target=",a.position," goal=",owner.navigation._goal)
		var support: String = owner.navigation.support(b.position)
		used_top = used_top or (b.runtime.grounded and support == "Platform3")
		if b.runtime.grounded and support == c[2]: landed = true; break
	print("ROUTE ",kind," ",id," ",mode," ",trip," landed=",landed," jumps=",jumped," drops=",dropped," ticks=",ticks," foot=",b.position," leg=",owner.navigation._leg)
	check(landed,"real Toy Shelf route "+kind+" "+id+" "+mode+" "+trip)
	if trip == "left_right": check(used_top,"different upper uses real intermediate top landing")
	if trip.ends_with("main"): check(dropped>0 and jumped==0,"legal downward edge, no jump spam")
	if trip == "main_left": check(jumped==2 if kind.ends_with("easy") else jumped<=6,"bounded ground and air jump attempts")
	key(KEY_E,false); human.reset()
	if Input.joy_connection_changed.is_connected(human._on_joy_connection_changed): Input.joy_connection_changed.disconnect(human._on_joy_connection_changed)
	a.free(); b.free(); stage.free()
