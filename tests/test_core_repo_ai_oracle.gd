extends "res://tests/test_core_repo_ai.gd"
class LegacyObservation extends Node3D:
	var bot_difficulty := "normal"
	var character_id := "turbofit"
	var prototype_fire := false
	var velocity := Vector3.ZERO
	var jumps_used := 0
	var recovery_spent := false
	var attack_cooldown := 0.0
	var teknium_magic := {"cooldown":0.0}
	var facing := 1.0
	func can_hit(other): return other != self
	func magic_locked(): return false
func run():
	check(FileAccess.get_sha256("res://scripts/bot_controller.gd") == "43f56449e8c92d40cd892f442ad6fd86993c04b34981e4e1c2ecdeee8b1aa867","original bot byte identity")
	# v0.3 adds tumble/source attribution and paired Mephisto; bot read() is unchanged.
	# Keep the actual supported-decision oracle below, not just a new source pin.
	check(FileAccess.get_sha256("res://scripts/fighter.gd") == "62584642a3905d3811e9970b179b1fd5348f1a47238fa09cd9f8028ff3fdb9dd","reviewed v0.3 fighter byte identity (decision oracle remains the unchanged bot)")
	var a = LegacyObservation.new(); var b = LegacyObservation.new()
	root.add_child(a); root.add_child(b); a.add_to_group("fighters"); b.add_to_group("fighters")
	var coverage := {}
	for kit in ["teknium","turbofit"]:
		for difficulty in ["easy","normal","hard"]:
			for geometry in [Vector3(4,0,0),Vector3(1.3,0,0),Vector3(1,2,0),Vector3(1,-1,0),Vector3(10,0,0)]:
				a.position = Vector3.ZERO; b.position = geometry
				if geometry.x == 10: a.position = Vector3(9,-1,0); b.position = Vector3.ZERO
				a.character_id = kit; a.bot_difficulty = difficulty; b.attack_cooldown = .5
				var original = load("res://scripts/bot_controller.gd").new()
				var derived = load("res://scripts/core/input/repo_ai_input_source.gd").new(); derived.configure(difficulty)
				var same = load("res://scripts/core/input/repo_ai_input_source.gd").new(); same.configure(difficulty)
				var obs = {"id":2,"position":a.position,"velocity":a.velocity,"character_id":kit,"enabled":true,"team":-1,"attack_cooldown":0.0,"can_jump":true,"recovery_spent":false,"magic_locked":false,"magic_cooldown":0.0}
				var target = obs.duplicate(); target.id = 1; target.position = b.position; target.attack_cooldown = .5
				for i in 200:
					var expected = original.read(a,1.0/60.0)
					var actual = derived.read(obs,[target],1.0/60.0)
					check(actual == expected,"original supported decision oracle "+kit+" "+difficulty+" "+str(geometry)+" tick "+str(i))
					check(actual == same.read(obs,[target],1.0/60.0),"same observations have same decisions independent of collision mode/no seed")
					for action in ["jump","attack","special","shield"]:
						if actual[action]: coverage[action] = true
	for action in ["jump","attack","special","shield"]: check(coverage.has(action),"oracle exercises "+action)
	a.free(); b.free()
	if not failures: print("PASS: original repo AI supported decision oracle and source preservation")
	quit(1 if failures else 0)
