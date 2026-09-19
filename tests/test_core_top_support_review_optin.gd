extends "res://tests/test_core_top_support_review_trajectory.gd"
func run():
	for participant in [1,2]:
		for endpoint in ["start","end"]:
			for invalid in [{},{"height":1.9,"half_width":0.4},{"height":NAN,"half_width":0.4,"foot_radius":0.12},{"height":1.9,"half_width":-0.4,"foot_radius":0.12}]:
				var solver = Solver.new()
				var start = {1:snap(0,2,-12),2:snap(0,0,0)}
				var end = {1:snap(0,1.8,-12),2:snap(0,0,0)}
				if endpoint == "start": start[participant].profile = invalid
				else: end[participant].profile = invalid
				solver.begin(start)
				check(not solver.solve(end,1).has(1),"both endpoints of both participants need complete finite positive support geometry")
	for opted_id in [1,2]:
		for reverse in [false,true]:
			var floor_node = floor_body(); var m = Match.new(); var a = Actor.new(); var b = Actor.new()
			root.add_child(a); root.add_child(b)
			if reverse: m.register_actor(2,b,-1,"teknium"); m.register_actor(1,a,-1,"teknium")
			else: m.register_actor(1,a,-1,"teknium"); m.register_actor(2,b,-1,"teknium")
			check(m.reset_with_collision_profiles({1:Vector3(0,2,0),2:Vector3.ZERO},{opted_id:fitted("teknium")},"legacy_solid"),"legal partial opt-in reset")
			a.runtime.velocity.y = -12; a.velocity = a.runtime.velocity
			await step(m)
			check(m.top_support_telemetry(1).relation.is_empty(),"partial install never enables pair support")
			check(m.top_support_telemetry(3-opted_id).geometry.is_empty(),"omitted actor remains opted out")
			a.free(); b.free(); floor_node.free()
	if not failures: print("PASS: bilateral support opt-in regression (%d checks)" % checks)
	quit(1 if failures else 0)
