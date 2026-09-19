extends "res://tests/test_core_body_profile_head.gd"
func run():
	for side in [-1,1]:
		var floor_node = floor_body(); var m = Match.new(); var a = Actor.new(); var b = Actor.new()
		var p = body_profile(0.6,2.8); p.body_center.x = side*0.35
		a.configure_body_profile(p); b.configure_body_profile(body_profile(0.2,0.6))
		root.add_child(a); root.add_child(b); m.register_actor(1,a); m.register_actor(2,b)
		m.reset({1:Vector3(-side*0.15,2,0),2:Vector3.ZERO})
		var head := false
		for i in 90:
			await step(m)
			for j in a.get_slide_collision_count():
				var c = a.get_slide_collision(j)
				for k in c.get_collision_count():
					if c.get_collider(k) == b and c.get_normal(k).y > 0.7: head = true
			if head: break
		check(head, "offset native upward head contact prerequisite")
		check(a.position.x*side < 0 and a.get_node("CoreCapsule").global_position.x*side > 0, "actual center opposite foot side prerequisite")
		await step(m)
		check(a._head_slip_direction == side, "escape chooses actual capsule side not offset foot position")
		a.free(); b.free(); floor_node.free()
	if not failures: print("PASS body profile offset head (%d checks)" % checks)
	quit(1 if failures else 0)
