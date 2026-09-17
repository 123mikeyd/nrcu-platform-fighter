extends "res://tests/test_core_top_support_native.gd"
func run():
	for reverse in [false,true]:
		var f = setup_pair("teknium","turbofit",reverse)
		for target in [1,2]:
			for mode in ["freeze","disable","hitstop","launch","reset","stock","rematch"]:
				reset_drop(f,0,0.1)
				await acquire(f)
				var before = f.a.position; var clock = f.a.runtime.tick; var generation = f.m.generation
				var shape = f.a.get_node("CoreCapsule").shape
				match mode:
					"freeze": f.m.set_frozen(target,true)
					"disable": f.m.set_enabled(target,false)
					"hitstop": f.m.fighters[target].hitstop_left = 3
					"launch": f.m.fighters[target].actor.apply_combat_launch(Vector3(-5,6,0),15)
					"reset": f.m.reset({1:Vector3(-4,1,0),2:Vector3(4,1,0)})
					"stock","rematch":
						var rules = load("res://scripts/core/match/match_rules.gd").new()
						f.m.configure_rules(rules)
						if mode == "stock": f.m.fighters[target].actor.position.y = -9
						else: f.m.rematch()
				await step(f.m)
				check(f.m.top_support_telemetry(1).relation.is_empty(),mode+" clears acquired relation")
				check(f.a.get_node("CoreCapsule").shape == shape,mode+" does not resize core")
				if target == 1 and mode == "freeze": check(absf(f.a.position.x-before.x)<0.001 and is_zero_approx(f.a.velocity.x),"frozen no injected slip")
				if target == 1 and mode == "hitstop": check(f.a.position == before and f.a.runtime.tick == clock,"stopped transform and actor clock unchanged")
				if target == 1 and mode == "launch": check(f.a.velocity.x < -1.5 and f.a.velocity.y > 0,"launch not overwritten")
				if mode in ["reset","rematch"]: check(f.m.generation > generation,"new generation")
				if mode == "stock": check(not f.m.lifecycle_events.is_empty(),"real stock lifecycle prerequisite")
				f.m.rules = null
		# Telemetry is copied and disconnected from the authority.
		reset_drop(f,0,0.1); await acquire(f)
		var telemetry = f.m.top_support_telemetry(1)
		telemetry.relation.carrier = 999; telemetry.geometry.height = -99
		check(f.m.top_support_telemetry(1).relation.carrier == 2 and f.m.top_support_telemetry(1).geometry.height > 0,"read-only telemetry")
		# Place a real roof above a legal acquired pair, then jump the carrier.
		var roof = StaticBody3D.new(); var c = CollisionShape3D.new(); var box = BoxShape3D.new()
		box.size = Vector3(8,0.2,4); c.shape = box; roof.add_child(c)
		var roof_bottom = f.a.position.y+f.a.get_node("CoreCapsule").shape.height+0.06
		roof.position.y = roof_bottom+0.1; root.add_child(roof)
		for i in 5: await step(f.m)
		var jump = Frame.new(); jump.pressed.jump = true; jump.held.jump = true
		await step(f.m,{2:jump}); jump.pressed.clear()
		var rejected = false; var jump_attempted = false
		for i in 9:
			await step(f.m,{2:jump})
			# The roof guard now retracts that tick's upward travel. Prove the
			# accepted native jump, not displacement that would create a crush.
			for event in f.b.runtime.states.trace:
				jump_attempted = jump_attempted or event.reason == "full hop"
			var p = f.m.top_support_telemetry(1).last_proposal
			rejected = rejected or (not p.is_empty() and not p.accepted)
			check(f.a.position.y+f.a.get_node("CoreCapsule").shape.height <= roof_bottom+0.003,"terrain ceiling blocks support lift")
		check(jump_attempted and rejected,"accepted carrier jump and refused roof lift prerequisites")
		roof.free(); dispose(f)
	if not failures: print("PASS: top support interruptions stock rematch telemetry and roof sweeps")
	quit(1 if failures else 0)
