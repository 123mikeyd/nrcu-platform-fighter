extends "res://tests/test_core_ledge_policy.gd"
func body(at: Vector3, size: Vector3) -> StaticBody3D:
	var b = StaticBody3D.new(); b.position = at
	var c = CollisionShape3D.new(); var box = BoxShape3D.new(); box.size = size; c.shape = box
	b.add_child(c); root.add_child(b); return b
func run():
	var p = load("res://scripts/core/stage/ledge_policy.gd").new()
	check(p.has_method("terrain_path_clear"), "real terrain shape sweep adapter exists")
	if failures: finish(); return
	var shape = CapsuleShape3D.new(); shape.radius = 0.4; shape.height = 1.8
	var terrain = body(Vector3(2,-0.5,0), Vector3(4,1,4))
	await physics_frame; await physics_frame
	var space = root.world_3d.direct_space_state
	var clear = func(points): return p.terrain_path_clear(space, shape, Vector3(0,0.9,0), points)
	var a = load("res://scripts/core/stage/ledge_anchor.gd").new(); a.anchor_id = "edge"
	var actors = {1: actor(Vector3(-1,-1,0), Vector3(1,-1,0))}
	var caught = p.advance({}, actors, [a], 0, clear)
	check(caught.proposals.get(1, {}).get("transition") == "catch", "real platform allows outside catch")
	actors[1].position = a.hang(); actors[1].intent = "climb"
	var climb = p.advance(caught.state, actors, [a], 1, clear)
	check(climb.proposals[1].transition == "climb", "outside-up-then-in climb clears real platform")
	check(not clear.call([a.hang(), a.climb()]), "direct diagonal teleport intersects stage wall")
	var wall = body(Vector3(-0.82,-0.3,0), Vector3(0.06,3,4))
	await physics_frame; await physics_frame
	actors[1].position = Vector3(-1.4,-1,0); actors[1].intent = ""
	var blocked = p.advance({}, actors, [a], 0, clear)
	check(blocked.proposals.is_empty(), "thin wall blocks full catch sweep")
	wall.free()
	var roof = body(Vector3(-0.65,1,0), Vector3(1,0.1,4))
	await physics_frame; await physics_frame
	actors[1].position = a.hang(); actors[1].intent = "climb"
	blocked = p.advance(caught.state, actors, [a], 1, clear)
	check(blocked.proposals[1].transition == "blocked", "roof blocks climb path even with free destination")
	check(not clear.call([Vector3(2,-0.5,0), Vector3(2,3,0)]), "initial overlap fails closed")
	check(not clear.call([]), "empty path fails closed")
	roof.free(); terrain.free()
	finish()
