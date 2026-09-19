extends "res://tests/test_core_recovery_acceptance.gd"
## Independent counterfactual: null recipient opts out only via atomic full batch.
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b)
	var profiles = {1:load("res://data/collision/generated/turbofit.tres"),2:load("res://data/collision/generated/teknium.tres")}
	var spawns = {1:Vector3(0,20,0),2:Vector3(4,20,0)}
	check(m.reset_with_collision_profiles(spawns,profiles),"full generated prerequisite")
	await step(m)
	var generation = m.generation
	var prior = m.collision_telemetry(2)
	check(not m.reset_with_collision_profiles(spawns,{2:null}),"active partial null remains illegal")
	check(m.generation == generation and m.collision_telemetry(2) == prior and m.fighter_interaction_mode == "grounded_jostle","partial refusal leaves authority untouched")
	check(m.reset_with_collision_profiles(spawns,{1:profiles[1],2:null}),"independent complete opt-out positive control")
	await step(m)
	check(m.collision_telemetry(1).ok and m.collision_telemetry(1).geometry_mode == "generated_hurtboxes","retained recipient really generated")
	check(m.collision_telemetry(2).geometry_mode == "legacy_body_capsule" and m.fighter_interaction_mode == "legacy_solid","only opted-out recipient legacy and symmetric body mode")
	a.free(); b.free()
	if not failures: print("PASS: independent full-batch generated recipient opt-out control")
	quit(1 if failures else 0)
