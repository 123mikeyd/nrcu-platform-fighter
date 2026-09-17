extends "res://tests/test_core_body_profile.gd"
func run():
	var a = Actor.new(); root.add_child(a)
	var shape = a.get_node("CoreCapsule").shape
	var bad = body_profile(0.3,1.5); bad.body_center.y += 0.2
	check(not a.configure_body_profile(bad), "reject shifted foot plane without mutation")
	check(a.get_node("CoreCapsule").shape == shape, "invalid configuration retains native resource")
	for field in ["body_radius", "body_height", "body_center", "foot_origin", "generator_version", "source_sha256"]:
		bad = body_profile(0.3,1.5)
		match field:
			"body_radius": bad.body_radius = NAN
			"body_height": bad.body_height = 0.1
			"body_center": bad.body_center.y = 2.0
			"foot_origin": bad.foot_origin.y = NAN
			"generator_version": bad.generator_version = 999
			"source_sha256": bad.source_asset = "res://assets/teknium/teknium_animations.glb"; bad.source_sha256 = "bad"
		check(not a.configure_body_profile(bad), "invalid profile rejected: " + field)
	var fresh = Actor.new(); root.add_child(fresh)
	fresh.position.y = 100
	await physics_frame; fresh.simulate({})
	check(not fresh.configure_body_profile(body_profile(0.3,1.5)), "first native physics permanently closes standalone resize window")
	fresh.reset_at(Vector3(0,100,0))
	check(not fresh.configure_body_profile(null), "actor-only reset cannot bypass match-owned full reset")
	fresh.free()
	bad = body_profile(0.3,1.5)
	bad.source_asset = "res://assets/teknium/teknium_animations.glb"; bad.source_sha256 = "0".repeat(64)
	check(not a.configure_body_profile(bad), "well-formed but stale source hash rejected")
	a.scale = Vector3(2,2,2)
	check(not a.configure_body_profile(null), "scaled native actor cannot install a body")
	a.scale = Vector3.ONE
	var m = Match.new(); m.register_actor(1,a)
	check(not a.configure_body_profile(body_profile(0.3,1.5)), "registered actor cannot bypass match lifecycle")
	check(m.has_method("reset_with_body_profiles"), "explicit atomic full reset API")
	if not m.has_method("reset_with_body_profiles"):
		a.free(); quit(1); return
	var b = Actor.new(); root.add_child(b); m.register_actor(2,b)
	var profiles = {1:body_profile(0.3,1.5),2:body_profile(0.6,2.8)}
	check(m.reset_with_body_profiles({1:Vector3(0,10,0),2:Vector3(1,10,0)},profiles), "valid full reset applies unequal geometry")
	check(m.fighters[1].kit_id == "teknium" and a.body_profile_snapshot().character_id == "synthetic-body", "collision identity independent of kit")
	var f = Frame.new(); f.pressed.special = true
	await step(m,{1:f})
	for i in 11: await step(m)
	check(m.fighters[2].caught_by == 1, "native unequal-body capture prerequisite")
	var before = [m.generation,m.tick,a.position,b.position,a.get_node("CoreCapsule").shape,b.get_node("CoreCapsule").shape]
	profiles[2].body_center.y = 999
	check(not m.reset_with_body_profiles({1:Vector3(9,9,0)},profiles), "invalid batch rejects before any lifecycle cleanup")
	check(before == [m.generation,m.tick,a.position,b.position,a.get_node("CoreCapsule").shape,b.get_node("CoreCapsule").shape] and m.fighters[2].caught_by == 1, "no partial warp shape tick or hold mutation")
	check(not a.configure_body_profile(null) and not b.configure_body_profile(null), "held actors reject in-place resizing")
	check(m.reset_with_body_profiles({1:Vector3(-3,0,0),2:Vector3(3,0,0)},{1:body_profile(0.6,2.8),2:null}), "caller full reset releases hold and safely replaces geometry")
	check(m.fighters[2].caught_by == 0 and a.get_collision_exceptions().is_empty() and b.get_collision_exceptions().is_empty(), "full lifecycle pair cleanup")
	var snapshot = a.body_profile_snapshot(); snapshot.character_id = "mutated"
	check(a.body_profile_snapshot().character_id == "synthetic-body", "metadata snapshot cannot mutate live identity")
	m.reset({1:Vector3.ZERO,2:Vector3(3,0,0)})
	check(is_equal_approx(a.get_node("CoreCapsule").shape.height,2.8) and is_equal_approx(b.get_node("CoreCapsule").shape.height,1.8), "ordinary reset retains independent selected geometry")
	a.free(); b.free()
	if not failures: print("PASS body profile lifecycle (%d checks)" % checks)
	quit(1 if failures else 0)
