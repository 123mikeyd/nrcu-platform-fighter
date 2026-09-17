extends "res://tests/test_core_top_support_native.gd"
func run():
	for reverse in [false,true]:
		var f = setup_pair("turbofit","teknium",reverse)
		var c = Actor.new(); root.add_child(c)
		f.m.register_actor(3,c,-1,"teknium")
		f.m.reset_with_collision_profiles({1:Vector3(0,5.1,0),2:Vector3(0,2.02,0),3:Vector3.ZERO},{1:fitted("teknium"),2:fitted("turbofit"),3:fitted("teknium")},"legacy_solid")
		for id in [1,2]:
			f.m.fighters[id].actor.runtime.velocity.y = -12
			f.m.fighters[id].actor.velocity.y = -12
		var chain = false
		for i in 35:
			await step(f.m)
			var middle = f.m.top_support_telemetry(2)
			if not middle.relation.is_empty():
				check(middle.geometry.pose_category == "supported" and is_equal_approx(middle.geometry.height,2.396),"accepted carrier stance owns upright source head immediately, no airborne envelope")
			var upper = f.m.top_support_telemetry(1)
			if not upper.relation.is_empty() and upper.relation.carrier == 2 and not middle.relation.is_empty():
				chain = true
				check(absf(upper.relation.plane-(f.b.position.y+middle.geometry.height))<.0001,"stack commits from final lower actor/head, no stale plane")
				check(absf(f.a.position.y+upper.relation.sole_offset-upper.relation.plane)<.0001,"stack rider sole meets committed carrier head")
				break
		check(chain,"real three-actor supported chain prerequisite")
		c.free(); dispose(f)
	if not failures: print("PASS: committed supported stack head ownership")
	quit(1 if failures else 0)
