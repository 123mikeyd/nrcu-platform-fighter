extends "res://tests/test_core_ledge_match.gd"
func run():
	for side in [-1,1]:
		for reverse in [false,true]:
			for facing in [-1,1]:
				for stopped in [false,true]:
					var terrain = body(Vector3(-2*side,-0.5,0),Vector3(4,1,4))
					var m = load("res://scripts/core/match/match_simulation.gd").new()
					for id in ([2,1] if reverse else [1,2]):
						var actor = Actor.new(); root.add_child(actor); m.register_actor(id,actor)
					var anchor = Anchor.new(); anchor.anchor_id = "edge"; anchor.outward = side
					m.configure_ledges([anchor],LedgePolicy.new())
					m.reset({1:Vector3(side,-1,0),2:Vector3(-8*side,3,0)})
					await tick(m,{1:frame(false,-side)})
					check(m.ledge_telemetry(1).anchor_id == "edge","native catch prerequisite")
					var a = m.fighters[1].actor; var b = m.fighters[2].actor
					m.fighters[1].facing = facing; m.fighters[2].facing = facing
					var at: Vector3 = a.position
					b.reset_at(Vector3(side*1.6,-1.5,0)); b.apply_combat_launch(Vector3(-side*5,0,0),30)
					if stopped: m.fighters[1].hitstop_left = 30
					var collided = false
					for i in 6:
						await tick(m)
						for j in b.get_slide_collision_count():
							var c = b.get_slide_collision(j)
							for k in c.get_collision_count():
								if c.get_collider(k) == a: collided = true
						check(a.position == at and m.ledge_telemetry(1).anchor_id == "edge","legal native side touch preserves held anchor")
					check(collided,"live approach reaches held/stopped capsule")
					var q = PhysicsShapeQueryParameters3D.new(); q.shape = a.get_node("CoreCapsule").shape
					q.transform = Transform3D(Basis.IDENTITY,at+Vector3(0,0.9,0)); q.collision_mask = 2; q.exclude = [a.get_rid()]; q.margin = 0
					check(a.get_world_3d().direct_space_state.intersect_shape(q).is_empty(),"native legal contact is not penetration")
					if stopped:
						m.fighters[1].hitstop_left = 0
						await tick(m)
						check(a.position == at and m.ledge_telemetry(1).anchor_id == "edge","resumed hanger accepts same legal side contact")
					# Actual overlap must still release, including after a stopped hold.
					b.reset_at(at+Vector3(side*0.7,0,0)); m.fighters[2].hitstop_left = 10
					await tick(m)
					check(m.ledge_events.get(1,{}).get("transition","") == "blocked" and m.ledge_telemetry(1).anchor_id == "","penetrating body blocks hang")
					check(m.ledge_events.get(1,{}).get("path",[]).is_empty(),"blocked overlap commits no ledge path; native penetration recovery remains owned by mover")
					cleanup(m); terrain.free()
	# Keep terrain's conservative margin, start overlap, thin sweeps and elbows.
	var a = Actor.new(); root.add_child(a); a.reset_at(Vector3(20,20,0))
	var shape = a.get_node("CoreCapsule").shape; var offset = Vector3(0,0.9,0); var policy = LedgePolicy.new()
	var wall = body(Vector3(0.9005,1,0),Vector3(1,4,4))
	await physics_frame
	check(not policy.terrain_path_clear(a.get_world_3d().direct_space_state,shape,offset,[Vector3.ZERO],3,[a.get_rid()]),"terrain margin-only obstruction retained")
	wall.free()
	wall = body(Vector3(0,1,0),Vector3(0.01,4,4)); await physics_frame
	check(not policy.terrain_path_clear(a.get_world_3d().direct_space_state,shape,offset,[Vector3(-1,0,0),Vector3(1,0,0)],3,[a.get_rid()]),"thin wall sweep remains blocked")
	check(not policy.terrain_path_clear(a.get_world_3d().direct_space_state,shape,offset,[Vector3.ZERO,Vector3(-1,0,0)],3,[a.get_rid()]),"initial terrain penetration remains blocked")
	wall.free()
	var stage = body(Vector3(2,-0.5,0),Vector3(4,1,4)); await physics_frame
	var anchor = Anchor.new()
	var elbow = Vector3(anchor.hang().x,anchor.climb().y,0)
	check(policy.terrain_path_clear(a.get_world_3d().direct_space_state,shape,offset,[anchor.hang(),elbow,anchor.climb()],3,[a.get_rid()]),"full outside-up-in elbow remains legal")
	check(not policy.terrain_path_clear(a.get_world_3d().direct_space_state,shape,offset,[anchor.hang(),anchor.climb()],3,[a.get_rid()]),"diagonal shortcut through stage remains blocked")
	var roof = body(elbow+Vector3(0,1.7,0),Vector3(0.1,0.1,4)); await physics_frame
	check(not policy.terrain_path_clear(a.get_world_3d().direct_space_state,shape,offset,[anchor.hang(),elbow,anchor.climb()],3,[a.get_rid()]),"roof blocks intermediate climb waypoint")
	roof.free(); stage.free(); a.free()
	if not failures: print("PASS body review ledge (%d checks)" % checks)
	quit(1 if failures else 0)
