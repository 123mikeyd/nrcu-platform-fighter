extends "res://tests/test_core_ai_comparison_lab_ticks.gd"
const StageOwner = preload("res://scripts/core/input/repo_ai_match_input.gd")
func run():
	var records := []
	for kit in ["turbofit","teknium"]:
		for side in [-1,1]:
			var lab = load("res://scenes/combat_lab.tscn").instantiate(); root.add_child(lab); lab.set_physics_process(false)
			lab.select_fighter(1,kit); lab.set_p2_repo_ai(true); lab.set_comparison_interaction("grounded_jostle"); lab.set_ai_difficulty("normal"); lab.start_stock_match()
			var geom = load("res://scripts/core/stage/combat_lab_stage.gd").new().geometry()[0]
			var owner = StageOwner.new(); owner.stage_bounds = {"left":geom.position.x-geom.size.x/2,"right":geom.position.x+geom.size.x/2,"top":geom.position.y+geom.size.y/2}
			lab.repo_inputs = owner
			var spawns: Dictionary = lab.simulation.rules.stage.spawns
			for id in spawns: spawns[id].x = absf(spawns[id].x)*side*(1 if id == 1 else -1)
			lab.simulation.rematch(); owner.reset()
			var quiet := 0; var longest := 0; var max_damage := 0.0; var previous := 0.0; var moves := {}; var boundary_ticks := 0
			for i in 1800:
				await physics_frame; lab._physics_process(1.0/60)
				var a = lab.actors[0]; var b = lab.actors[1]
				var damage: float = lab.simulation.fighters[1].percent
				var viable: bool = absf(a.position.x) < 11.8 and absf(a.position.y) < .1 and lab.simulation.fighters[1].enabled
				var boundary: bool = absf(a.position.x) > 9.5 and absf(b.position.x) > 7 and absf(b.position.x) < 8.6
				quiet = quiet+1 if viable and damage == previous and boundary else 0
				longest = maxi(longest,quiet); previous = damage; max_damage = maxf(max_damage,damage)
				if viable and boundary: boundary_ticks += 1
				if lab.simulation.fighters[2].move_id != "": moves[lab.simulation.fighters[2].move_id] = true
				if not lab.simulation.result.is_empty(): break
			var row = {"kit":kit,"side":side,"ticks":lab.simulation.tick,"max_damage":max_damage,"longest_boundary_quiet":longest,"boundary_ticks":boundary_ticks,"moves":moves.keys()}
			records.append(row); print("STAGE_LAB ",JSON.stringify(row))
			check(longest < 600,"no ten-second repeatable old-boundary oscillation "+kit+str(side))
			check(max_damage > 0,"actual damage remains possible "+kit+str(side))
			lab.free()
	var file = FileAccess.open("res://.verification/core/ai-stage-adaptation/lab-bouts.json",FileAccess.WRITE); file.store_string(JSON.stringify(records,"\t")); file.close()
	if not failures: print("PASS: repo AI adapted stage long native lab bouts")
	quit(1 if failures else 0)
