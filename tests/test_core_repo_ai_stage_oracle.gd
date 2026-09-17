extends "res://tests/test_core_repo_ai_oracle.gd"
func run():
	var a = LegacyObservation.new(); var b = LegacyObservation.new()
	root.add_child(a); root.add_child(b); a.add_to_group("fighters"); b.add_to_group("fighters")
	var comparisons := 0
	for kit in ["teknium","turbofit"]:
		for difficulty in ["easy","normal","hard"]:
			for position in [Vector3(0,0,0),Vector3(-8,0,0),Vector3(8,0,0),Vector3(-8.01,0,0),Vector3(8.01,0,0),Vector3(0,-.51,0)]:
				a.position = position; b.position = position+Vector3(1.8,0,0)
				a.character_id = kit; a.bot_difficulty = difficulty; b.attack_cooldown = .5
				var original = load("res://scripts/bot_controller.gd").new()
				var defaults = load("res://scripts/core/input/repo_ai_input_source.gd").new(); defaults.configure(difficulty)
				var explicit = load("res://scripts/core/input/repo_ai_input_source.gd").new(); explicit.configure(difficulty)
				var obs = {"id":2,"position":a.position,"velocity":a.velocity,"character_id":kit,"enabled":true,"team":-1,"attack_cooldown":0.0,"can_jump":true,"recovery_spent":false,"magic_locked":false,"magic_cooldown":0.0}
				var target = obs.duplicate(); target.id = 1; target.position = b.position; target.attack_cooldown = .5
				var bounded = obs.duplicate(true); bounded.stage_bounds = {"left":-8.0,"right":8.0,"top":0.0}
				for tick in 1000:
					var expected = original.read(a,1.0/60)
					check(defaults.read(obs,[target],1.0/60) == expected,"default original oracle")
					check(explicit.read(bounded,[target],1.0/60) == expected,"explicit original bounds oracle")
					comparisons += 2
	check(comparisons == 72000,"72000 comparisons executed")
	check(FileAccess.get_sha256("res://scripts/bot_controller.gd") == "43f56449e8c92d40cd892f442ad6fd86993c04b34981e4e1c2ecdeee8b1aa867","original bot unchanged")
	check(FileAccess.get_sha256("res://scripts/fighter.gd") == "9337a721d5ae9fd2a98e41d5f8a2d826006c906ec7da1b676228ef9bbae379ce","reviewed v0.2 fighter unchanged")
	a.free(); b.free()
	print("ORACLE_COMPARISONS ",comparisons)
	if not failures: print("PASS: repo AI 72000 default and original bounds oracle comparisons")
	quit(1 if failures else 0)
