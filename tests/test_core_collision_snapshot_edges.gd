extends "res://tests/test_core_collision_snapshot.gd"
func run() -> void:
	var p = fixture(); var service = load(BUILDER).new()
	service.configure(p,p.source_asset,p.source_sha256,"draft")
	var pose := {"Hand":Transform3D.IDENTITY}
	for filters in [{"enabled":"false"},{"enabled_hurtbox_ids":PackedStringArray(["unknown"])},{"enabled_hurtbox_ids":PackedStringArray(["arm","arm"])},{"team_id":{}},{"unsupported_filter":true}]:
		var result: Dictionary = service.build("a",pose,Transform3D.IDENTITY,revision(p),filters)
		check(not result.ok and result.primitives.is_empty() and not result.has_bounds and not result.diagnostics.is_empty(),"malformed participation rejected")
	var rev := revision(p); rev.extra = Resource.new()
	check(not service.build("a",pose,Transform3D.IDENTITY,rev).ok,"unknown pose metadata cannot retain external object")
	# Individually finite primitives can overflow their combined Vector3 AABB.
	var q = fixture(); var extra = q.hurtboxes[0].duplicate(true); extra.hurtbox_id = "other"; extra.bone_name = "Other"; q.hurtboxes.append(extra)
	service.configure(q,q.source_asset,q.source_sha256,"wide")
	var wide := {"Hand":Transform3D(Basis.IDENTITY,Vector3(-3e38,0,0)),"Other":Transform3D(Basis.IDENTITY,Vector3(3e38,0,0))}
	var bounds: Dictionary = service.build("a",wide,Transform3D.IDENTITY,revision(q))
	check(not bounds.ok and not bounds.has_bounds and bounds.primitives.is_empty(),"nonfinite union bounds fail closed")
	if not failures: print("PASS: collision snapshot malformed filters and bounds")
	quit(1 if failures else 0)
