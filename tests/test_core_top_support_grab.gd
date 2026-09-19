extends "res://tests/test_core_top_support_native.gd"
func run():
	for reverse in [false,true]:
		var f = setup_pair("teknium","teknium",reverse)
		reset_drop(f,0,0.1); await acquire(f)
		var frame = Frame.new(); frame.pressed.special = true
		await step(f.m,{1:frame})
		check(f.m.fighters[1].grab != null and f.m.top_support_telemetry(1).relation.is_empty(),"real grab startup releases top-support motion")
		reset_drop(f,0,0.1); await acquire(f)
		var c = Actor.new(); root.add_child(c); f.m.register_actor(3,c)
		c.reset_at(Vector3(1.65,1.82,0)); f.m.fighters[3].facing = -1
		var platform = StaticBody3D.new(); var shape = CollisionShape3D.new(); var box = BoxShape3D.new()
		box.size = Vector3(0.4,0.2,4); shape.shape = box; platform.add_child(shape); platform.position = Vector3(1.65,1.72,0); root.add_child(platform)
		for i in 6: await step(f.m)
		check(c.runtime.grounded and not f.m.top_support_telemetry(1).relation.is_empty(),"legal standing third-party grabber and supported victim prerequisite")
		await step(f.m,{3:frame})
		for i in 11: await step(f.m)
		var grab = f.m.fighters[3].grab
		var point = c.position+grab.sample("GrabStart",13.0/24,grab.facing)
		var nearest_gap = INF; var nearest_point = Vector3.ZERO
		for primitive in f.m.collision_telemetry(1).primitives:
			var near = Geometry3D.get_closest_point_to_segment(point,primitive.a,primitive.b)
			var gap = point.distance_to(near)-primitive.radius-0.18
			if gap < nearest_gap: nearest_gap = gap; nearest_point = near
		print("GRAB ",point," gap=",nearest_gap," near=",nearest_point," status ",f.m.fighters[1].grab," ",f.m.fighters[1].grab_immune_until)
		check(f.m.fighters[1].caught_by == 3,"actual hand acquisition catches supported rider")
		check(f.m.top_support_telemetry(1).relation.is_empty(),"capture releases relation in same contact commit")
		f.m.cancel_action(3,"test release")
		check(not c in f.a.get_collision_exceptions(),"grab and transient support exceptions do not leak")
		c.free(); platform.free(); dispose(f)
	if not failures: print("PASS: support grab startup capture release and exception ownership")
	quit(1 if failures else 0)
