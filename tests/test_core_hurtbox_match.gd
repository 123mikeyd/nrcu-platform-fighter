extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b)
	check(m.has_method("reset_with_collision_profiles"),"generated collision full reset API")
	if not m.has_method("reset_with_collision_profiles"):
		a.free(); b.free(); quit(1); return
	var profiles := {1:load("res://data/collision/generated/turbofit.tres"),2:load("res://data/collision/generated/teknium.tres")}
	check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(4,20,0)},profiles),"validated full generated sources installed: "+str(m.collision_install_diagnostics()))
	await step(m)
	for id in [1,2]:
		var t: Dictionary = m.collision_telemetry(id)
		check(t.get("ok",false),"full generated snapshot valid: "+str(t.get("diagnostics",[])))
		check(t.get("primitives",[]).size() == profiles[id].hurtboxes.size(),"all generated limbs sampled")
		check(t.get("pose_request",{}).get("clip","") != "","canonical pose request published")
	var before: Dictionary = m.collision_telemetry(2)
	m.simulate()
	check(before == m.collision_telemetry(2),"same physics tick cannot advance pose")
	m.set_enabled(2,false)
	check(not m.collision_telemetry(2).get("ok",true),"disable invalidates snapshot immediately")
	var missing: Resource = profiles[2].duplicate(true)
	missing.source_asset = "res://assets/missing_hurtbox_source.glb"
	check(not m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(4,20,0)},{2:missing}),"missing source asset rejects without engine error")
	missing.source_asset = "res://data/collision/generated/teknium.tres"
	missing.source_sha256 = FileAccess.get_sha256(missing.source_asset)
	check(not m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(4,20,0)},{2:missing}),"non-scene pose resource fails with diagnostic not engine cast error")
	check(not m.collision_install_diagnostics().is_empty(),"invalid source diagnostic exposed")
	check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(4,20,0)},{1:profiles[1],2:null}),"explicit generated opt-out full reset")
	await step(m)
	check(m.collision_telemetry(2).geometry_mode == "legacy_body_capsule","null profile explicitly selects legacy")
	check(m.collision_telemetry(1).geometry_mode == "generated_hurtboxes" and m.collision_telemetry(1).ok,"omitted actor retains generated identity")
	a.free(); b.free()
	if not failures: print("PASS: generated hurtbox match (%d checks)" % checks)
	quit(1 if failures else 0)
