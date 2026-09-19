extends "res://tests/test_core_ice_match_defense.gd"

func fixture(kit: String, policy := "finite"):
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"ice_mage"); m.register_actor(2,b,-1,kit)
	if policy != "null":
		var profile = load("res://scripts/core/combat/defense_profile.gd").new()
		profile.policy_id = policy
		profile.ground_dodge_speed = 0; profile.shield_drain = 0; profile.shield_regen = 0
		m.configure_defense(profile)
	m.reset({1:Vector3(-10,.01,0),2:Vector3(0,.01,0)})
	for i in 12: await step(m)
	return m

func dispose(m):
	for f in m.fighters.values(): f.actor.free()

func enter_phase(m, phase: String):
	if phase in ["idle", "shield"]: return
	await step(m,{2:shield(true,Vector2.RIGHT)})
	var target := "dodge_recovery" if phase == "recovery_exit" else phase
	for i in 60:
		if m.defense_telemetry(2).state == target: break
		await step(m)
	check(m.defense_telemetry(2).state == target,"real defense phase "+phase)
	if phase == "recovery_exit":
		while m.defense_telemetry(2).remaining_ticks > 1: await step(m)

func run():
	var floor = floor_body()
	for kit in ["teknium", "turbofit", "ice_mage"]:
		for phase in ["dodge_startup", "dodge_invulnerable", "dodge_recovery", "recovery_exit", "idle", "shield"]:
			for held in [true, false]:
				var m = await fixture(kit)
				await enter_phase(m,phase)
				if phase == "shield": await step(m,{2:shield(true)})
				bolt(m,1,2,"phase-contact")
				await step(m,{2:shield()} if held else {})
				var blocked: bool = phase == "dodge_invulnerable" or (phase in ["idle", "shield"] and held)
				var label := "%s %s held=%s" % [kit,phase,held]
				print("CASE %s damage=%s frozen=%s" % [label,m.fighters[2].percent,m.fighters[2].frozen])
				check(m.fighters[2].percent == (0 if blocked else 4),"collision damage "+label)
				check(m.fighters[2].frozen == not blocked,"collision freeze "+label)
				check(m.projectile_telemetry().is_empty(),"contact consumed "+label)
				dispose(m)
		# Same vulnerable recovery with immunity just before / at its clock endpoint.
		for immune in [2.0/60.0, 1.0/60.0]:
			var m = await fixture(kit)
			await enter_phase(m,"dodge_recovery")
			m.fighters[2].status_host.freeze_immunity = immune
			bolt(m,1,2,"immune-contact"); await step(m,{2:shield()})
			check(m.fighters[2].percent == 4,"immune recovery damage "+kit)
			check(m.fighters[2].frozen == (immune == 1.0/60.0),"immunity endpoint gates recovery freeze "+kit)
			dispose(m)
		# Legacy chip still suppresses freeze, with either default or explicit policy.
		for policy in ["null", "legacy"]:
			for held in [true,false]:
				var m = await fixture(kit,policy)
				bolt(m,1,2,"legacy-contact"); await step(m,{2:shield()} if held else {})
				check(is_equal_approx(m.fighters[2].percent,1.4 if held else 4.0),"legacy chip "+kit+policy)
				check(m.fighters[2].frozen == not held,"legacy status snapshot "+kit+policy)
				dispose(m)
		# Two accepted bolts must still freeze then shatter under held intent.
		var pair = await fixture(kit)
		await enter_phase(pair,"dodge_recovery")
		bolt(pair,1,2,"a"); bolt(pair,1,2,"b"); await step(pair,{2:shield()})
		check(pair.fighters[2].percent == 8 and not pair.fighters[2].frozen,"ordered recovery bolts "+kit)
		check(pair.status_telemetry(2).freeze_immunity == 1,"recovery freeze then shatter "+kit)
		check(pair.fighters[2].actor.runtime.hitstun_left > 0 and pair.fighters[2].actor.velocity.x > 0,"aggregate launch restored "+kit)
		dispose(pair)
	# Mixed basic then frost: collision shielding survives an earlier sorted break.
	var m = await fixture("teknium")
	var c = Actor.new(); root.add_child(c); m.register_actor(3,c)
	m.reset({1:Vector3(1.5,.01,0),2:Vector3(0,.01,0),3:Vector3(-10,.01,0)})
	# Source 1 uses the legacy basic so it breaks before source 3's bolt.
	m.configure_actor_kit(1,"teknium")
	for i in 12: await step(m)
	m.fighters[2].defense.shield_health = 1
	bolt(m,3,2,"later"); await step(m,{1:press(Vector2.LEFT,"attack"),2:shield(true)})
	check(m.fighters[2].percent == 4 and not m.fighters[2].frozen,"mixed shield-break snapshot suppresses later frost status")
	bolt(m,3,2,"next-frame"); await step(m,{2:shield()})
	check(m.fighters[2].percent == 8 and m.fighters[2].frozen,"subsequent broken shield contact freezes despite held intent")
	dispose(m)
	floor.free()
	if not failures: print("PASS: ice match dodge status (%d checks)" % checks)
	quit(1 if failures else 0)
