extends "res://tests/test_core_collision_snapshot.gd"
func run() -> void:
	var p = fixture(); p.hurtboxes[0].local_transform = Transform3D.IDENTITY
	var service = load(BUILDER).new(); var other = load(BUILDER).new()
	check(service.configure(p,p.source_asset,p.source_sha256,"policy","conservative_affine").is_empty(),"explicit affine policy")
	other.configure(p,p.source_asset,p.source_sha256,"policy")
	var pose := {"Hand":Transform3D(Basis(Vector3(1,0,0),Vector3(2,1,0),Vector3(0,0,1)),Vector3.ZERO)}
	var world := Transform3D(Basis.from_scale(Vector3.ONE*2),Vector3.ZERO)
	var result: Dictionary = service.build("id",pose,world,revision(p))
	check(result.ok and result.transform_policy == "conservative_affine","policy disclosed")
	check(not result.diagnostics.is_empty() and "large affine enclosure" in str(result.diagnostics),"large affine approximation warning returned not engine spam")
	check(not other.build("id",pose,world,revision(p)).ok,"default exact remains fail closed")
	if result.ok:
		var c: Dictionary = result.primitives[0]
		check(c.a == Vector3(-4,-2,0) and c.b == Vector3(4,2,0),"preserve shear spine; visual_scale 19 and foot_origin never reapplied")
		check(c.radius < 3 and c.radius >= sqrt(7.0),"operator radius conservative but not double scaled")
		check(c.mapping == "conservative_affine_enclosure" and c.inflation_factor > 1.05,"telemetry identifies enclosure")
		var captured := result.duplicate(true)
		result.primitives[0].radius = 999; result.diagnostics.clear()
		check(service.build("id",pose,world,revision(p)) == captured,"cached telemetry and primitives private")
		service.reset(); check(service.build("id",pose,world,revision(p)) == captured,"reset retains policy")
	for bad in [{},{"Hand":Transform3D(Basis.from_scale(Vector3(1,0,1)),Vector3.ZERO)},{"Hand":Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))}]:
		var invalid: Dictionary = service.build("id",bad,world,revision(p))
		check(not invalid.ok and invalid.primitives.is_empty() and not invalid.has_bounds,"affine preserves missing/singular/nonfinite error; no body fallback")
	var rev := revision(p); rev.source_sha256 = "0".repeat(64)
	check(not service.build("id",pose,world,rev).ok,"affine preserves identity guard")
	check(not service.configure(p,p.source_asset,p.source_sha256,"policy","normalize").is_empty(),"unknown policy rejected")
	check(service.cache_size() == 0 and not service.build("id",pose,world,revision(p)).ok,"failed reconfigure clears prior policy/profile/cache")
	if not failures: print("PASS: affine snapshot policy warnings and lifecycle")
	quit(1 if failures else 0)
