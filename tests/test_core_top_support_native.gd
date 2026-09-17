extends "res://tests/test_core_top_support_lifecycle.gd"
func reset_drop(f, x: float, gap: float, speed := -12.0):
	var plane = f.m.top_support_telemetry(2).geometry.height
	f.m.reset({1:Vector3(x,plane+gap,0),2:Vector3.ZERO})
	f.a.runtime.air_jumps_left = 0; f.a.runtime.recovery_spent = true
	f.a.runtime.velocity.y = speed; f.a.velocity = f.a.runtime.velocity
func run():
	for lower in ["teknium","turbofit"]:
		for upper in ["teknium","turbofit"]:
			for reverse in [false,true]:
				var f = setup_pair(lower,upper,reverse)
				var plane = f.m.top_support_telemetry(2).geometry.height
				var width = f.m.top_support_telemetry(2).geometry.half_width + 0.12
				for side in [-1,1]:
					reset_drop(f,side*(width-0.02),0.10)
					await step(f.m)
					check(not f.m.top_support_telemetry(1).relation.is_empty(),"edge descending acquires "+lower+upper)
					check(f.a.position.y+f.m.top_support_telemetry(1).relation.get("sole_offset",0.0) >= f.b.position.y+plane-0.002,"edge feet protected")
					check(not f.a.runtime.grounded and f.a.runtime.air_jumps_left == 0 and f.a.runtime.recovery_spent,"no terrain/air resource refund")
					reset_drop(f,side*(width+0.10),0.10)
					await step(f.m)
					check(f.m.top_support_telemetry(1).relation.is_empty(),"glancing outside bounded footprint")
				reset_drop(f,0,-0.035,3.0)
				await step(f.m)
				check(f.m.top_support_telemetry(1).relation.is_empty() and f.a.velocity.y > 0,"rising from below is not captured")
				reset_drop(f,0,-0.04,-0.2)
				await step(f.m)
				check(f.m.top_support_telemetry(1).relation.is_empty() and f.a.position.y < plane-0.015,"synthetic below-plane overlap not warped")
				reset_drop(f,0,1,-120.0)
				f.a.runtime._tuning.fall_speed = 200
				await step(f.m)
				check(not f.m.top_support_telemetry(1).relation.is_empty() and f.a.position.y+f.m.top_support_telemetry(1).relation.get("sole_offset",0.0) >= plane-0.002,"high-speed swept crossing no tunnel")
				reset_drop(f,0,0.1)
				await acquire(f)
				var contact = f.a.position
				var lost = false
				for i in 70:
					await step(f.m)
					if f.m.top_support_telemetry(1).relation.is_empty(): lost = true; break
				check(lost and f.a.position.x > contact.x+0.1,"finite deterministic head slip, not infinite platform")
				reset_drop(f,0,0.1)
				await acquire(f)
				for i in 8: await step(f.m)
				var bottom_before = f.b.position.y; var rider_before = f.a.position.y
				var frame = Frame.new(); frame.pressed.jump = true; frame.held.jump = true
				await step(f.m,{2:frame})
				frame.pressed.clear()
				for i in 7: await step(f.m,{2:frame})
				check(f.b.position.y > bottom_before+0.1,"lower real buffered ground jump prerequisite")
				check(f.a.position.y > rider_before+0.1,"rising carrier swept support follows upward motion")
				dispose(f)
	if not failures: print("PASS: top support native edge crossing carrier and slip matrix")
	quit(1 if failures else 0)
