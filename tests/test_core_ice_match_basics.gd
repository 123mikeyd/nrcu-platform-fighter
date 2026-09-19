extends "res://tests/test_core_recovery_acceptance.gd"
func floor_body():
	var body = StaticBody3D.new(); var shape = CollisionShape3D.new(); var box = BoxShape3D.new()
	box.size = Vector3(200,1,10); shape.shape = box; body.add_child(shape); body.position.y = -.5; root.add_child(body); return body
func run():
	var floor = floor_body()
	for grounded in [true,false]:
		for facing in [-1.0,1.0]:
			for aim in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(-facing,-1),Vector2(-facing,1)]:
				var m = Match.new(); var a = Actor.new(); var b = Actor.new()
				root.add_child(a); root.add_child(b); m.register_actor(1,a,-1,"ice_mage"); m.register_actor(2,b)
				m.reset({1:Vector3(0,.01 if grounded else 50,0),2:Vector3(20,50,0)})
				if grounded:
					for i in 12: await step(m)
				check(a.runtime.grounded == grounded,"route fixture support")
				m.fighters[1].facing = facing
				var direction = Vector3(facing,0,0)
				if aim.y < -.1: direction = Vector3.UP
				elif aim.y > .1: direction = Vector3(facing,-.25,0).normalized() if grounded else Vector3.DOWN
				elif absf(aim.x) > .1: direction = Vector3(signf(aim.x),0,0)
				await step(m,{1:press(aim,"attack")})
				check(m.kit_telemetry(1).basic.clip == "IceStrike","all routes IceStrike")
				check(m.fighters[1].buffer.peek("attack").is_empty(),"basic edge consumed")
				if aim.y != 0: check(m.kit_telemetry(1).basic.facing == facing,"vertical aim retains facing")
				for i in 10: await step(m)
				check(m.fighters[2].percent == 0,"no premature event")
				# Position target at source cone for authoritative final event query.
				b.reset_at(a.position + direction*1.5)
				b.runtime.velocity = a.runtime.velocity
				await step(m)
				check(m.fighters[2].percent == 8,"every directional cone resolves 8 damage")
				check(is_equal_approx(m.kit_telemetry(1).basic.remaining,.35),"event source cooldown replacement")
				check(m.fighters[1].force == null and m.fighters[1].grab == null and m.fighters[1].recovery == null,"no fallback")
				a.free(); b.free()
	floor.free()
	if not failures: print("PASS: ice match basics (%d checks)" % checks)
	quit(1 if failures else 0)
