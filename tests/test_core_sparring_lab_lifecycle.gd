extends "res://tests/test_core_ai_comparison_lab_ticks.gd"
func run():
	var lab = load("res://scenes/combat_lab.tscn").instantiate(); root.add_child(lab); lab.set_physics_process(false)
	for owner in ["human","repo_ai","sparring_easy","human"]:
		lab.set_paused(true)
		send(KEY_F,true); send(KEY_K,true); send(KEY_ENTER,true)
		var generation = lab.simulation.generation
		check(lab.set_p2_input_owner(owner), "owner sequence selects "+owner)
		check(lab.simulation.generation > generation and lab.paused, "owner reset remains paused "+owner)
		check(lab.repo_inputs._frames.is_empty() and lab.sparring_inputs._frames.is_empty(), "both owner caches clear "+owner)
		for id in [1,2]: check(lab.simulation.fighters[id].buffer.debug_pending().is_empty(), "queue cleared")
		var tick = lab.simulation.tick
		await physics_frame; lab._physics_process(1.0/60)
		check(lab.simulation.tick == tick, "pause freezes match")
		lab.step_once(); await physics_frame; lab._physics_process(1.0/60); lab._physics_process(1.0/60)
		check(lab.simulation.tick == tick+1, "single step only")
		check(not lab._selected_inputs()._frames[1].pressed.get("attack",false), "held P1 edge suppressed")
		if owner == "human": check(not lab._selected_inputs()._frames[2].pressed.get("attack",false), "held P2 edge suppressed")
		else: check(lab._selected_inputs()._frames[2].source_id == owner, "correct source, P2 keys ignored")
		for key in [KEY_F,KEY_K,KEY_ENTER]: send(key,false)
	lab.set_p2_input_owner("sparring_easy"); lab.start_stock_match(); lab.set_paused(false)
	for i in 50: await physics_frame; lab._physics_process(1.0/60)
	check(not lab.sparring_inputs._frames.is_empty(), "real cache prerequisite")
	var age: int = lab.sparring_inputs.ai.age
	lab.simulation.fighters[2].hitstop_left = 4
	await physics_frame; lab._physics_process(1.0/60)
	check(lab.sparring_inputs.ai.age == age, "P2 hitstop freezes Sparring observation/decision age")
	lab.actors[1].position = Vector3(0,-9,0)
	await physics_frame; lab._physics_process(1.0/60)
	check(lab.simulation.fighters[2].stocks == 2, "actual stock loss prerequisite")
	check(lab.sparring_inputs._frames.is_empty() and lab.repo_inputs._frames.is_empty(), "stock boundary clears both owners immediately")
	lab.rematch_lab()
	check(lab.sparring_inputs.enabled and lab.sparring_inputs.ai.sequence == 0 and lab.simulation.fighters[2].stocks == 3, "rematch preserves owner resets source")
	lab.free()
	if not failures: print("PASS: Sparring lab transitions held pause and stock lifecycle")
	quit(1 if failures else 0)
