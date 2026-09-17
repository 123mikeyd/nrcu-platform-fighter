extends "res://tests/test_core_grab_slice.gd"
func run():
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 10); shape.shape = box; floor_body.add_child(shape); floor_body.position.y = -0.5; root.add_child(floor_body)
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); var c = Actor.new()
	root.add_child(a); root.add_child(b); root.add_child(c)
	m.register_actor(1, a); m.register_actor(2, b); m.register_actor(3, c)
	for reason in ["follow", "break", "blocked", "hit_caster", "hit_victim"]:
		m.reset({1: Vector3.ZERO, 2: Vector3.RIGHT, 3: Vector3(5, 0, 0)})
		for i in 10: await step(m)
		var f = Frame.new(); f.pressed.special = true
		await step(m, {1: f})
		for i in 11: await step(m)
		var offset: Vector3 = b.position - a.position
		check(m.fighters[2].caught_by == 1 and offset.distance_to(Vector3.RIGHT) < 0.01, "capture preserves actual offset")
		b.runtime.recovery_spent = true; b.runtime.air_jumps_left = 0
		if reason == "follow":
			for i in 30:
				var previous: Vector3 = b.position
				await step(m)
				check(b.position.distance_to(previous) <= 3.0/60 + 0.0001, "actor movement capped not teleported")
				check(m.fighters[1].grab.anchor(a.position).distance_to(a.position + offset) <= 0.25001, "hand delta capped")
			check(b.runtime.recovery_spent and b.runtime.air_jumps_left == 0, "no caught grounded resource reset")
		elif reason == "break":
			b.position.x += 0.81; await step(m)
			check(m.fighters[2].caught_by == 0 and m.fighters[1].grab == null, "distance breaks both links")
		elif reason == "blocked":
			var wall := StaticBody3D.new(); var collider := CollisionShape3D.new(); var wallbox := BoxShape3D.new()
			wallbox.size = Vector3(0.02, 4, 4); collider.shape = wallbox; wall.add_child(collider)
			wall.position = b.position + Vector3(0.1, 1, 0); root.add_child(wall)
			b.position.x += 0.2
			await step(m)
			check(m.fighters[2].caught_by == 0, "blocked anchor cancels")
			wall.free()
		else:
			c.position = Vector3(-1 if reason == "hit_caster" else 2, 0, 0)
			var hit = Frame.new(); hit.pressed.attack = true; hit.axis = Vector2.RIGHT if reason == "hit_caster" else Vector2.LEFT
			await step(m, {3: hit})
			var victim_id := 1 if reason == "hit_caster" else 2
			check(m.fighters[victim_id].percent > 0 and m.fighters[victim_id].actor.runtime.hitstun_left > 0, "real incoming strike")
			check(m.fighters[2].caught_by == 0 and m.fighters[1].grab == null, "normal hit cancels both endpoints")
			check(m.fighters[victim_id].actor.velocity.length() > 0, "release does not erase incoming launch")
	a.free(); b.free(); c.free(); floor_body.free()
	if not failures: print("PASS: grab restraint and real hits (%d checks)" % checks)
	quit(1 if failures else 0)
