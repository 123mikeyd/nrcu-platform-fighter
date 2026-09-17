extends "res://tests/test_core_collision_snapshot.gd"
const Queries = preload("res://scripts/core/collision/hurtbox_queries.gd")
func run() -> void:
	var q = Queries.new()
	check(q.has_method("capsule_enclosing_affine"),"separate conservative affine converter")
	if failures: quit(1); return
	for basis in [Basis.IDENTITY,Basis.from_scale(Vector3(2,3,0.5)),Basis(Vector3(1,0,0),Vector3(2,1,0),Vector3(0,0,1)),Basis.from_scale(Vector3(-2,2,2)),Basis(Vector3.UP,0.7)*Basis.from_scale(Vector3(1,4,2)),Basis(Vector3(1,0,0),Vector3(0.0000003,1,0),Vector3(0,0,1))]:
		var t: Transform3D = Transform3D(basis,Vector3(31.7,-5.2,0.3))
		var c: Dictionary = q.call("capsule_enclosing_affine","test",t,4.0,0.5)
		check(not c.is_empty(),"finite nonsingular affine including reflection supported")
		if c.is_empty(): continue
		check(c.a.is_equal_approx(t*Vector3(0,-1.5,0)) and c.b.is_equal_approx(t*Vector3(0,1.5,0)),"spine not orthonormalized")
		check(c.has("mapping") and c.has("radius_scale_bound") and c.has("inflation_factor"),"enclosure explicitly labeled with inflation telemetry")
		for k in 1000:
			var y := 1.0-2.0*(k+0.5)/1000.0; var r := sqrt(1-y*y); var angle := k*2.399963229728653
			# Use scalar double matrix products, not production query arithmetic.
			var v := [0.5*r*cos(angle),0.5*y,0.5*r*sin(angle)]
			var norm2 := 0.0
			for axis in 3:
				var value: float = basis.x[axis]*v[0]+basis.y[axis]*v[1]+basis.z[axis]*v[2]
				norm2 += value*value
			check(norm2 <= c.radius*c.radius,"operator bound contains transformed crosssection")
		if basis == Basis.IDENTITY: check(is_equal_approx(c.radius,0.5),"uniform exact radius preserved within storage rounding")
	var shear := Transform3D(Basis(Vector3(1,0,0),Vector3(2,1,0),Vector3(0,0,1)),Vector3.ZERO)
	check(Queries.capsule_from_transform("strict",shear,4,0.5).is_empty(),"strict exact converter still rejects shear")
	for t in [Transform3D(Basis.from_scale(Vector3(1,0,1)),Vector3.ZERO),Transform3D(Basis.IDENTITY,Vector3(INF,0,0)),Transform3D(Basis(Vector3(1,1,0),Vector3(1,1,0),Vector3(0,0,1)),Vector3.ZERO)]:
		check(q.call("capsule_enclosing_affine","bad",t,4,0.5).is_empty(),"singular/nonfinite fail closed")
	if not failures: print("PASS: affine capsule transform bound and strict boundary")
	quit(1 if failures else 0)
