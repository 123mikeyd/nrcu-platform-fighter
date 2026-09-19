extends "res://tests/test_core_body_profile.gd"
const Hurtbox = preload("res://scripts/core/collision/generated_hurtbox.gd")
func run():
	await rejected_reset("reset_with_body_profiles")
	await rejected_reset("reset_with_collision_profiles")
	merge_boundaries()
	editor_boundaries()
	if not failures: print("PASS collision profile malformed (%d checks)" % checks)
	quit(1 if failures else 0)
func rejected_reset(method: String):
	var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	var m = Match.new(); m.register_actor(1,a); m.register_actor(2,b)
	m.reset({1:Vector3(0,10,0),2:Vector3(1,10,0)})
	var f = Frame.new(); f.pressed.special = true
	await step(m,{1:f})
	for i in 11: await step(m)
	check(m.fighters[2].caught_by == 1 and m.fighters[1].grab != null, method + " real native grab established")
	m.fighters[2].percent = 37.0
	var before := snapshot(m,a,b)
	var good = body_profile(0.6,2.8)
	# Imported profiles exercise collision-host preflight, not unsupported-character rejection.
	if method == "reset_with_collision_profiles": good = load("res://data/collision/generated/teknium.tres").duplicate(true)
	var bad_profiles: Array = [Resource.new(),Hurtbox.new(),42,"invalid",{}]
	for nested in [null,Resource.new(),CollisionProfile.new()]:
		var bad = good.duplicate(true); bad.hurtboxes.append(nested); bad_profiles.append(bad)
	for bad in bad_profiles:
		check(not m.call(method,{1:Vector3(-4,0,0),2:Vector3(4,0,0)},{1:good,2:bad}), method + " rejects malformed second profile")
		check(snapshot(m,a,b) == before, method + " preserves relation percent generation revisions positions and native exceptions")
	a.free(); b.free()
func snapshot(m,a,b) -> Dictionary:
	return {"generation":m.generation,"tick":m.tick,"grab":m.fighters[1].grab,"caught":m.fighters[2].caught_by,"percent":m.fighters[2].percent,"a_body":a.body_profile_snapshot(),"b_body":b.body_profile_snapshot(),"a_position":a.position,"b_position":b.position,"a_exceptions":a.get_collision_exceptions(),"b_exceptions":b.get_collision_exceptions()}

func hurtbox():
	var h = Hurtbox.new(); h.hurtbox_id = "torso"; h.bone_name = "Spine"
	h.radius = 0.2; h.height = 0.8
	return h
func merge_boundaries():
	var base = body_profile(0.6,2.8); base.hurtboxes.append(hurtbox())
	check(base.validate().is_empty(), "typed valid profile accepted")
	check(base.merged_with(null).get("errors",["missing"]).is_empty(), "null override is supported no-op")
	for wrong in [Resource.new(),Hurtbox.new()]:
		check(not base.merged_with(wrong).get("errors",[]).is_empty(), "wrong override resource returns explicit errors")
	for nested in [null,Resource.new(),CollisionProfile.new()]:
		var bad = base.duplicate(true); bad.hurtboxes.append(nested)
		check(not bad.validate().is_empty(), "malformed nested entry returns validation errors")
		check(not bad.merged_with(null).get("errors",[]).is_empty(), "malformed base no-op merge rejects")
		var override = base.duplicate(true); override.manual_override = true
		check(not bad.merged_with(override).get("errors",[]).is_empty(), "malformed base merge rejects before ID access")
		override.hurtboxes.append(nested)
		check(not base.merged_with(override).get("errors",[]).is_empty(), "malformed nested override rejects before flag access")
	var partial = CollisionProfile.new(); partial.character_id = base.character_id; partial.manual_override = true
	partial.override_fields = PackedStringArray(["body_radius"]); partial.body_radius = 0.5
	check(base.merged_with(partial).get("errors",["missing"]).is_empty(), "valid partial body override accepted")
	for kind in ["duplicate","missing","unknown","rebind","invalid_ignored"]:
		var override = base.duplicate(true); override.manual_override = true
		override.hurtboxes[0].manual_override = true
		match kind:
			"duplicate": override.hurtboxes.append(override.hurtboxes[0].duplicate(true))
			"missing": override.hurtboxes[0].hurtbox_id = ""
			"unknown": override.hurtboxes[0].hurtbox_id = "unknown"
			"rebind": override.hurtboxes[0].bone_name = "Other"
			"invalid_ignored":
				override.hurtboxes[0].manual_override = false
				override.hurtboxes[0].radius = NAN
		check(not base.merged_with(override).get("errors",[]).is_empty(), kind + " override rejects explicitly")
	check(base.validate().is_empty() and base.body_radius == 0.6 and base.hurtboxes.size() == 1, "merge never mutates source")

func editor_boundaries():
	var path := "user://collision_profile_malformed_fixture.tres"
	var override_path := "user://collision_profile_malformed_override.tres"
	var base = body_profile(0.6,2.8); base.hurtboxes.append(hurtbox())
	check(ResourceSaver.save(base,path) == OK, "editor fixture saved")
	var lab = load("res://scenes/collision_authoring_lab.tscn").instantiate(); root.add_child(lab)
	check(lab.open_profile(path), "editor accepts typed valid profile")
	var working = lab.working
	for nested in [null,Resource.new(),CollisionProfile.new()]:
		var bad = base.duplicate(true); bad.manual_override = true; bad.hurtboxes.append(nested)
		check(ResourceSaver.save(bad,override_path) == OK, "malformed editor override saved")
		check(not lab.reload_override(override_path), "editor rejects malformed nested override")
		check(lab.working == working and not lab.status.text.is_empty(), "editor retains working profile and reports error")
	lab.free()
	DirAccess.remove_absolute(path); DirAccess.remove_absolute(override_path)
