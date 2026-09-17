extends "res://tests/test_core_ice_match_shatter.gd"
func floor_body():
	var body = StaticBody3D.new(); var shape = CollisionShape3D.new(); var box = BoxShape3D.new()
	box.size = Vector3(100,1,10); shape.shape = box; body.add_child(shape); body.position.y = -.5; root.add_child(body); return body
func shield(pressed := false, axis := Vector2.ZERO):
	var f = Frame.new(); f.held.shield = true; f.pressed.shield = pressed; f.axis = axis; return f
func run():
	var floor = floor_body()
	for kit in ["teknium","turbofit","ice_mage"]:
		var m = Match.new(); var a = Actor.new(); var b = Actor.new()
		root.add_child(a); root.add_child(b)
		m.register_actor(1,a,-1,"ice_mage"); m.register_actor(2,b,-1,kit)
		var profile = load("res://scripts/core/combat/defense_profile.gd").new()
		profile.shield_drain = 0; profile.shield_regen = 0; profile.ground_dodge_speed = 0
		m.configure_defense(profile)
		m.reset({1:Vector3(-10,.01,0),2:Vector3(0,.01,0)})
		for i in 12: await step(m)
		bolt(m,1,2,"shield"); await step(m,{2:shield(true)})
		check(m.fighters[2].percent == 0 and not m.fighters[2].frozen,"finite shield rejects hit/status "+kit)
		check(m.defense_telemetry(2).shield_health == 94,"finite frost cost4+2 "+kit)
		m.reset({1:Vector3(-10,.01,0),2:Vector3(0,.01,0)})
		for i in 12: await step(m)
		await step(m,{2:shield(true,Vector2.RIGHT)})
		for i in 20:
			if m.defense_telemetry(2).state == "dodge_invulnerable": break
			await step(m)
		check(m.defense_telemetry(2).state == "dodge_invulnerable","real dodge fixture "+kit)
		m.set_projectile_absorbing(2,true)
		bolt(m,1,2,"dodge"); await step(m)
		check(m.fighters[2].percent == 0 and not m.fighters[2].frozen,"dodge rejects status "+kit)
		check(m.fighters[2].absorbed_damage == 0,"dodge cannot commit absorption payload "+kit)
		check(m.projectile_telemetry().is_empty(),"dodge consumes contact "+kit)
		a.free(); b.free()
	# First contact breaks a shield; captured frost remains status-suppressed.
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); var c = Actor.new()
	root.add_child(a); root.add_child(b); root.add_child(c)
	m.register_actor(1,a); m.register_actor(2,b,-1,"ice_mage"); m.register_actor(3,c)
	var profile = load("res://scripts/core/combat/defense_profile.gd").new(); profile.shield_drain = 0; profile.shield_regen = 0
	m.configure_defense(profile); m.reset({1:Vector3(1.5,.01,0),2:Vector3(-10,.01,0),3:Vector3(0,.01,0)})
	for i in 12: await step(m)
	m.fighters[3].defense.shield_health = 1
	bolt(m,2,3,"later"); await step(m,{1:press(Vector2.LEFT,"attack"),3:shield(true)})
	check(m.fighters[3].percent == 4,"later frost damage after ordered shield break")
	check(not m.fighters[3].frozen,"collision shield snapshot survives earlier ordered break")
	a.free(); b.free(); c.free(); floor.free()
	if not failures: print("PASS: ice match finite defense (%d checks)" % checks)
	quit(1 if failures else 0)
