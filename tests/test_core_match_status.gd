extends "res://tests/test_core_match_lifecycle.gd"

func run() -> void:
	await landing_during_hitstun()
	await enable_during_hitstun(false)
	await enable_during_hitstun(true)
	if failures == 0: print("PASS: core match status (%d checks)" % checks)
	quit(1 if failures else 0)

func landing_during_hitstun() -> void:
	var m = Match.new()
	var floor = floor_body()
	var a = Actor.new()
	root.add_child(a)
	m.register_actor(10, a)
	m.reset({10: Vector3(0, 0.25, 0)})
	a.apply_combat_launch(Vector3(0, -5, 0), 12)
	for i in range(8):
		await tick(m)
		if a.runtime.grounded: break
	check(a.is_on_floor() and a.runtime.grounded and a.runtime.hitstun_left > 1, "real floor contact occurs during hitstun")
	while a.runtime.hitstun_left > 1: await tick(m)
	var jump = frame()
	jump.pressed.jump = true
	jump.held.jump = true
	await tick(m, {10: jump})
	check(a.runtime.hitstun_left == 0 and a.runtime.states.status == "normal", "last hitstun tick completes before landing recovery")
	check(a.runtime.states.action == "landing_lock" and not a.can_accept_jump(), "hitstun expiry restores pending landing lock and rejects premature jump")
	for i in range(a.profile.landing_ticks):
		check(not a.can_accept_jump(), "landing recovery never advertises an unexecutable jump")
		await tick(m)
		check(not m.fighters[10].buffer.peek("jump").is_empty(), "near-expiry jump remains queued throughout landing recovery")
	check(a.can_accept_jump(), "jump becomes eligible after all landing recovery ticks")
	await tick(m)
	check(m.fighters[10].buffer.peek("jump").is_empty() and a.runtime.states.locomotion == "jump_startup", "first legal tick consumes buffered jump into actual startup")
	for i in range(a.profile.jump_startup_ticks): await tick(m)
	check(a.velocity.y > 0 and not a.runtime.grounded, "buffered jump launches real body from floor after hitstun landing")
	a.free()
	floor.free()

func enable_during_hitstun(disconnect: bool) -> void:
	var label := "reenable" if disconnect else "redundant enable"
	var m = Match.new()
	var a = Actor.new()
	root.add_child(a)
	m.register_actor(10, a)
	m.reset({10: Vector3(0, 5, 0)})
	a.apply_combat_launch(Vector3(5, 2, 0), 4)
	await tick(m, {10: frame(true)})
	check(not m.fighters[10].buffer.peek("attack").is_empty(), label + ": attack queues while stunned")
	var remaining: int = a.runtime.hitstun_left
	if disconnect:
		m.set_enabled(10, false)
		check(m.fighters[10].buffer.peek("attack").is_empty(), "disconnect clears preexisting input")
		var at: Vector3 = a.position
		var velocity: Vector3 = a.velocity
		for i in range(3): await tick(m, {10: frame(true)})
		check(a.position == at and a.velocity == velocity and a.runtime.hitstun_left == remaining, "disabled actor freezes motion and remaining hitstun")
		check(m.fighters[10].buffer.peek("attack").is_empty(), "disabled input never enters queue")
	var buffer = m.fighters[10].buffer
	m.set_enabled(10, true)
	check(a.runtime.hitstun_left == remaining and a.runtime.states.status == "hitstun" and not a.can_accept_jump(), label + ": enable preserves remaining stun and its acceptance gate")
	if not disconnect:
		check(m.fighters[10].buffer == buffer and not buffer.peek("attack").is_empty(), "redundant enable is a no-op including queued edge identity")
	# Supply a fresh real attack after reenabling; redundant enable uses its existing edge.
	for i in range(remaining):
		await tick(m, {10: frame(disconnect and i == 0)})
		check(m.fighters[10].activation_id.is_empty() and not m.fighters[10].buffer.peek("attack").is_empty(), label + ": actual attack stays queued on every locked tick")
	check(a.runtime.hitstun_left == 0 and a.runtime.states.status == "normal", label + ": resumed hitstun expires after exact remaining ticks")
	await tick(m)
	check(not m.fighters[10].activation_id.is_empty() and m.fighters[10].buffer.peek("attack").is_empty(), label + ": queued attack activates only on first legal tick")
	a.free()
