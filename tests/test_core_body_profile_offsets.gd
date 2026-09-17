extends "res://tests/test_core_body_profile_ledge.gd"
func run():
	for side in [-1,1]:
		for kind in ["synthetic","teknium","turbofit"]:
			var p = body_profile(0.6,2.8) if kind == "synthetic" else load("res://data/collision/generated/"+kind+".tres")
			if kind == "synthetic": p.body_center.x = 0.35; p.body_center.z = 0.05
			var terrain = block(Vector3(-side*2,-0.5,0),Vector3(4,1,4))
			var m = Match.new(); var a = Actor.new(); root.add_child(a)
			check(a.configure_body_profile(p), "configure offset profile before registration")
			m.register_actor(1,a); m.reset({1:Vector3(side*1.35,-1,0)})
			var anchor = Anchor.new(); anchor.anchor_id="edge"; anchor.outward=side
			m.configure_ledges([anchor],Policy.new())
			var f = Frame.new(); f.axis.x=-side
			await step(m,{1:f})
			check(m.ledge_telemetry(1).anchor_id == "edge", "offset body actual ledge catch: " + kind)
			var collider = a.get_node("CoreCapsule")
			check(is_equal_approx(collider.global_position.x,side*(p.body_radius+0.25)), "hang clearance measured from actual offset center")
			check(a.position.z == 0 and is_equal_approx(collider.position.z,p.body_center.z), "offset depth preserved without moving planar foot origin")
			var up = Frame.new(); up.axis.y=-1
			await step(m,{1:up})
			check(is_equal_approx(collider.global_position.x,-side*(p.body_radius+0.3)) and is_equal_approx(a.position.y,0.06), "offset body complete clear elbow climb")
			for i in 5: await step(m)
			check(a.runtime.grounded, "offset profile native terrain landing")
			a.free(); terrain.free()
	if not failures: print("PASS body profile offsets (%d checks)" % checks)
	quit(1 if failures else 0)
