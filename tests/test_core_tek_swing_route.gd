extends "res://tests/test_core_collision_pose_policy.gd"
func run():
	var host = preload("res://scripts/core/collision/collision_host.gd").new()
	check(host.configure(load("res://data/collision/generated/teknium.tres"),"swing-test").is_empty(),"host accepts trusted derived source")
	var c := context(); c.entity_id = 1; c.source_melee = true; c.strike_id = "swing"; c.strike_move = "SIDE STRIKE"; c.strike_elapsed = .16
	host.commit(c,0,Transform3D.IDENTITY,{})
	var r: Dictionary = host.telemetry().pose_request
	check(r.get("clip","") == "SwingPunchV1","generated side selects new swing")
	check(is_equal_approx(r.get("source_seconds",-1),.16),"swing uses raw .32 second authored clock")
	check(not r.get("derived_source",{}).is_empty(),"request exposes derived source provenance")
	var tick := 1
	for move in ["AIR STRIKE","UPPERCUT","UP AIR","LOW SWEEP","DOWN STRIKE"]:
		c.strike_move = move; c.strike_id = move; host.commit(c,tick,Transform3D.IDENTITY,{}); tick += 1
		r = host.telemetry().pose_request
		check(r.clip == ("Kick" if move in ["LOW SWEEP","DOWN STRIKE"] else "Punch"),"neighbor retains original source "+move)
		check(not r.has("derived_source"),"neighbor is not relabelled derived")
	c.strike_move = "SIDE STRIKE"; c.strike_id = "compat"; c.source_melee = false
	host.commit(c,tick,Transform3D.IDENTITY,{})
	check(host.telemetry().pose_request.clip == "Punch","compatibility preserves original Punch")
	var derived = preload("res://scripts/core/presentation/teknium_swing_source.gd")
	var model = load(derived.ASSET).instantiate(); var skeleton: Skeleton3D = model.get_node(derived.SKELETON)
	check(derived.validated_library(skeleton) != null,"actual installed hierarchy/rest accepted")
	skeleton.set_bone_rest(0,Transform3D.IDENTITY)
	check(derived.validated_library(skeleton) == null,"changed skeleton rest rejected")
	model.free()
	var manifest := metadata("teknium"); manifest.sources[0].clips.SwingPunchV1 = .32
	check(not load(POLICY).new().configure(manifest).is_empty(),"unproven derived clip rejected")
	if not failures: print("PASS: Tek swing route provenance and unchanged neighbors")
	quit(1 if failures else 0)
