extends "res://tests/test_core_body_profile_head.gd"
func run():
	for reverse in [false,true]:
		for large in [false,true]:
			var floor_node = floor_body(); var m = Match.new(); var a = Actor.new(); var b = Actor.new()
			a.configure_body_profile(body_profile(0.6 if large else 0.3,2.8 if large else 1.8))
			b.configure_body_profile(body_profile(0.3 if large else 0.6,1.8 if large else 2.8))
			root.add_child(a); root.add_child(b)
			if reverse: m.register_actor(2,b); m.register_actor(1,a)
			else: m.register_actor(1,a); m.register_actor(2,b)
			m.reset({1:Vector3.ZERO,2:Vector3(1,0,0)})
			for i in 12: await step(m)
			var shapes = [a.get_node("CoreCapsule").shape,b.get_node("CoreCapsule").shape]
			var f = Frame.new(); f.pressed.special = true
			await step(m,{1:f})
			for i in 11: await step(m)
			check(m.fighters[2].caught_by == 1, "real grab uses unequal native target capsule in both roles")
			check(a.get_collision_exceptions().has(b) and b.get_collision_exceptions().has(a), "capture installs reciprocal exceptions")
			m.fighters[1].hitstop_left = 3
			var at = [a.position,b.position]; var clocks = [a.runtime.tick,b.runtime.tick]
			for i in 3: await step(m)
			check(at == [a.position,b.position] and clocks == [a.runtime.tick,b.runtime.tick], "unequal held pair shares stopped clock and placement")
			m.cancel_action(1,"profile grab test release")
			check(m.fighters[2].caught_by == 0 and a.get_collision_exceptions().is_empty() and b.get_collision_exceptions().is_empty(), "release clears relation and exceptions")
			check(shapes == [a.get_node("CoreCapsule").shape,b.get_node("CoreCapsule").shape], "grab release never swaps or resizes shapes")
			m.reset({1:Vector3(-3,0,0),2:Vector3(3,0,0)})
			check(shapes == [a.get_node("CoreCapsule").shape,b.get_node("CoreCapsule").shape] and m.fighters[1].grab == null, "reset clears grab history retaining stable independent shapes")
			check(m.reset_with_body_profiles({1:Vector3.ZERO,2:Vector3(1,0,0)},{2:body_profile(0.3,1.5)}), "reset installs intentionally shorter capture target")
			for i in 12: await step(m)
			await step(m,{1:f})
			for i in 11: await step(m)
			check(m.fighters[1].grab != null and m.fighters[2].caught_by == 0, "native short capsule genuinely misses unchanged authored hand sphere")
			a.free(); b.free(); floor_node.free()
	if not failures: print("PASS body profile grab (%d checks)" % checks)
	quit(1 if failures else 0)
