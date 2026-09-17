extends "res://tests/test_core_collision_snapshot.gd"
func run() -> void:
	var p = fixture(); var second = p.hurtboxes[0].duplicate(true)
	second.hurtbox_id = "aaa"; p.hurtboxes.append(second)
	var service = load(BUILDER).new(); var other = load(BUILDER).new()
	service.configure(p,p.source_asset,p.source_sha256,"draft"); other.configure(p,p.source_asset,p.source_sha256,"draft")
	var pose := {"Hand":Transform3D.IDENTITY}; var rev := revision(p)
	var active := {"enabled":true,"eliminated":false,"team_id":"red","enabled_hurtbox_ids":PackedStringArray(["arm","aaa"])}
	var before: Dictionary = service.build("a",pose,Transform3D.IDENTITY,rev,active)
	check(before.primitives[0].id == "aaa", "stable lexical IDs independent of resource order")
	for state in [{"enabled":false},{"eliminated":true},{"enabled_hurtbox_ids":PackedStringArray()}]:
		var empty: Dictionary = service.build("a",pose,Transform3D.IDENTITY,rev,state)
		check(empty.ok and empty.primitives.is_empty() and not empty.has_bounds and not empty.participation.active, "explicit nonparticipation, never bad profile/body fallback")
	var filtered: Dictionary = service.build("a",pose,Transform3D.IDENTITY,rev,{"enabled_hurtbox_ids":PackedStringArray(["arm"])})
	check(filtered.primitives.size() == 1 and filtered.primitives[0].id == "arm", "enabled IDs captured once")
	active.enabled = false; active.enabled_hurtbox_ids.clear()
	check(before.participation.enabled and before.participation.enabled_hurtbox_ids.size() == 2, "participation deep copied")
	p.hurtboxes[0].radius = 88; pose.Hand.origin = Vector3(9,0,0); rev.seconds = 3
	var unchanged: Dictionary = service.build("a",{"Hand":Transform3D.IDENTITY},Transform3D.IDENTITY,revision(p))
	check(unchanged.primitives == before.primitives, "configure captured private source definitions")
	before.primitives[0].radius = 100; before.profile_revision.revision = "corrupt"; before.pose_revision.seconds = 77
	var other_result: Dictionary = other.build("b",{"Hand":Transform3D.IDENTITY},Transform3D.IDENTITY,revision(p))
	check(other_result.primitives == unchanged.primitives and other_result.profile_revision.revision == "draft", "two instances independent; no shared outputs")
	check(service.has_method("cache_size") and service.has_method("reset"), "bounded resettable cache API")
	if service.has_method("cache_size"):
		for time in range(40):
			var snapshot: Dictionary = service.build("a",{"Hand":Transform3D.IDENTITY},Transform3D.IDENTITY,revision(p,time))
			check(snapshot.pose_revision.seconds == time and snapshot.primitives == unchanged.primitives and service.cache_size() <= 1, "explicit caller time and bounded cache")
		var frozen: Dictionary = service.build("a",{"Hand":Transform3D.IDENTITY},Transform3D.IDENTITY,revision(p,39))
		frozen.primitives.clear()
		check(service.build("a",{"Hand":Transform3D.IDENTITY},Transform3D.IDENTITY,revision(p,39)).primitives == unchanged.primitives, "unchanged paused/hitstop time returns copied result")
		var moved: Dictionary = service.build("a",pose,Transform3D.IDENTITY,revision(p,39))
		check(moved.primitives != unchanged.primitives, "same time placement/pose changes invalidate cache")
		service.reset(); check(service.cache_size() == 0, "reset cache only")
		check(service.build("a",{"Hand":Transform3D.IDENTITY},Transform3D.IDENTITY,revision(p)).ok, "reset retains configured source")
	if not failures: print("PASS: collision snapshot lifecycle and filters")
	quit(1 if failures else 0)
