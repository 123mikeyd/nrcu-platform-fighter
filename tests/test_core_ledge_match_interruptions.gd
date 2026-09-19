extends "res://tests/test_core_ledge_match.gd"
func run() -> void:
	var terrain = body(Vector3(2,-0.5,0),Vector3(4,1,4))
	var p = LedgePolicy.new(); p.protection_ticks = 2
	var m = setup_ledge(p)
	await tick(m,{1:frame(false,1)})
	m.fighters[2].actor.position = Vector3(-2,-1.5,0)
	await tick(m,{2:frame(true,1)})
	check(m.fighters[1].percent == 0, "ledge protection filters actual attack")
	m.fighters[2].ready_tick = 0
	await tick(m,{2:frame(true,1)})
	check(m.fighters[1].percent == 8 and m.ledge_telemetry(1).anchor_id == "", "expired protection takes actual hit and synchronously releases ledge")
	var launch = m.fighters[1].actor.velocity
	check(launch.length() > 1 and m.fighters[1].actor.runtime.hitstun_left > 0, "release cannot overwrite incoming launch")
	cleanup(m)
	for reason in ["freeze","disable","removed","reset"]:
		m = setup_ledge(); await tick(m,{1:frame(false,1)})
		if reason == "freeze": m.set_frozen(1,true)
		elif reason == "disable": m.set_enabled(1,false)
		elif reason == "removed": root.remove_child(m.fighters[1].actor)
		else: m.reset({1:Vector3(-1,-1,0),2:Vector3(8,3,0)})
		check(m.ledge_telemetry(1).anchor_id == "", "synchronous cleanup: " + reason)
		cleanup(m)
	# Protection also excludes grab, without turning ledge into permanent immunity.
	for protected in [true,false]:
		p = LedgePolicy.new(); p.protection_ticks = 50 if protected else 0
		m = setup_ledge(p); await tick(m,{1:frame(false,1)})
		# Caster and victim share height; caster is outside and faces inward.
		m.fighters[2].actor.position = Vector3(-1.65,-1.5,0)
		var special = Frame.new(); special.pressed.special = true
		await tick(m,{2:special})
		for i in 11:
			m.fighters[2].actor.position = Vector3(-1.65,-1.5,0)
			m.fighters[2].actor.runtime.velocity = Vector3.ZERO
			await tick(m)
		check(m.fighters[1].caught_by == (0 if protected else 2), "grab respects finite ledge protection")
		if not protected: check(m.ledge_telemetry(1).anchor_id == "", "capture releases occupied ledge immediately")
		cleanup(m)
	terrain.free()
	if not failures: print("PASS: core ledge match interruption (%d checks)" % checks)
	quit(1 if failures else 0)
