extends "res://tests/test_core_ledge_policy.gd"

func run():
	var stage = load("res://scripts/core/stage/combat_lab_stage.gd").new()
	check(stage.has_method("geometry"), "immutable authored geometry descriptors exist")
	if failures: finish(); return
	var descriptors: Array = stage.geometry()
	check(descriptors.is_read_only() and descriptors.size() == 1, "one immutable main platform descriptor")
	var d: Dictionary = descriptors[0]
	check(d.is_read_only(), "descriptor itself is immutable")
	check(d.id == "combat_lab.main" and d.position == Vector3(0, -0.4, 0) and d.size == Vector3(24, 0.8, 3), "exact authored collider dimensions")
	check(d.collision_layer == 1 and d.collision_mask == 0 and not d.pass_through, "solid terrain filtering authored")
	# Instantiate the actual lab, not a hand-built approximation of its terrain.
	var lab = load("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(lab)
	lab.set_physics_process(false)
	var bodies: Array = lab.find_children("*", "StaticBody3D", true, false)
	check(bodies.size() == descriptors.size(), "actual lab has no unaccounted extra platforms")
	if bodies.size() != 1: lab.free(); finish(); return
	var terrain: StaticBody3D = bodies[0]
	var collider: CollisionShape3D = terrain.get_child(0)
	check(collider.shape is BoxShape3D, "actual lab main collider is box")
	check(terrain.global_position == d.position and collider.position == Vector3.ZERO and collider.shape.size == d.size, "descriptor agrees with actual collider, not visual mesh")
	check(terrain.global_basis == Basis.IDENTITY and collider.basis == Basis.IDENTITY, "authored fixed world-aligned terrain")
	check(terrain.collision_layer == d.collision_layer and terrain.collision_mask == d.collision_mask and not terrain.is_in_group("core_pass_through"), "actual solid collision filtering agrees")
	var capsule: CollisionShape3D = lab.actors[0].get_node("CoreCapsule")
	check(capsule.shape is CapsuleShape3D and is_equal_approx(capsule.shape.radius, 0.4) and is_equal_approx(capsule.shape.height, 1.8) and capsule.position.is_equal_approx(Vector3(0, 0.9, 0)), "use actual actor foot-origin capsule")
	var policy = load("res://scripts/core/stage/ledge_policy.gd").new()
	await physics_frame; await physics_frame
	var clear = func(points): return policy.terrain_path_clear(root.world_3d.direct_space_state, capsule.shape, capsule.position, points)
	for a in stage.create_anchors():
		var side: int = a.outward
		var edge := terrain.global_position + Vector3(side * collider.shape.size.x / 2, collider.shape.size.y / 2, 0)
		check(a.edge.is_equal_approx(edge), "anchor equals real collider edge: " + a.anchor_id)
		var start: Vector3 = a.edge + Vector3(side * 1.4, -1, 0)
		var actors := {1: actor(start, Vector3(-side, -1, 0))}
		check(clear.call([start, a.hang()]), "actual stage mirrored catch sweep clears")
		var caught = policy.advance({}, actors, [a], 0, clear)
		check(caught.proposals.get(1, {}).get("transition") == "catch", "valid approach catches against actual stage")
		actors[1].position = a.hang(); actors[1].intent = "climb"
		var climbed = policy.advance(caught.state, actors, [a], 1, clear)
		check(climbed.proposals.get(1, {}).get("transition") == "climb", "mirrored actual stage elbow climb clears")
		check(climbed.proposals[1].path == [a.hang(), a.hang(), Vector3(a.hang().x, a.climb().y, 0), a.climb()], "policy preserves outside-up-then-in waypoints")
		check(not clear.call([a.hang(), a.climb()]), "diagonal shortcut hits actual platform")
		# Outer/Y/Z inclusive eligibility boundaries; clearance separately rejects volume overlap.
		for y in [-1.8, -0.4]:
			for z in [-0.5, 0.5]:
				var at: Vector3 = a.edge + Vector3(side * 1.4, y, z)
				check(a.eligible(actor(at, Vector3(-side, 0, 0))) and clear.call([at, a.hang()]), "mirrored valid approach window corner clears")
		for delta in [Vector3(side * 1.41, -1, 0), Vector3(0, -1, 0), Vector3(-side, -1, 0), Vector3(side, -1.81, 0), Vector3(side, -0.39, 0), Vector3(side, -1, 0.51)]:
			check(not a.eligible(actor(a.edge + delta, Vector3(-side, -1, 0))), "outside authored approach window denied")
		check(not a.eligible(actor(start, Vector3(side, -1, 0))) and not a.eligible(actor(start, Vector3(-side, 1, 0))), "outward and rising approaches denied")
		# A thin obstruction lies between free endpoints; no start-overlap substitute.
		var behind: Vector3 = a.edge + Vector3(side * 3, -1.5, 0)
		var wall = body(a.edge + Vector3(side * 1.8, -0.4, 0), Vector3(0.06, 3, 3))
		await physics_frame; await physics_frame
		check(clear.call([behind]) and clear.call([a.hang()]), "wall test endpoints independently clear")
		check(not clear.call([behind, a.hang()]), "behind-wall catch sweep denied")
		wall.free()
		var roof = body(a.edge + Vector3(side * 0.65, 1, 0), Vector3(1, 0.1, 3))
		await physics_frame; await physics_frame
		check(clear.call([a.hang()]) and clear.call([a.climb()]), "roof leaves hang and final landing clear")
		var blocked = policy.advance(caught.state, actors, [a], 1, clear)
		check(blocked.proposals.get(1, {}).get("transition") == "blocked", "roof denies full climb")
		roof.free()
		await physics_frame; await physics_frame
		var overlapping: Vector3 = a.edge + Vector3(-side * 0.2, -0.4, 0)
		check(not clear.call([overlapping, a.hang()]), "actual main platform initial overlap denied")
		var near_wall: Vector3 = a.edge + Vector3(side * 0.05, -0.4, 0)
		check(a.eligible(actor(near_wall, Vector3(-side, -1, 0))) and not clear.call([near_wall, a.hang()]), "eligibility alone cannot authorize overlapping capsule")
	lab.free()
	finish()

func body(at: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.position = at; b.collision_layer = 1; b.collision_mask = 0
	var c := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = size; c.shape = box
	b.add_child(c); root.add_child(b)
	return b
