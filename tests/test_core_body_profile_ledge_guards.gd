extends "res://tests/test_core_body_profile_ledge.gd"
func run():
	for side in [-1,1]:
		for large in [false,true]:
			for obstruction in ["roof","wall","initial","none"]:
				var radius = 0.6 if large else 0.25; var height = 2.8 if large else 1.0
				var terrain = block(Vector3(-side*2,-0.5,0),Vector3(4,1,4))
				var m = Match.new(); var a = Actor.new(); var b = Actor.new()
				a.configure_body_profile(body_profile(radius,height)); b.configure_body_profile(body_profile(0.3,1.4))
				root.add_child(a); root.add_child(b); m.register_actor(2,a); m.register_actor(1,b)
				m.reset({2:Vector3(side*1.2,-1,0),1:Vector3(-side*8,4,0)})
				var anchor = Anchor.new(); anchor.anchor_id = "edge"; anchor.outward = side
				m.configure_ledges([anchor],Policy.new())
				var f = Frame.new(); f.axis.x = -side
				await step(m,{2:f})
				check(m.ledge_telemetry(2).anchor_id == "edge", "guard fixture actual catch prerequisite")
				var at = a.position; var shape = a.get_node("CoreCapsule").shape
				check(not a.configure_body_profile(body_profile(0.1,0.4)), "no live ledge body shrinking")
				m.fighters[2].hitstop_left = 2
				var clock = a.runtime.tick
				await step(m); await step(m)
				check(a.position == at and a.runtime.tick == clock and m.ledge_telemetry(2).anchor_id == "edge", "stopped unequal hanger retains placement and occupancy")
				var obstacle = null
				if obstruction == "roof": obstacle = block(Vector3(at.x,0.65,0),Vector3(radius*2+0.1,0.1,4))
				if obstruction == "wall": obstacle = block(Vector3(side*0.03,1.5,0),Vector3(0.04,3,4))
				if obstruction == "initial": obstacle = block(at+Vector3(0,height/2,0),Vector3(0.1,0.1,0.1))
				# Evaluate the unchanged full-body route directly before native movement
				# can recover an intentionally inserted invalid overlap.
				var snapshot = {"body":{"radius":radius,"height":height}}
				var path = [at,Vector3(at.x,0.06,0),anchor.climb(snapshot)]
				await physics_frame
				var exclude: Array[RID] = [a.get_rid()]
				var clear = m.ledge_policy.terrain_path_clear(a.get_world_3d().direct_space_state,shape,a.get_node("CoreCapsule").transform,path,3,exclude)
				check(clear == (obstruction == "none"), "whole profile route respects " + obstruction)
				check(a.position == at and a.get_node("CoreCapsule").shape == shape, "query never partially warps or shrinks body")
				if obstacle != null: obstacle.free()
				a.free(); b.free(); terrain.free()
	if not failures: print("PASS body profile ledge guards (%d checks)" % checks)
	quit(1 if failures else 0)
