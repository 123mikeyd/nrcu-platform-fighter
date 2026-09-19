extends "res://tests/test_core_top_support_native.gd"
func run():
	for reverse in [false,true]:
		var f = setup_pair("teknium","teknium",reverse)
		reset_drop(f,0,0.1); await acquire(f)
		var anchor = load("res://scripts/core/stage/ledge_anchor.gd").new()
		anchor.anchor_id = "support-release-ledge"; anchor.edge = Vector3(0.8,3.4,0)
		var wall = StaticBody3D.new(); var c = CollisionShape3D.new(); var box = BoxShape3D.new()
		box.size = Vector3(4.4,1,4); c.shape = box; wall.add_child(c); wall.position = Vector3(3,2.9,0); root.add_child(wall)
		f.m.configure_ledges([anchor],load("res://scripts/core/stage/ledge_policy.gd").new())
		await step(f.m)
		check(f.m.ledge_telemetry(1).anchor_id == anchor.anchor_id,"real authored ledge catch from acquired support prerequisite")
		check(f.m.top_support_telemetry(1).relation.is_empty(),"ledge catch releases support on same committed tick")
		wall.free(); dispose(f)
	if not failures: print("PASS: top support handoff to authored native ledge")
	quit(1 if failures else 0)
