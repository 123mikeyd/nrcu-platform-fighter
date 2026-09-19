extends "res://tests/test_core_stage_navigation.gd"
func run():
	var owner = load("res://scripts/core/input/repo_ai_match_input.gd").new()
	check(owner.configure_navigation(surfaces()),"valid wrapper opt-in")
	owner.ai.read({"position":Vector3.ZERO},[],1.0/60)
	var sequence: int = owner.ai.sequence
	check(sequence==1,"source sampled prerequisite")
	check(owner.configure_navigation(surfaces()) and owner.ai.sequence==sequence,"unchanged geometry refresh before sampling does not reset reaction state")
	var bad := surfaces(); bad[0].rect=Rect2(0,0,0,1)
	check(not owner.configure_navigation(bad) and owner.ai.sequence==sequence,"malformed geometry rejected atomically")
	var supplied := surfaces(); owner.configure_navigation(supplied); supplied[0].id="changed"
	check(owner._navigation_surfaces[0].id=="main","wrapper deep copies surfaces")
	check(owner.configure_navigation([]) and owner._navigation_surfaces.is_empty(),"explicit opt-out")
	var nav = load("res://scripts/core/input/stage_navigation.gd").new()
	for malformed in [{}, {"full_jump_speed":NAN}, {"full_jump_speed":true}]:
		check(not nav.configure(surfaces(),malformed),"malformed capabilities refused")
	var budget := caps(); budget.air_jumps=2
	check(not nav.configure(surfaces(),budget),"unsupported authored budget not invented")
	if not failures: print("PASS: wrapper geometry refresh copy validation and opt-out")
	quit(1 if failures else 0)
