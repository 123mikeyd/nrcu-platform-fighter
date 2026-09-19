extends "res://tests/test_core_defense_match.gd"
func run():
	var floor = floor_body(); var p = DefenseProfile.new(); p.shield_drain = 0; p.shield_regen = 0
	var m = setup_match(p)
	for character in ["teknium","turbofit"]:
		check(m.reset_with_collision_profiles({1:Vector3(0,.01,0),2:Vector3(1.1,.01,0)},{1:load("res://data/collision/generated/teknium.tres"),2:load("res://data/collision/generated/"+character+".tres")}),"actual generated defense setup")
		await settle(m)
		check(m.fighters[2].actor.runtime.grounded,"actual floor shield prerequisite")
		await tick(m,{1:frame(true,1),2:shield(true)})
		check(not m.fighters[1].activation_id.is_empty(),"shield test real input activation")
		check(m.events.is_empty() and m.defense_telemetry(2).shield_health == 100,"shield startup inactive")
		var blocks := 0
		for age in range(1,12):
			await tick(m,{2:shield()})
			for event in m.events:
				blocks += 1
				check(age >= 9 and event.contact_evidence.has("attack_shape"),"blocked real active hand")
				check(event.get("geometry_mode","") == "generated_hurtboxes","blocked hand retains generated evidence")
		check(blocks == 1,"shield spends once per activation")
		check(m.fighters[2].percent == 0 and m.defense_telemetry(2).shield_health < 100,"Teknium generated hand spends shield not damage "+character)
		# Each contender must independently reach/damage at this legal placement;
		# neither an empty trade nor shield immunity can satisfy the controls.
		m.configure_actor_kit(2,character)
		for attacker in [1,2]:
			m.reset({1:Vector3(0,.01,0),2:Vector3(1.1,.01,0)})
			m.fighters[2].facing = -1; await settle(m)
			await tick(m,{attacker:frame(true,1 if attacker == 1 else -1)})
			check(not m.fighters[attacker].activation_id.is_empty(),"independent contender accepted")
			var control_hits := 0
			var last := 18 if attacker == 2 and character == "turbofit" else 11
			for age in range(1,last+1):
				await tick(m)
				for event in m.events:
					if event.source == attacker:
						control_hits += 1
						check(event.contact_evidence.has("attack_shape"),"independent contender real source geometry")
			check(control_hits == 1 and m.fighters[3-attacker].percent == (14 if attacker == 2 and character == "turbofit" else 8),"independent contender damages once "+character+str(attacker))
		m.reset({1:Vector3(0,.01,0),2:Vector3(1.1,.01,0)})
		if character == "turbofit": m.configure_actor_kit(2,"turbofit")
		await settle(m)
		m.fighters[2].facing = -1
		var frames := {1:frame(true,1)}
		if character == "turbofit":
			# Real Horizontal starts eight ticks before Punch: age17 and age9.
			await tick(m,{2:frame(true,-1)})
			check(m.fighters[2].move_id == "MeleeHorizontal" and not m.fighters[2].activation_id.is_empty(),"guitar trade real activation prerequisite")
			for age in range(1,8): await tick(m)
			check(m.events.is_empty() and m.fighters[1].percent == 0,"Turbo preparatory hand frames inactive")
		else: frames[2] = frame(true,-1)
		await tick(m,frames)
		check(not m.fighters[1].activation_id.is_empty() and not m.fighters[2].activation_id.is_empty(),"both trade activations real")
		var impact_age := -1
		for age in range(1,12):
			await tick(m)
			if not m.events.is_empty():
				impact_age = age
				break
		check(impact_age >= 9 and impact_age <= 11,"trade reaches actual hand window")
		check(m.fighters[1].percent == (14 if character == "turbofit" else 8) and m.fighters[2].percent == 8,"generated simultaneous trade "+character)
		check(m.events.size() == 2,"two trade candidates")
		for event in m.events:
			check(event.get("geometry_mode","") == "generated_hurtboxes","trade evidence generated")
			check(event.contact_evidence.pose_revision == m.collision_telemetry(event.victim).contact_snapshot.pose_revision,"trade evidence keeps pre-hit pose")
		m.configure_actor_kit(2,"teknium")
	cleanup(m); floor.free()
	if not failures: print("PASS: two fighter combat (%d checks)" % checks)
	quit(1 if failures else 0)
