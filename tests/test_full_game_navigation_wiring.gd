extends "res://tests/test_core_stage_navigation_native.gd"
func run():
	var session = load("res://scripts/experimental/full_game_session.gd").new()
	root.add_child(session); session.set_physics_process(false)
	check(session.error.is_empty(),"session initializes")
	check(session.inputs._navigation_surfaces.size()==4,"production session configures all four support surfaces")
	check(session.stage.has_method("navigation_surfaces"),"stage owns actual geometry extraction")
	if not session.stage.has_method("navigation_surfaces"):
		session.free(); quit(1); return
	var expected := geometry(session.stage)
	check(session.inputs._navigation_surfaces==expected,"same authored geometry rather than constants")
	var shape = session.stage.get_node("Platform1").get_child(0)
	shape.position.x += 0.2
	session.reset_inputs()
	check(session.inputs._navigation_surfaces==geometry(session.stage),"reset refreshes actual geometry")
	var before: int = session.simulation.tick
	shape.rotation.z = 0.2
	await physics_frame; session._physics_process(1.0/60)
	check(session.simulation.tick==before and not session.error.is_empty(),"invalid rotated support fails clearly before any sampling")
	check(session.get_node_or_null("NavigationError/Message") != null,"runtime geometry refusal is visible, not a silent stopped match")
	shape.rotation.z = 0
	session.reset_inputs()
	check(session.error.is_empty(),"valid reset restores navigation")
	var surfaces: Array = session.inputs._navigation_surfaces.duplicate(true)
	for mode in ["legacy_solid","grounded_jostle"]:
		check(session.simulation.reset_with_collision_profiles({1:Vector3(-3,0,0),2:Vector3(3,0,0)},{1:fitted("teknium"),2:fitted("turbofit")},mode),"arm installs")
		session.reset_inputs()
		check(session.inputs._navigation_surfaces==surfaces,"both arms receive identical support geometry")
	session.free()
	if not failures: print("PASS: fullgame navigation geometry reset arms and fail-clear sampling")
	quit(1 if failures else 0)
