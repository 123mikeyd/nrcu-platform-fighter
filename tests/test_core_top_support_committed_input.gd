extends "res://tests/test_core_top_support_lifecycle.gd"
func parsed_step(m, source):
	await physics_frame
	Input.flush_buffered_events()
	m.simulate({1:source.sample(m.tick)})
func run():
	for upper in ["teknium","turbofit"]:
		for available in [0,1]:
			var f = setup_pair("teknium",upper)
			f.a.runtime.air_jumps_left = available
			f.a.runtime.recovery_spent = available == 0
			await acquire(f)
			var source = Source.new()
			key(KEY_SPACE,false); await parsed_step(f.m,source)
			check(not f.m.top_support_telemetry(1).relation.is_empty(),"retained stance before parsed jump")
			check(f.a.runtime.air_jumps_left == available and f.a.runtime.recovery_spent == (available == 0),"support does not refund resources")
			key(KEY_SPACE,true); await parsed_step(f.m,source)
			key(KEY_SPACE,false)
			var pose = f.m.collision_telemetry(1).pose_request
			if available:
				check(f.a.velocity.y > 0 and f.a.runtime.air_jumps_left == 0,"parsed jump spends existing airborne opportunity")
				check(f.m.top_support_telemetry(1).relation.is_empty() and pose.state != "supported","same committed jump tick restores air source")
			else:
				check(f.a.velocity.y <= 0 and f.a.runtime.air_jumps_left == 0,"spent jump remains spent on support")
			check(not f.a.runtime.grounded,"no terrain ground lock or landing")
			dispose(f)
	if not failures: print("PASS: supported parsed jump resources and same-tick air pose")
	quit(1 if failures else 0)
