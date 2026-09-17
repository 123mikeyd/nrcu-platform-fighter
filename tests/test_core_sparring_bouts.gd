extends "res://tests/test_core_ai_comparison_lab_ticks.gd"
const OUT = "res://.verification/core/sparring-ai/"
func run():
	var rows := []
	var policies := ["repo_easy"]
	if "sparring" in OS.get_cmdline_user_args(): policies.append("sparring_easy")
	for kit in ["teknium","turbofit"]:
		for mode in ["grounded_jostle","legacy_solid"]:
			for policy in policies:
				var lab = load("res://scenes/combat_lab.tscn").instantiate(); root.add_child(lab); lab.set_physics_process(false)
				lab.select_fighter(0,kit); lab.select_fighter(1,kit); lab.set_p2_repo_ai(true); lab.set_comparison_interaction(mode); lab.set_ai_difficulty("easy"); lab.start_stock_match()
				if policy == "sparring_easy":
					lab.repo_inputs = load("res://scripts/core/input/sparring_match_input.gd").new()
					lab.repo_inputs.configure(2,true,"easy")
					lab.p2_input_button.set_item_text(1,"P2: Sparring / Easy (ours)")
					var help = lab.find_child("RosterHelp",true,false)
					help.text = help.text.replace("P2 Repo AI (Mikey adaptation)","P2 Sparring / Easy (ours, NOT Mikey AI)")
				lab.set_paused(false)
				var trace := []; var attacks := 0; var specials := 0; var idle := 0; var longest_idle := 0; var quiet := 0; var damage1 := 0.0; var damage2 := 0.0; var hits1 := 0; var hits2 := 0; var accepted := {}; var seen := {}; var p1_edges := 0; var openings := 0; var opening_hits := 0; var open_run := 0; var longest_open := 0
				for i in 1200:
					await physics_frame
					var a = lab.actors[0]; var b = lab.actors[1]
					# Simple practice: approach for 70/120 ticks; attack every second.
					# Only current positions, no bot decision/cooldown reads.
					var dx: float = b.position.x-a.position.x
					var approach: bool = i % 120 < 70 and absf(dx)>1.25 and absf(a.position.x)<10.5
					send(KEY_A,approach and dx<0); send(KEY_D,approach and dx>0)
					send(KEY_F,i%60==30)
					send(KEY_SPACE,a.position.y < -0.2 and i%30==0)
					var before1: float = lab.simulation.fighters[1].percent; var before2: float = lab.simulation.fighters[2].percent
					lab._physics_process(1.0/60)
					var f1: Dictionary = lab.simulation.fighters[1]; var f2: Dictionary = lab.simulation.fighters[2]
					var frames: Dictionary = lab.repo_inputs._frames
					var f = frames.get(2)
					if f == null: continue
					if frames[1].pressed.get("attack",false): p1_edges += 1
					if f.pressed.get("attack",false): attacks += 1
					if f.pressed.get("special",false): specials += 1
					var neutral: bool = f.axis == Vector2.ZERO and not f.held.values().has(true)
					if neutral: idle += 1
					var unlocked: bool = f2.ready_tick <= lab.simulation.tick and f2.hitstop_left<=0 and f2.caught_by==0 and f2.grab==null and b.telemetry().get("status","")=="normal"
					if f2.kit != null: unlocked = unlocked and not f2.kit.snapshot().get("action_locked",false)
					var opening: bool = neutral and unlocked and absf(a.position.x-b.position.x)<2.4 and absf(a.position.y-b.position.y)<0.8
					if opening: openings += 1
					if opening and f2.percent>before2: opening_hits += 1
					open_run = open_run+1 if opening else 0; longest_open = maxi(longest_open,open_run)
					quiet = quiet+1 if neutral else 0; longest_idle = maxi(longest_idle,quiet)
					if f1.percent > before1: damage1 += f1.percent-before1; hits1 += 1
					if f2.percent > before2: damage2 += f2.percent-before2; hits2 += 1
					if f2.move_id != "" and not seen.has(str(f2.activation_id)):
						seen[str(f2.activation_id)] = true; accepted[f2.move_id] = accepted.get(f2.move_id,0)+1
					trace.append({"tick":lab.simulation.tick,"p1":frames[1].to_dict(),"p2":f.to_dict(),"positions":[a.position,b.position],"damage":[f1.percent,f2.percent],"p2_move":f2.move_id,"p2_ready":f2.ready_tick,"p2_status":b.telemetry().get("status",""),"p2_hitstop":f2.hitstop_left,"opening":opening})
					if i == 300 and DisplayServer.get_name() != "headless":
						# The production _process refreshes repo-only help every render.
						# Freeze presentation for this diagnostic capture; no UI source edit.
						lab.set_process(false); lab._process(0.0)
						if policy == "sparring_easy":
							var help = lab.find_child("RosterHelp",true,false)
							help.text = help.text.replace("P2 Repo AI (Mikey adaptation)","P2 Sparring / Easy (ours)")
							check(not help.text.contains("Mikey adaptation"),"capture has no false Mikey attribution")
						await process_frame; await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png(OUT+kit+"-"+mode+"-"+policy+".png")
						lab.set_process(true)
					if not lab.simulation.result.is_empty(): break
				for key in [KEY_A,KEY_D,KEY_F,KEY_SPACE]: send(key,false)
				var row = {"kit":kit,"mode":mode,"policy":policy,"ticks":trace.size(),"p1_attack_edges":p1_edges,"attack_edges":attacks,"special_edges":specials,"neutral_ticks":idle,"longest_neutral":longest_idle,"p1_damage_received":damage1,"p2_damage_received":damage2,"p1_damage_events":hits1,"p2_damage_events":hits2,"accepted":accepted,"close_unlocked_neutral_ticks":openings,"longest_close_opening":longest_open,"opening_damage_events":opening_hits}
				rows.append(row); print("SPARRING_BOUT ",JSON.stringify(row))
				check(p1_edges>0,"parsed P1 basic inputs "+kit+mode+policy)
				check(damage2>0,"P1 deals actual damage "+kit+mode+policy)
				if policy == "sparring_easy": check(damage1>0,"sparring remains a useful damaging opponent "+kit+mode)
				var file = FileAccess.open(OUT+kit+"-"+mode+"-"+policy+"-trace.json",FileAccess.WRITE); file.store_string(JSON.stringify(trace)); file.close()
				lab.free()
	var file = FileAccess.open(OUT+("comparison-bouts.json" if policies.size()>1 else "baseline-bouts.json"),FileAccess.WRITE); file.store_string(JSON.stringify(rows,"\t")); file.close()
	if not failures: print("PASS: sparring native parsed-key practice bouts")
	quit(1 if failures else 0)
