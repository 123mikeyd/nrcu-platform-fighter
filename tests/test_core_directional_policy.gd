extends "res://tests/test_core_directional_up.gd"
func run() -> void:
	var m = Match.new(); var a = Actor.new(); root.add_child(a); m.register_actor(1, a)
	# Delayed diagonals restore the press-time x, as existing SIDE/FORCE/recovery do.
	for y in [-1.0, 1.0]:
		m.reset({1: Vector3(0, 50, 0)})
		m.fighters[1].ready_tick = 2
		await tick(m, {1: aim(Vector2(-1, y))})
		check(m.fighters[1].activation_id.is_empty() and not m.fighters[1].buffer.peek("attack").is_empty(), "cooldown retains vertical request")
		var later = Frame.new(); later.axis = Vector2(1, -y)
		await tick(m, {1: later})
		a.runtime.grounded = true
		await tick(m, {1: later})
		check(m.fighters[1].move_id == ("UPPERCUT" if y < 0 else "LOW SWEEP"), "buffered y retained; ground context chosen at acceptance, not press")
		check(m.fighters[1].facing == -1 and m.fighters[1].ready_tick == 22, "delayed diagonal restores pressed facing and acceptance-relative cooldown")
		check(m.fighters[1].buffer.peek("attack").is_empty(), "accepted deferred request consumed once")
	# Pure vertical has no horizontal commitment; retain core acceptance-facing convention.
	m.reset({1: Vector3(0, 50, 0)}); m.fighters[1].ready_tick = 1
	await tick(m, {1: aim(Vector2.DOWN)})
	var left = Frame.new(); left.axis = Vector2.LEFT
	a.runtime.grounded = true
	await tick(m, {1: left})
	check(m.fighters[1].move_id == "LOW SWEEP" and m.fighters[1].facing == -1, "zero x vertical keeps acceptance-facing, no invented press-facing field")
	for y in [-1.0, 1.0]:
		m.reset({1: Vector3(0, 50, 0)})
		var both = aim(Vector2(0, y)); both.pressed.special = true
		await tick(m, {1: both})
		check(m.fighters[1].move_id == ("UP AIR" if y < 0 else "DOWN STRIKE") and not a.runtime.recovery_spent and m.fighters[1].force == null, "accepted vertical basic wins simultaneous special")
		check(not m.fighters[1].buffer.peek("special").is_empty(), "basic priority leaves unaccepted special buffered")
		var held = Frame.new(); held.axis.y = y; held.held.attack = true
		var activation: String = m.fighters[1].activation_id
		for i in 19: await tick(m, {1: held})
		check(m.fighters[1].activation_id == activation and m.fighters[1].ready_tick == 20, "hold cannot restart within cooldown")
		await tick(m, {1: held})
		check(m.fighters[1].activation_id.is_empty() and m.fighters[1].buffer.peek("special").is_empty() and not a.runtime.recovery_spent, "t20 hold does not repeat; special expired")
		await tick(m, {1: aim(Vector2(0, y))})
		check(not m.fighters[1].activation_id.is_empty(), "fresh edge works after cooldown")
	for axis in [Vector2.ZERO, Vector2.DOWN]:
		m.reset({1: Vector3(0, 50, 0)})
		var special = Frame.new(); special.axis = axis; special.pressed.special = true
		await tick(m, {1: special})
		if axis == Vector2.ZERO:
			check(m.fighters[1].grab != null and m.fighters[1].buffer.peek("special").is_empty(), "neutral special accepts grab once")
		else:
			check(m.fighters[1].activation_id.is_empty(), "down special remains unsupported")
	# Core basic boundaries use representable Vector2 endpoints, not promoted decimal doubles.
	for y in [-0.1001, -0.1, 0.1, 0.1001]:
		m.reset({1: Vector3(0, 50, 0)})
		await tick(m, {1: aim(Vector2(1, y))})
		var expected := "UP AIR" if y < -0.1 else "DOWN STRIKE" if y > 0.1 else "AIR STRIKE"
		check(m.fighters[1].move_id == expected, "strict aim endpoint %s" % y)
	# Stun and shield gates do not consume vertical edges.
	for shield in [false, true]:
		m.reset({1: Vector3(0, 50, 0)})
		if not shield: a.apply_combat_launch(Vector3.ZERO, 2)
		var f = aim(Vector2.UP); f.held.shield = shield
		await tick(m, {1: f})
		check(m.fighters[1].activation_id.is_empty() and not m.fighters[1].buffer.peek("attack").is_empty(), "locked vertical input buffers")
		await tick(m); await tick(m)
		check(m.fighters[1].move_id == "UP AIR", "first legal tick accepts deferred vertical")
	check(a.get_child_count() == 1 and a.get_child(0) is CollisionShape3D, "all policy tests execute without render/presenter nodes")
	a.free()
	if not failures: print("PASS: directional policy (%d checks)" % checks)
	quit(1 if failures else 0)
