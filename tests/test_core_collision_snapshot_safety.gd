extends "res://tests/test_core_collision_snapshot.gd"
func run() -> void:
	var p = fixture(); var service = load(BUILDER).new()
	service.configure(p,p.source_asset,p.source_sha256,"draft")
	var pose := {"Hand":Transform3D.IDENTITY}
	for kind in ["source","hash","seconds","clip","episode","policy","missing_time","blend"]:
		var rev := revision(p)
		match kind:
			"source": rev.source_asset = "res://wrong.glb"
			"hash": rev.source_sha256 = "0".repeat(64)
			"seconds": rev.seconds = NAN
			"clip": rev.clip = ""
			"episode": rev.episode_id = ""
			"policy": rev.policy = 99
			"missing_time": rev.erase("seconds")
			"blend": rev.blend = 0.5
		var result: Dictionary = service.build("entity",pose,Transform3D.IDENTITY,rev)
		check(not result.ok and not result.diagnostics.is_empty() and result.primitives.is_empty() and not result.has_bounds, "invalid pose identity: " + kind)
	# Run malformed geometry after identity rejection exists, avoiding absent-feature indexing errors in RED.
	if failures == 0:
		for bad in [{}, {"Hand":Vector3.ZERO}, {"Hand":Transform3D(Basis.from_scale(Vector3(1,2,1)),Vector3.ZERO)}, {"Hand":Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))}]:
			var result: Dictionary = service.build("entity",bad,Transform3D.IDENTITY,revision(p))
			check(not result.ok and result.primitives.is_empty() and not result.diagnostics.is_empty(), "malformed/missing bone fails closed")
		for world in [Transform3D(Basis.from_scale(Vector3(1,2,1)),Vector3.ZERO),Transform3D(Basis.IDENTITY,Vector3(INF,0,0)),Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO)]:
			var result: Dictionary = service.build("entity",pose,world,revision(p))
			check(not result.ok and result.primitives.is_empty(), "unsupported world fails closed")
	if not failures: print("PASS: collision snapshot pose safety")
	quit(1 if failures else 0)
