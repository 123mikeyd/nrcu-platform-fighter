extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	for reverse in [false,true]:
		var m = Match.new(); var a = Actor.new(); var b = Actor.new()
		root.add_child(a); root.add_child(b)
		var actors := {1:a,2:b}
		for id in ([2,1] if reverse else [1,2]): m.register_actor(id,actors[id],-1,"turbofit")
		var profile = load("res://data/collision/generated/turbofit.tres")
		check(m.reset_with_collision_profiles({1:Vector3(0,30,0),2:Vector3(2,30,0)},{1:profile,2:profile}),"duplicate real source install")
		var traded := false
		var shape: CollisionShape3D = a.get_node("CoreCapsule")
		var first_legal := int(ceil((shape.shape.radius*2+.05)/.05))
		for i in range(first_legal,61):
			m.reset({1:Vector3(0,30,0),2:Vector3(i*.05,30,0)})
			await step(m,{1:press(Vector2.RIGHT,"attack"),2:press(Vector2.LEFT,"attack")})
			for tick_index in 9: await step(m)
			if m.fighters[1].percent == 14 and m.fighters[2].percent == 14:
				traded = true
				check(m.events.size() == 2,"simultaneous two-sided generated candidate collection")
				for event in m.events: check(event.get("geometry_mode","") == "generated_hurtboxes","trade uses hurtboxes")
				print("TRADE legal separation ",i*.05," reverse=",reverse)
				break
		check(traded,"real generated duplicate kicks trade in registration order "+str(reverse))
		m.reset({1:Vector3(0,30,0),2:Vector3(2,30,0)})
		# Deliberately unsupported collision-character/kit pairing must diagnose,
		# not emit an empty-success or use the native movement body.
		m.configure_actor_kit(2,"teknium")
		await step(m,{2:press(Vector2.RIGHT,"attack")})
		var value: Dictionary = m.collision_telemetry(2)
		check(not value.get("ok",true) and not value.get("diagnostics",[]).is_empty(),"unsupported committed source state explicit diagnostic")
		check(value.get("primitives",[]).is_empty(),"invalid source state has no partial geometry")
		a.free(); b.free()
	if not failures: print("PASS: hurtbox match trades (%d checks)" % checks)
	quit(1 if failures else 0)
