extends "res://tests/test_core_top_support_lifecycle.gd"
func run():
	var f = setup_pair("teknium","turbofit")
	await acquire(f)
	var t = f.m.top_support_telemetry(2)
	check(t.geometry.has("world_segment") and t.body.has("world_transform"),"debug API exposes authoritative world support segment and full native core transform")
	if t.geometry.has("world_segment") and t.body.has("world_transform"):
		check(t.body.world_transform == f.b.get_node("CoreCapsule").global_transform,"actual installed shape transform")
		check(is_equal_approx(t.geometry.world_segment[0].y,f.b.position.y+t.geometry.height) and t.geometry.world_segment[1].y == t.geometry.world_segment[0].y,"actual support plane endpoints")
		var left = t.geometry.world_segment[0]
		t.geometry.world_segment[0] = Vector3(999,999,999)
		check(f.m.top_support_telemetry(2).geometry.world_segment[0] == left,"detached debug geometry")
	dispose(f)
	if not failures: print("PASS: authoritative read-only top-support geometry API")
	quit(1 if failures else 0)
