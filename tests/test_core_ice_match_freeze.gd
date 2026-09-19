extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	for kit in ["teknium","turbofit","ice_mage"]:
		var m = Match.new(); var a = Actor.new(); var b = Actor.new()
		root.add_child(a); root.add_child(b)
		m.register_actor(1,a,-1,"ice_mage"); m.register_actor(2,b,-1,kit)
		m.reset({1:Vector3(0,20,0),2:Vector3(1.5,20,0)})
		await step(m,{1:press(Vector2.ZERO)})
		for i in 11: await step(m)
		check(m.fighters[2].percent == 4,"actual bolt damage " + kit)
		check(b.runtime.states.status == "frozen","atomic accepted bolt freezes " + kit)
		check(b.velocity.x == 0 and b.velocity.y <= 0,"freeze suppresses launch " + kit)
		check(b.runtime.hitstun_left == 0,"freeze replaces bolt stun " + kit)
		if m.has_method("status_telemetry"):
			check(m.status_telemetry(2).freeze_remaining == 1.0,"entry full duration")
			var y = b.position.y
			for i in 59: await step(m)
			check(m.status_telemetry(2).freeze_remaining > 0,"strict before endpoint")
			check(b.position.y < y,"frozen body falls")
			await step(m)
			check(not m.fighters[2].frozen,"natural thaw endpoint")
			check(m.status_telemetry(2).freeze_immunity == 1.0,"thaw grants full not decremented immunity")
		else: check(false,"match publishes finite status telemetry")
		a.free(); b.free()
	if not failures: print("PASS: ice match freeze (%d checks)" % checks)
	quit(1 if failures else 0)
