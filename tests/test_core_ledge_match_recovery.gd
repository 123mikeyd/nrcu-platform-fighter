extends "res://tests/test_core_ledge_match.gd"
func run() -> void:
	var terrain = body(Vector3(2,-0.5,0),Vector3(4,1,4))
	var p = LedgePolicy.new(); p.regrab_ticks = 2
	var m = setup_ledge(p)
	m.fighters[1].actor.position = Vector3(-4,3,0)
	var special = Frame.new(); special.pressed.special = true; special.axis.y = -1
	await tick(m,{1:special})
	check(m.fighters[1].recovery != null and m.fighters[1].actor.runtime.recovery_spent, "actual recovery accepted before catch")
	var ready = m.fighters[1].ready_tick
	m.fighters[1].actor.position = Vector3(-1,-1,0)
	m.fighters[1].actor.runtime.velocity = Vector3(1,-1,0); m.fighters[1].actor.velocity = Vector3(1,-1,0)
	# Outside the body capsule, still inside the recovery hit box if catch fails to cancel it.
	m.fighters[2].actor.position = Vector3(-1.9,-1,0)
	await tick(m,{1:frame(false,1)})
	check(m.ledge_telemetry(1).anchor_id == "left", "falling recovery catches")
	check(m.fighters[1].recovery == null and not m.fighters[1].actor.runtime.recovery_motion, "catch cancels source before recovery contact gathering")
	check(m.fighters[2].percent == 0, "caught recovery has no same-frame outgoing hit")
	check(not m.fighters[1].actor.runtime.recovery_spent and m.fighters[1].actor.runtime.air_jumps_left == 0 and m.fighters[1].ready_tick == ready, "benefit restores recovery permission only, never cooldown or air jumps")
	var drop = Frame.new(); drop.pressed.down = true
	await tick(m,{1:drop}); await tick(m)
	m.fighters[1].actor.position = Vector3(-1,-1,0); m.fighters[1].actor.runtime.velocity = Vector3(1,-1,0)
	m.fighters[1].actor.runtime.recovery_spent = true
	await tick(m,{1:frame(false,1)})
	check(m.ledge_telemetry(1).anchor_id == "left" and not m.ledge_telemetry(1).protected and m.fighters[1].actor.runtime.recovery_spent, "regrab in same excursion grants no recovery or protection")
	await tick(m,{1:drop})
	m.fighters[1].actor.position = Vector3(2,0.02,0); m.fighters[1].actor.runtime.velocity = Vector3(0,-1,0)
	for i in 10: await tick(m)
	check(m.fighters[1].actor.runtime.grounded, "trusted real landing occurs")
	m.fighters[1].actor.position = Vector3(-1,-1,0); m.fighters[1].actor.runtime.reconcile_contact(false,Vector3(1,-1,0)); m.fighters[1].actor.runtime.recovery_spent = true
	await tick(m,{1:frame(false,1)})
	check(m.ledge_telemetry(1).protected and not m.fighters[1].actor.runtime.recovery_spent, "terrain transition rearms catch benefit")
	cleanup(m); terrain.free()
	if not failures: print("PASS: core ledge match recovery (%d checks)" % checks)
	quit(1 if failures else 0)
