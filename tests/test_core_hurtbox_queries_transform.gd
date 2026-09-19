extends "res://tests/test_core_hurtbox_queries_sweep.gd"
func run() -> void:
	check(q.has_method("capsule_from_transform"), "transform API exists")
	if not q.has_method("capsule_from_transform"): return
	for scale in [0.25, 1.0, 3.0]:
		for rotation in [Basis.IDENTITY, Basis(Vector3.FORWARD, PI/2), Basis(Vector3(1, 2, 3).normalized(), 0.7)]:
			for facing in [-1.0, 1.0]:
				var basis: Basis = rotation.scaled(Vector3(scale*facing, scale, scale))
				var tr := Transform3D(basis, Vector3(4, -2, 3))
				var c: Dictionary = q.capsule_from_transform("limb", tr, 3.0, 0.5)
				check(not c.is_empty(), "uniform rotated/reflected transform accepted")
				if c.is_empty(): continue
				check(c.a.is_equal_approx(tr * Vector3(0, -1, 0)) and c.b.is_equal_approx(tr * Vector3(0, 1, 0)), "height includes caps; endpoints on local Y")
				check(is_equal_approx(c.radius, 0.5 * scale), "radius scaled once")
				hit(tr * Vector3(-10, 0, 0), tr * Vector3(10, 0, 0), 0.5*scale, c, 0.45, "rigid/scale/facing invariant")
	var ball: Dictionary = q.capsule_from_transform("ball", Transform3D.IDENTITY, 1, 0.5)
	check(ball.a == ball.b, "diameter height yields sphere")
	for tr in [Transform3D(Basis.from_scale(Vector3(1, 2, 1)), Vector3.ZERO), Transform3D(Basis(Vector3(1, 0, 0), Vector3(0.1, 1, 0), Vector3(0, 0, 1)), Vector3.ZERO), Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO), Transform3D(Basis.IDENTITY, Vector3(INF, 0, 0))]:
		check(q.capsule_from_transform("bad", tr, 3, 0.5).is_empty(), "unsupported transform fails closed")
	for values in [[-1.0, 0.5], [0.9, 0.5], [3.0, 0.0], [INF, 0.5], [3.0, NAN]]:
		check(q.capsule_from_transform("bad", Transform3D.IDENTITY, values[0], values[1]).is_empty(), "invalid dimensions fail closed")
