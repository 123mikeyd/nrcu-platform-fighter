extends "res://tests/test_core_ai_comparison_lab_ticks.gd"
const RepoAI = preload("res://scripts/core/input/repo_ai_input_source.gd")
func run():
	var rows := []
	for kit in ["teknium","turbofit"]:
		for difficulty in ["easy","normal","hard"]:
			for distance in [1.3,2.0,4.0]:
				var ai = RepoAI.new(); ai.configure(difficulty)
				var own = {"id":2,"position":Vector3.ZERO,"velocity":Vector3.ZERO,"team":-1,"enabled":true,"character_id":kit,"can_jump":true,"recovery_spent":false,"magic_locked":false,"magic_cooldown":0.0,"attack_cooldown":0.0,"facing":1.0}
				var target = own.duplicate(); target.id = 1; target.position = Vector3(distance,0,0); target.attack_cooldown = .5
				var decisions := []; var basic := []; var special := []; var shield := []; var movement := 0
				var seq := 0
				for tick in 1800:
					var f = ai.sample(tick,own,[target])
					if ai.sequence != seq: decisions.append(tick); seq = ai.sequence
					if f.pressed.get("attack",false): basic.append(tick)
					if f.pressed.get("special",false): special.append(tick)
					if f.pressed.get("shield",false): shield.append(tick)
					if f.axis.x != 0: movement += 1
				rows.append({"kit":kit,"difficulty":difficulty,"distance":distance,"decision_ticks":decisions,"basic_edges":basic,"special_edges":special,"shield_edges":shield,"movement_ticks":movement})
	DirAccess.make_dir_recursive_absolute("res://.verification/core/sparring-ai")
	var file = FileAccess.open("res://.verification/core/sparring-ai/repo-static.json",FileAccess.WRITE); file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("PASS: repo difficulty static pressure characterization")
	quit(0)
