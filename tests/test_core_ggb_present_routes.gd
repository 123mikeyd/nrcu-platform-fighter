extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
func run() -> void:
	var v = load("res://scripts/core/presentation/ggb_presenter.gd").new()
	root.add_child(v)
	if v.get("output") == null:
		check(false,"missing committed GGB route telemetry")
		v.free()
		quit(1)
		return
	var host = load("res://scripts/core/kits/ggb_host.gd").new()
	var source = load("res://scripts/ggb_visual.gd").new()
	root.add_child(source)
	for facing in [-1.0,1.0]:
		for airborne in [false,true]:
			for aim in [Vector2.ZERO,Vector2.UP,Vector2.DOWN]:
				host.cancel(true)
				check(host.start_basic("basic",aim,airborne,facing),"real basic accepted")
				var value: Dictionary = host.snapshot()
				value.grounded = not airborne
				var before := var_to_bytes(value)
				v.present(value,0)
				check(v.output.state == value.presentation.move,"all six source basics mapped")
				check(v.output.clip == "" and "no" in v.output.fallback,"honest missing clip fallback")
				check(var_to_bytes(value) == before,"detached snapshot immutable")
		for aim in [Vector2.DOWN,Vector2.UP,Vector2.RIGHT,Vector2.ZERO]:
			host.cancel(true)
			check(host.start_special("special",aim,facing,true),"real special accepted")
			var value: Dictionary = host.snapshot()
			value.grounded = false
			v.present(value,0)
			check(v.output.state == {Vector2.DOWN:"LeadFeet",Vector2.UP:"rising_strike",Vector2.RIGHT:"sticky_goo",Vector2.ZERO:"charge"}[aim],"special source route")
			check(v.is_lead == (aim == Vector2.DOWN),"LeadFeet means Heavy Drop only")
			if aim == Vector2.DOWN:
				source.sync_pose(false,Vector3.ZERO,true,facing,0,false)
				for i in 2: check(v.wings[i].transform.is_equal_approx(source.wings[i].transform),"lead hinge parity")
				check(v.lead_material.albedo_color == source.lead_material.albedo_color and is_equal_approx(v.lead_material.metallic, source.lead_material.metallic) and is_equal_approx(v.lead_material.roughness, source.lead_material.roughness),"source lead material")
				host.landed(true)
				value = host.snapshot()
				v.present(value,0)
				check(v.output.state == "landing" and not v.is_lead,"synchronous terrain slam restores gummy")
			if aim == Vector2.ZERO:
				for i in 120: host.prepare(true)
				v.present(host.snapshot(),120)
				check(v.output.state == "charge","indefinite charge remains source static")
				host.prepare(false)
				v.present(host.snapshot(),121)
				check(v.output.state == "charge_release" and v.output.identity.ends_with(":charge_release"),"same activation release is distinct episode")
		host.cancel(true)
		v.present(host.snapshot(),121)
		check(v.output.state == "idle" and not v.is_lead,"cancel reconciles on unchanged tick")
	v.present({"grounded":false,"locomotion":"float"},122)
	check(v.output.state == "float" and v.output.clip == "","float uses source airborne wing procedure, not invented clip")
	v.free()
	source.free()
	await process_frame
	if failures == 0: print("PASS: GGB actual host routes, LeadFeet landing charge release and honest fallbacks")
	quit(1 if failures else 0)
