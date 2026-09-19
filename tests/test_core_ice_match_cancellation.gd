extends "res://tests/test_core_ice_match_shatter.gd"
func run():
	for kit in ["teknium","turbofit","ice_mage"]:
		var m = Match.new(); var a = Actor.new(); var b = Actor.new()
		root.add_child(a); root.add_child(b)
		m.register_actor(1,a,-1,"ice_mage"); m.register_actor(2,b,-1,kit)
		m.reset({1:Vector3(-10,50,0),2:Vector3(0,50,0)})
		await step(m,{2:press(Vector2.ZERO,"attack")})
		bolt(m,1,2,"freeze-action"); await step(m)
		check(m.fighters[2].frozen,"freeze interrupts active basic "+kit)
		check(not m.kit_telemetry(2).action_locked,"finite freeze clears source attack cooldown "+kit)
		check(m.fighters[2].ready_tick == 0,"shared attack cooldown refunded "+kit)
		check(m.fighters[2].move_id == "" and m.fighters[2].recovery == null,"attached episode cancelled "+kit)
		var held = Frame.new(); held.held.shield = true; held.pressed.attack = true; held.pressed.special = true; held.pressed.jump = true; held.axis = Vector2.RIGHT
		await step(m,{2:held})
		check(not m.fighters[2].shield_command and b.velocity.x == 0 and m.fighters[2].move_id == "","effective freeze rejects all new intent "+kit)
		a.free(); b.free()
	if not failures: print("PASS: ice match freeze cancellation (%d checks)" % checks)
	quit(1 if failures else 0)
