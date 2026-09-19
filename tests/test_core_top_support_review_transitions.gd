extends "res://tests/test_core_top_support_review_trajectory.gd"
func run():
	# Preservation controls: only committed support may track category growth.
	for reverse in [false,true]:
		for blocked in [false,true]:
			var f = setup_pair("teknium","teknium",reverse)
			f.m.reset({1:Vector3(0,4,0),2:Vector3(0,2,0)})
			f.b.runtime._tuning.gravity = 0
			f.a.runtime.velocity.y = -12; f.a.velocity = f.a.runtime.velocity
			await step(f.m)
			check(not f.m.top_support_telemetry(1).relation.is_empty(),"held category transition acquired prerequisite")
			var height = f.m.top_support_telemetry(2).geometry.height
			var roof = StaticBody3D.new(); var c = CollisionShape3D.new(); var box = BoxShape3D.new()
			var roof_bottom = f.a.position.y+f.a.get_node("CoreCapsule").shape.height+0.02
			if blocked:
				box.size = Vector3(8,0.2,4); c.shape = box; roof.add_child(c); roof.position.y = roof_bottom+0.1; root.add_child(roof)
			await step(f.m)
			var t = f.m.top_support_telemetry(1)
			check(is_equal_approx(f.m.top_support_telemetry(2).geometry.height-height,0.08),"unchanged bounded category growth")
			check(not t.last_proposal.is_empty() and t.last_proposal.accepted == not blocked,"held category adjustment uses terrain acceptance")
			if blocked: check(f.a.position.y+f.a.get_node("CoreCapsule").shape.height <= roof_bottom+0.003 and t.relation.is_empty(),"roof rejection releases rather than warps")
			else: check(is_equal_approx(f.a.position.y+t.relation.sole_offset,f.b.position.y+height+0.08),"held rider follows expanding category")
			check(not f.a.runtime.grounded and f.a.runtime.air_jumps_left == 1,"category carry is not terrain ground")
			check(f.a.get_collision_exceptions().is_empty() and f.b.get_collision_exceptions().is_empty(),"no movement exception leaks")
			roof.free(); dispose(f)
		# Native acquisition from real relative rise, not category change.
		var f = setup_pair("teknium","teknium",reverse)
		f.m.reset({1:Vector3(0.45,3.94,0),2:Vector3(0,2,0)})
		f.a.runtime.velocity.y = 4; f.a.velocity = f.a.runtime.velocity
		f.b.runtime.velocity.y = 12; f.b.velocity = f.b.runtime.velocity
		await step(f.m)
		check(f.b.position.y > 2.15,"carrier actually rose through start plane prerequisite")
		check(not f.m.top_support_telemetry(1).relation.is_empty(),"native faster rising carrier catches rising rider")
		dispose(f)
	# Ineligible endpoints must never renew a previously held relation.
	for participant in [1,2]:
		for endpoint in ["start","end"]:
			var solver = Solver.new()
			var start = {1:snap(0,1.9,0),2:snap(0,0,0)}
			var end = {1:snap(0,1.9,0),2:snap(0,0,0,1.98)}
			solver.commit(1,{"carrier":2,"generation":1},true)
			if endpoint == "start": start[participant].eligible = false
			else: end[participant].eligible = false
			solver.begin(start)
			check(not solver.solve(end,1).has(1) and solver.snapshot(1).relation.is_empty(),"disabled/stock status boundaries retire held support")
	if not failures: print("PASS: support category and native relative-rise controls (%d checks)" % checks)
	quit(1 if failures else 0)
