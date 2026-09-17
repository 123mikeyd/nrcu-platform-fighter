extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); root.add_child(a); m.register_actor(1, a)
	m.reset({1: Vector3(0, 50, 0)})
	m.fighters[1].ready_tick = 2
	await step(m, {1: press(Vector2(-1, -1))})
	check(not m.fighters[1].buffer.peek("special").is_empty(), "cooldown request not consumed")
	var right = Frame.new(); right.axis = Vector2.RIGHT
	await step(m, {1: right}); await step(m, {1: right})
	check(m.fighters[1].recovery != null and m.fighters[1].recovery.facing == -1, "acceptance uses press-time up aim and facing despite later right input")
	check(m.fighters[1].ready_tick == 41, "cooldown relative to acceptance tick")
	# t+38 blocked, buffered basic accepted at t+39 even though still spent.
	for i in 37: await step(m)
	await step(m, {1: press(Vector2.RIGHT, "attack")})
	check(m.fighters[1].move_id == "RISING STRIKE" and not m.fighters[1].buffer.peek("attack").is_empty(), "t+38 still blocks basic without consuming")
	await step(m)
	check(m.fighters[1].move_id == "AIR STRIKE" and m.fighters[1].buffer.peek("attack").is_empty(), "t+39 accepts buffered basic, no blanket attack lock")
	m.reset({1: Vector3(0, 50, 0)})
	await step(m, {1: press(Vector2.RIGHT)})
	await step(m, {1: press()})
	check(m.fighters[1].force != null and not a.runtime.recovery_spent and not m.fighters[1].buffer.peek("special").is_empty(), "force excludes recovery without consuming illegal edge")
	for i in 6: await step(m)
	check(m.fighters[1].buffer.peek("special").is_empty(), "force-blocked recovery expires")
	m.reset({1: Vector3(0, 50, 0)})
	var shield = press(); shield.held.shield = true
	await step(m, {1: shield})
	check(not a.runtime.recovery_spent and not m.fighters[1].buffer.peek("special").is_empty(), "shield rejects recovery without consumption")
	m.reset({1: Vector3(0, 50, 0)})
	var both = press(Vector2.RIGHT, "attack"); both.pressed.special = true
	await step(m, {1: both})
	check(m.fighters[1].move_id == "AIR STRIKE" and not a.runtime.recovery_spent, "existing attack priority")
	m.reset({1: Vector3(0, 50, 0)})
	await step(m, {1: press(Vector2(0, -0.1))})
	check(not a.runtime.recovery_spent and not m.fighters[1].buffer.peek("special").is_empty(), "strict representable up threshold excluded")
	# Eligibility: self, team, disabled excluded; unassigned inside origin-box included.
	var others := []
	for id in [2, 3, 4]:
		var b = Actor.new(); root.add_child(b); others.append(b); m.register_actor(id, b, 1 if id == 2 else -1)
	m.fighters[1].team = 1
	m.reset({1: Vector3(0, 30, 0), 2: Vector3(0.5, 31, 0), 3: Vector3(-0.5, 31, 0), 4: Vector3(0.2, 31, 0)})
	m.set_enabled(4, false)
	await step(m, {1: press()})
	check(m.fighters[1].percent == 0 and m.fighters[2].percent == 0 and m.fighters[4].percent == 0, "recovery self/team/disabled excluded")
	check(m.fighters[3].percent == 12 and m.events.size() == 1, "only eligible victim contact")
	# Two recoveries trade without insertion-order dependent cancellation.
	m.fighters[1].team = -1; m.fighters[2].team = -1
	m.reset({1: Vector3(0, 30, 0), 2: Vector3(0.5, 30, 0), 3: Vector3(20, 30, 0), 4: Vector3(25, 30, 0)})
	await step(m, {1: press(), 2: press(Vector2(-1, -1))})
	check(m.fighters[1].percent == 12 and m.fighters[2].percent == 12, "simultaneous recovery trade resolves snapshot")
	check(m.fighters[1].recovery == null and m.fighters[2].recovery == null, "trade cancels both only after snapshot")
	a.free()
	for b in others: b.free()
	if not failures: print("PASS: recovery arbitration (%d checks)" % checks)
	quit(1 if failures else 0)
