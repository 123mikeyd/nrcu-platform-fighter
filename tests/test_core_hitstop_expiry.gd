extends "res://tests/test_core_match_strikes.gd"
func run() -> void:
	for stopped in [false,true]:
		for offset in [-1,0,1]:
			var m = load("res://scripts/core/match/match_simulation.gd").new()
			var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
			m.register_actor(1,a); m.register_actor(2,b); m.reset({1:Vector3(0,5,0),2:Vector3(1,5,0)})
			await tick(m)
			var deadline = m.tick + offset
			m.fighters[2].protection_until = deadline; m.fighters[2].grab_immune_until = deadline
			m.fighters[2].ready_tick = m.tick; m.fighters[2].magic_ready_tick = m.tick
			if stopped: m.fighters[2].hitstop_left = 1
			m.projectiles.append({"source":1,"activation_id":"expiry","facing":1.0,"position":b.position+Vector3(-0.45,0.9,0),"spawn_tick":-1,"ttl":96})
			await tick(m)
			var expected = deadline + (1 if stopped and offset > 0 else 0)
			check(m.fighters[2].protection_until == expected and m.fighters[2].grab_immune_until == expected, "immunity expiry is strict future only; stopped=%s offset=%d" % [stopped,offset])
			check(m.fighters[2].percent == (0 if offset > 0 else 8), "expired immunity never revives against projectile during stop")
			check(m.projectiles.is_empty(), "projectile contact consumes even while actor stopped")
			check(m.fighters[2].ready_tick == (m.tick if stopped else m.tick-1), "ready deadline keeps existing skipped-acceptance semantics")
			a.free(); b.free()
	# Protection/grab immunity equality is tested against an actual capture too.
	var ground = StaticBody3D.new(); var shape = CollisionShape3D.new(); var box = BoxShape3D.new(); box.size = Vector3(30,1,6)
	shape.shape = box; ground.add_child(shape); ground.position.y = -0.5; root.add_child(ground)
	for offset in [-1,0,1]:
		var m = load("res://scripts/core/match/match_simulation.gd").new()
		var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
		m.register_actor(1,a); m.register_actor(2,b); m.reset({1:Vector3.ZERO,2:Vector3(1,0,0)})
		for i in 10: await tick(m)
		var special = Frame.new(); special.pressed.special = true
		await tick(m,{1:special})
		for i in 10: await tick(m)
		m.fighters[2].grab_immune_until = m.tick + offset; m.fighters[2].hitstop_left = 1
		await tick(m)
		check(m.fighters[2].caught_by == (0 if offset > 0 else 1), "actual capture sees expired vs future immunity during victim stop")
		a.free(); b.free()
	ground.free()
	if not failures: print("PASS: core hitstop expiry (%d checks)" % checks)
	quit(1 if failures else 0)
