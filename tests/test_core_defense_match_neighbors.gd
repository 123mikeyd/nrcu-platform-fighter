extends "res://tests/test_core_defense_match.gd"
func run() -> void:
	var floor = floor_body(); var p = DefenseProfile.new(); p.shield_drain = 0
	var m = setup_match(p); await settle(m)
	m.fighters[2].actor.position.x = 1.0
	m.configure_hitstop(load("res://scripts/core/combat/hitstop_profile.gd").new())
	var special = Frame.new(); special.pressed.special = true; special.axis.y = -1
	await tick(m, {1:special, 2:shield(true)})
	check(m.fighters[2].percent == 0 and m.defense_telemetry(2).shield_health < 100, "actual recovery contact routes through shield")
	var health = m.defense_telemetry(2).shield_health
	check(m.fighters[1].hitstop_left == 0, "blocked contacts do not request damage hitstop")
	await tick(m, {1:shield(true, Vector2.RIGHT),2:shield()})
	check(m.defense_telemetry(1).state == "idle" and not m.fighters[1].buffer.peek("shield").is_empty(), "active recovery rejects unconsumed defense edge")
	check(m.defense_telemetry(2).shield_health == health, "recovery victim ledger charges once")
	m.reset({1:Vector3(0,6,0),2:Vector3(1,6,0)})
	await tick(m, {1:frame(true,1),2:frame(true,-1)})
	check(m.fighters[1].percent == 8 and m.fighters[2].percent == 8, "finite mode preserves actual same-frame trades")
	for id in [1,2]: check(m.fighters[id].hitstop_left == 4, "trade sources stop after shared batch")
	m.reset({1:Vector3(0,6,0),2:Vector3(10,6,0)})
	special.axis = Vector2.RIGHT
	await tick(m,{1:special})
	var force = m.fighters[1].force; var age = force.age
	m.fighters[1].hitstop_left = 2
	var edge = shield(true, Vector2.RIGHT)
	await tick(m,{1:edge}); await tick(m)
	check(force.age == age and not m.fighters[1].buffer.peek("shield").is_empty(), "hitstop preserves force source clock and buffered edge")
	await tick(m)
	check(force.age == age+1 and m.defense_telemetry(1).state == "idle" and not m.fighters[1].buffer.peek("shield").is_empty(), "busy force resumes source but rejects defense without consumption")
	# A fresh edge during hitstop is accepted on resume with press-time direction.
	m.reset({1:Vector3(0,6,0),2:Vector3(10,6,0)})
	m.fighters[2].hitstop_left = 2
	await tick(m,{2:shield(true,Vector2.UP)}); await tick(m)
	await tick(m)
	check(m.defense_telemetry(2).state == "dodge_startup", "paused released edge survives to legal acceptance")
	for i in 4: await tick(m)
	check(m.fighters[2].actor.velocity.y > 0, "input up maps to positive stage y")
	cleanup(m); floor.free()
	if not failures: print("PASS: core defense match neighbors (%d checks)" % checks)
	quit(1 if failures else 0)
