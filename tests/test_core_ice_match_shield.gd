extends "res://tests/test_core_ice_match_shatter.gd"
func shield_frame():
	var f = Frame.new(); f.held.shield = true; return f
func run():
	for kit in ["teknium","turbofit","ice_mage"]:
		var m = Match.new(); var a = Actor.new(); var b = Actor.new()
		root.add_child(a); root.add_child(b)
		m.register_actor(1,a,-1,"ice_mage"); m.register_actor(2,b,-1,kit)
		m.reset({1:Vector3(-10,50,0),2:Vector3(0,50,0)})
		bolt(m,1,2,"shield"); await step(m,{2:shield_frame()})
		check(is_equal_approx(m.fighters[2].percent,1.4),"frost legacy shield 35 percent chip "+kit)
		check(not m.fighters[2].frozen,"shield snapshot suppresses status "+kit)
		var strength: float = (1.0 + 1.4*.065 + 4.0*.12)*.28
		check(is_equal_approx(b.velocity.length(),strength),"legacy shield scales full payload knockback "+kit)
		m.reset({1:Vector3(-10,50,0),2:Vector3(0,50,0)})
		m.set_frozen(2,true)
		bolt(m,1,2,"frozen-shield"); await step(m,{2:shield_frame()})
		check(m.fighters[2].percent == 4,"frozen legacy shield cannot intercept "+kit)
		m.reset({1:Vector3(-10,50,0),2:Vector3(0,50,0)})
		m.set_projectile_absorbing(2,true)
		bolt(m,1,2,"absorb"); await step(m)
		check(m.fighters[2].absorbed_damage == 4 and m.fighters[2].percent == 0 and not m.fighters[2].frozen,"atomic absorption without damage/status "+kit)
		m.reset({1:Vector3(-10,50,0),2:Vector3(0,50,0)})
		m.fighters[2].protection_until = m.tick+2
		bolt(m,1,2,"protected"); await step(m)
		check(m.fighters[2].percent == 0 and not m.fighters[2].frozen,"respawn protection filters status "+kit)
		check(m.projectile_telemetry().is_empty(),"protected contact consumes bolt "+kit)
		a.free(); b.free()
	if not failures: print("PASS: ice match shield (%d checks)" % checks)
	quit(1 if failures else 0)
