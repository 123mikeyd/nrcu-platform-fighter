extends "res://tests/test_core_ai_comparison_lab_ticks.gd"
func run():
	var path := "res://scripts/core/input/sparring_match_input.gd"
	check(FileAccess.file_exists(path),"isolated P2-only sparring wrapper exists")
	if failures: quit(1); return
	var owner = load(path).new()
	check(not owner.configure(1,true,"easy") and not owner.configure(2,true,"hard"),"P2 easy only, no mislabeled Mikey difficulty")
	check(owner.configure(2,true,"easy"),"explicit easy configuration")
	var lab = load("res://scenes/combat_lab.tscn").instantiate(); root.add_child(lab); lab.set_physics_process(false)
	lab.set_p2_repo_ai(true); lab.start_stock_match(); lab.repo_inputs=owner; lab.set_paused(false)
	for i in 60: await physics_frame; lab._physics_process(1.0/60)
	check(owner.ai.age>24 and owner._frames[2].source_id=="sparring_easy","real lab ownership and distinct provenance")
	var tick: int = lab.simulation.tick; var age: int = owner.ai.age
	lab.set_paused(true)
	for i in 4: await physics_frame; lab._physics_process(1.0/60)
	check(lab.simulation.tick==tick and owner.ai.age==age,"pause freezes native match/source")
	lab.step_once(); await physics_frame; lab._physics_process(1.0/60); lab._physics_process(1.0/60)
	check(lab.simulation.tick==tick+1,"single step commits only once")
	lab.reset_lab(); check(owner.ai.age==0,"reset clears delayed observation history")
	lab.set_paused(false); await physics_frame; lab._physics_process(1.0/60)
	check(owner.ai.age==1 and owner._frames[2].pressed.is_empty(),"reset no stale attack edge")
	var f: Dictionary = lab.simulation.fighters[2]; f.hitstop_left=8; age=owner.ai.age
	await physics_frame; lab._physics_process(1.0/60)
	check(owner.ai.age==age,"actual P2 hitstop freezes AI clock")
	f.stocks-=1; await physics_frame; lab._physics_process(1.0/60)
	check(owner.ai.age==0,"stock identity drops stale history even while stopped")
	owner.configure(2,false,"easy"); await physics_frame
	send(KEY_K,true); lab._physics_process(1.0/60); send(KEY_K,false)
	check(owner._frames[2].source_id!="sparring_easy","disabled wrapper leaves human P2 source")
	lab.free()
	if not failures: print("PASS: sparring P2 wrapper native ownership lifecycle and pause")
	quit(1 if failures else 0)
