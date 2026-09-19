extends "res://tests/test_core_collision_snapshot.gd"
func run() -> void:
	var service = load(BUILDER).new()
	for kind in ["duplicate","empty_id","whitespace_id","bad_version","bad_hash","mismatch_hash","mismatch_asset","empty_revision","no_hurtboxes","dimensions","local_scale"]:
		var p = fixture(); var asset: String = p.source_asset; var sha: String = p.source_sha256; var rev := "draft"
		match kind:
			"duplicate": p.hurtboxes.append(p.hurtboxes[0].duplicate(true))
			"empty_id": p.hurtboxes[0].hurtbox_id = ""
			"whitespace_id": p.hurtboxes[0].hurtbox_id = " "
			"bad_version": p.generator_version = 999
			"bad_hash": p.source_sha256 = "not-a-sha"
			"mismatch_hash": sha = "0".repeat(64)
			"mismatch_asset": asset = "res://wrong.glb"
			"empty_revision": rev = ""
			"no_hurtboxes": p.hurtboxes.clear()
			"dimensions": p.hurtboxes[0].radius = NAN
			"local_scale": p.hurtboxes[0].local_transform.basis = Basis.from_scale(Vector3(1,2,1))
		var errors: PackedStringArray = service.configure(p,asset,sha,rev)
		check(not errors.is_empty(), "fail closed profile: " + kind)
		if not errors.is_empty():
			var invalid: Dictionary = service.build("entity",{},Transform3D.IDENTITY,revision(p))
			check(not invalid.ok and invalid.primitives.is_empty() and not invalid.has_bounds, "failed configure invalidates source")
	if not failures: print("PASS: collision snapshot profile validation")
	quit(1 if failures else 0)
