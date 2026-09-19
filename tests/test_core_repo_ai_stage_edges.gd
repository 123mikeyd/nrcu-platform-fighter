extends "res://tests/test_core_top_support_lifecycle.gd"
const Owner = preload("res://scripts/core/input/repo_ai_match_input.gd")
func run():
	var records := []
	var geom = load("res://scripts/core/stage/combat_lab_stage.gd").new().geometry()[0]
	var bounds = {"left":geom.position.x-geom.size.x/2,"right":geom.position.x+geom.size.x/2,"top":geom.position.y+geom.size.y/2}
	for mode in ["grounded_jostle","legacy_solid"]:
		for kit in ["turbofit","teknium"]:
			for side in [-1,1]:
				var f = setup_pair(kit,"teknium",false,mode)
				f.floor.position = geom.position; f.floor.get_child(0).shape.size = geom.size
				f.m.configure_defense(load("res://scripts/core/combat/defense_profile.gd").new())
				f.m.configure_hitstop(load("res://scripts/core/combat/hitstop_profile.gd").new())
				# Legal reset anchors, no post-reset position/velocity edits.
				f.m.reset_with_collision_profiles({1:Vector3(side*11.0,0.02,0),2:Vector3(side*7.0,0.02,0)},{1:fitted("teknium"),2:fitted(kit)},mode)
				var owner = Owner.new(); owner.stage_bounds = bounds; owner.configure(2,true,"normal")
				var approached := false; var moves := {}; var longest := 0; var quiet := 0; var minimum := INF; var max_damage := 0.0
				for i in 1200:
					await physics_frame
					owner.advance(f.m)
					var gap: float = absf(f.a.position.x-f.b.position.x)
					minimum = minf(minimum,gap)
					approached = approached or (gap < 1.65 and side*f.b.position.x > 9)
					var move: String = f.m.fighters[2].move_id
					if move != "": moves[move] = true
					# A viable grounded target beyond the old boundary must not strand pursuit.
					var viable: bool = absf(f.a.position.x) < 11.8 and absf(f.a.position.y) < .1
					quiet = quiet+1 if viable and gap > 2.4 else 0
					longest = maxi(longest,quiet)
					max_damage = maxf(max_damage,f.m.fighters[1].percent)
				var row = {"kit":kit,"mode":mode,"side":side,"ticks":1200,"approached":approached,"moves":moves.keys(),"min_gap":minimum,"longest_viable_out_of_range":longest,"max_damage":max_damage}
				records.append(row); print("STAGE_BOUT ",JSON.stringify(row))
				check(approached,"approaches real edge target "+kit+mode+str(side))
				check(not moves.is_empty(),"accepted attack near real edge "+kit+mode+str(side))
				check(longest < 600,"no ten-second boundary pursuit stall "+kit+mode+str(side))
				dispose(f)
	DirAccess.make_dir_recursive_absolute("res://.verification/core/ai-stage-adaptation")
	var file = FileAccess.open("res://.verification/core/ai-stage-adaptation/edge-bouts.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t")); file.close()
	if not failures: print("PASS: repo AI stage edge native bouts")
	quit(1 if failures else 0)
