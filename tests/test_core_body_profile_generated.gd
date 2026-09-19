extends "res://tests/test_core_body_profile_ledge.gd"
func run():
	for character in ["teknium","turbofit"]:
		var source = load("res://data/collision/generated/"+character+".tres")
		check(source != null and source.validate().is_empty(), "actual generated draft schema validates: " + character)
		if source == null: continue
		var before = [source.body_center,source.foot_origin,source.body_radius,source.body_height]
		var a = Actor.new()
		check(a.configure_body_profile(source), "install actual generated offset capsule without recentering: " + character)
		root.add_child(a)
		var collider = a.get_node("CoreCapsule")
		check(collider.position == source.body_center and is_equal_approx(collider.shape.radius,source.body_radius) and is_equal_approx(collider.shape.height,source.body_height), "actual draft dimensions and offset retained")
		check(a.position == Vector3.ZERO and a.basis == Basis.IDENTITY, "source rest foot metadata never translates or scales native actor")
		check(before == [source.body_center,source.foot_origin,source.body_radius,source.body_height], "source resource unchanged")
		print("DRAFT_NOT_APPROVED_BALANCE ",character," radius=",source.body_radius," height=",source.body_height," center=",source.body_center)
		a.free()
	if not failures: print("PASS body profile generated (%d checks)" % checks)
	quit(1 if failures else 0)
