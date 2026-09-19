extends "res://tests/test_core_defense_match.gd"
func profile(character: String):
	return load("res://data/collision/generated/"+character+".tres").merged_with(load("res://data/collision/overrides/"+character+"_anatomical_v1.tres")).profile
func run():
	var floor = floor_body(); var p = DefenseProfile.new(); p.shield_drain = 0; p.shield_regen = 0
	var m = setup_match(p)
	for character in ["teknium","turbofit"]:
		m.configure_actor_kit(1,character); m.configure_actor_kit(2,character)
		check(m.reset_with_collision_profiles({1:Vector3(0,.01,0),2:Vector3(1.1,.01,0)},{1:profile(character),2:profile(character)}),"merged shield scenario")
		m.fighters[2].facing = -1
		await settle(m)
		await tick(m,{1:frame(true,1),2:shield(true)})
		var blocks := 0
		for age in 35:
			await tick(m,{2:shield()})
			blocks += m.events.size()
		check(blocks == 1 and m.fighters[2].percent == 0 and m.defense_telemetry(2).shield_health < 100,"delayed physical contact spends shield once "+character)
		m.reset({1:Vector3(0,.01,0),2:Vector3(1.1,.01,0)})
		m.fighters[2].facing = -1; await settle(m)
		await tick(m,{1:frame(true,1),2:frame(true,-1)})
		var traded := false
		for age in 35:
			await tick(m)
			if m.events.size() == 2:
				traded = true
				for event in m.events: check(event.contact_evidence.pose_revision == m.collision_telemetry(event.victim).contact_snapshot.pose_revision,"trade frozen recipient pose")
		check(traded and m.fighters[1].percent > 0 and m.fighters[2].percent > 0,"delayed same-snapshot trade "+character)
	cleanup(m); floor.free()
	if not failures: print("PASS: melee defense and trades (%d checks)" % checks)
	quit(1 if failures else 0)
