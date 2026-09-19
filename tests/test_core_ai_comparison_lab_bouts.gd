extends "res://tests/test_core_ai_comparison_lab_ticks.gd"
func run():
	var evidence: Array = []
	for kit in ["teknium","turbofit"]:
		for mode in ["grounded_jostle","legacy_solid"]:
			for difficulty in ["easy","normal","hard"]:
				var lab = load("res://scenes/combat_lab.tscn").instantiate(); root.add_child(lab); lab.set_physics_process(false)
				lab.select_fighter(1,kit); lab.set_p2_repo_ai(true); lab.set_comparison_interaction(mode); lab.set_ai_difficulty(difficulty); lab.start_stock_match()
				var max_damage := 0.0; var travel := 0.0; var last_x: float = lab.actors[1].position.x
				var attacks := {}; var longest_quiet := 0; var quiet := 0; var previous_damage := 0.0
				for i in 1800:
					await physics_frame
					lab._physics_process(1.0/60)
					var f: Dictionary = lab.simulation.fighters[2]
					var damage: float = lab.simulation.fighters[1].percent
					max_damage = maxf(max_damage,damage)
					quiet = quiet + 1 if damage == previous_damage else 0; longest_quiet = maxi(longest_quiet,quiet); previous_damage = damage
					travel += absf(lab.actors[1].position.x-last_x); last_x = lab.actors[1].position.x
					if f.move_id != "": attacks[f.move_id] = true
					if not lab.simulation.result.is_empty(): break
				var record := {"kit":kit,"mode":mode,"difficulty":difficulty,"ticks":lab.simulation.tick,"max_p1_damage":max_damage,"ai_travel":travel,"moves":attacks.keys(),"longest_no_damage_ticks":longest_quiet,"stall_flag_10s":longest_quiet >= 600,"p1_stocks":lab.simulation.fighters[1].stocks,"result":lab.simulation.result}
				evidence.append(record); print("AI_LAB_BOUT ",JSON.stringify(record))
				check(max_damage > 0 and travel > 1 and not attacks.is_empty(),"native lab AI attacks and damages "+kit+" "+mode+" "+difficulty)
				lab.free()
	DirAccess.make_dir_recursive_absolute("res://.verification/core/ai-comparison-lab")
	var file = FileAccess.open("res://.verification/core/ai-comparison-lab/bouts.json",FileAccess.WRITE); file.store_string(JSON.stringify(evidence,"\t")); file.close()
	if not failures: print("PASS: AI comparison lab twelve 30-second native bouts")
	quit(1 if failures else 0)
