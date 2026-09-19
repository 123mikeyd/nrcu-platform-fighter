extends "res://tests/test_core_collision_snapshot.gd"
func run() -> void:
	var p = fixture(); p.hurtboxes[0].local_transform = Transform3D.IDENTITY
	p.hurtboxes[0].radius = 4.6218109130859375; p.hurtboxes[0].height = 9.243621826171875
	var service = load(BUILDER).new(); service.configure(p,p.source_asset,p.source_sha256,"rounding")
	for origin in [Vector3(-95.24089050292969,33.11,91.3),Vector3(1e7,-1e7,0.00003),Vector3.ZERO]:
		var result: Dictionary = service.build("a",{"Hand":Transform3D(Basis.IDENTITY,origin)},Transform3D.IDENTITY,revision(p))
		check(result.ok,"finite rounding fixture")
		for c in result.primitives:
			for axis in 3:
				check(float(result.aabb.position[axis]) <= minf(c.a[axis],c.b[axis])-float(c.radius),"lower bound rounds outward")
				check(float(result.aabb.end[axis]) >= maxf(c.a[axis],c.b[axis])+float(c.radius),"upper bound rounds outward")
	var bad: Dictionary = service.build("a",{},Transform3D.IDENTITY,revision(p))
	check(not bad.ok and not bad.participation.get("active",true),"invalid snapshot cannot participate")
	if not failures: print("PASS: collision snapshot conservative float bounds")
	quit(1 if failures else 0)
