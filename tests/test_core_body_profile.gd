extends "res://tests/test_core_grab_slice.gd"
const CollisionProfile = preload("res://scripts/core/collision/character_collision_profile.gd")
func body_profile(radius: float, height: float):
	var p = CollisionProfile.new()
	p.character_id = "synthetic-body"
	p.body_radius = radius; p.body_height = height; p.body_center = Vector3(0,height / 2,0)
	return p
func run():
	var a = Actor.new(); var b = Actor.new(); var c = Actor.new()
	check(a.has_method("configure_body_profile"), "explicit independent movement-body configuration API")
	if not a.has_method("configure_body_profile"):
		a.free(); b.free(); c.free(); quit(1); return
	var p = body_profile(0.6,2.8)
	check(a.configure_body_profile(p) and b.configure_body_profile(p), "configure before first physics")
	root.add_child(a); root.add_child(b); root.add_child(c)
	var sa = a.get_node("CoreCapsule"); var sb = b.get_node("CoreCapsule"); var sc = c.get_node("CoreCapsule")
	check(is_equal_approx(sa.shape.radius, 0.6) and is_equal_approx(sa.shape.height, 2.8) and sa.position == Vector3(0,1.4,0), "requested native capsule at foot origin")
	check(sa.shape != sb.shape, "duplicate actors have independent shape resources")
	check(is_equal_approx(sc.shape.radius, 0.4) and is_equal_approx(sc.shape.height, 1.8) and sc.position == Vector3(0,0.9,0), "exact compatibility capsule")
	p.body_radius = 0.9
	check(is_equal_approx(sa.shape.radius, 0.6) and is_equal_approx(sb.shape.radius, 0.6), "definition mutation cannot resize installed bodies")
	a.reset_at(Vector3(2,3,0))
	check(is_equal_approx(sa.shape.radius, 0.6) and is_equal_approx(sa.shape.height, 2.8), "reset retains selected dimensions")
	check(a.basis == Basis.IDENTITY and a.up_direction == Vector3.UP, "unscaled upright native actor")
	a.free(); b.free(); c.free()
	if not failures: print("PASS body profile (%d checks)" % checks)
	quit(1 if failures else 0)
