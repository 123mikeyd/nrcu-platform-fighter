extends "res://tests/test_core_top_support_native.gd"
func run():
	for lower in ["teknium","turbofit"]:
		for upper in ["teknium","turbofit"]:
			for reverse in [false,true]:
				var f = setup_pair(lower,upper,reverse)
				reset_drop(f,0,0.1); await acquire(f)
				var roof = StaticBody3D.new(); var c = CollisionShape3D.new(); var box = BoxShape3D.new()
				box.size = Vector3(8,0.2,4); c.shape = box; roof.add_child(c)
				roof.position.y = f.a.position.y+f.a.get_node("CoreCapsule").shape.height+0.16; root.add_child(roof)
				for i in 5: await step(f.m)
				var jump = Frame.new(); jump.pressed.jump = true; jump.held.jump = true
				await step(f.m,{2:jump}); jump.pressed.clear()
				var blocked = false
				for i in 12:
					await step(f.m,{2:jump})
					var proposal = f.m.top_support_telemetry(1).last_proposal
					blocked = blocked or (not proposal.is_empty() and not proposal.accepted)
					var ca = f.a.get_node("CoreCapsule"); var cb = f.b.get_node("CoreCapsule")
					var axis_a = ca.shape.height*0.5-ca.shape.radius; var axis_b = cb.shape.height*0.5-cb.shape.radius
					var vertical = maxf(0,absf(ca.global_position.y-cb.global_position.y)-axis_a-axis_b)
					var horizontal = ca.global_position.x-cb.global_position.x
					var distance = Vector2(horizontal,vertical).length()
					if distance < ca.shape.radius+cb.shape.radius-0.005:
						print("ROOF overlap=",ca.shape.radius+cb.shape.radius-distance," a=",f.a.position," b=",f.b.position," proposal=",proposal," state=",f.a.runtime.states.locomotion)
					check(distance >= ca.shape.radius+cb.shape.radius-0.005,"blocked roof lift must not manufacture native-core overlap "+lower+upper)
				check(blocked,"actual denied support lift prerequisite "+lower+upper)
				roof.free(); dispose(f)
	if not failures: print("PASS: roof carrier does not manufacture crush overlap")
	quit(1 if failures else 0)
