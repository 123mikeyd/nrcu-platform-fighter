extends "res://tests/test_core_body_profile.gd"
func floor_body():
	var b = StaticBody3D.new(); var c = CollisionShape3D.new(); var s = BoxShape3D.new()
	s.size = Vector3(40,1,4); c.shape = s; b.add_child(c); b.position.y = -0.5; root.add_child(b); return b
func run():
	for reverse in [false,true]:
		var floor_node = floor_body(); var m = Match.new(); var a = Actor.new(); var b = Actor.new()
		a.configure_body_profile(body_profile(0.6,2.8)); b.configure_body_profile(body_profile(0.2,0.6))
		root.add_child(a); root.add_child(b)
		if reverse: m.register_actor(2,b); m.register_actor(1,a)
		else: m.register_actor(1,a); m.register_actor(2,b)
		m.reset({1:Vector3(0,2,0),2:Vector3.ZERO})
		a.runtime.air_jumps_left = 0; a.runtime.recovery_spent = true
		var head := false
		for i in 90:
			await step(m)
			for j in a.get_slide_collision_count():
				var c = a.get_slide_collision(j)
				for k in c.get_collision_count():
					if c.get_collider(k) == b and c.get_normal(k).y > 0.7: head = true
			if head: break
		check(head, "unequal short-body native head contact prerequisite")
		check(not a.runtime.grounded and a.runtime.air_jumps_left == 0 and a.runtime.recovery_spent, "head never refunds terrain resources")
		var at = a.position
		await step(m)
		check(a.position.x > at.x and a.velocity.x >= 1.49, "derived head support permits slip atop short body")
		a.free(); b.free(); floor_node.free()
	if not failures: print("PASS body profile head (%d checks)" % checks)
	quit(1 if failures else 0)
