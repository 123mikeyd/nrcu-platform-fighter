extends "res://tests/test_core_force_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); root.add_child(a); m.register_actor(1, a)
	m.reset({1: Vector3(0, 20, 0)})
	# Rejected request preserves press-time axis through the real buffer.
	m.fighters[1].ready_tick = 2
	await step(m, {1: press(Vector2.LEFT)})
	check(not m.fighters[1].buffer.peek("special").is_empty(), "rejected special is not consumed")
	await step(m, {1: press(Vector2.RIGHT, "jump")})
	await step(m)
	check(m.fighters[1].force != null and m.fighters[1].facing == -1, "buffered special uses press-time facing")
	var x: float = a.position.x; var y: float = a.position.y; var jumps: int = a.runtime.air_jumps_left
	await step(m, {1: press(Vector2.RIGHT, "jump")})
	check(a.position.x == x and a.runtime.air_jumps_left == jumps, "magic locks movement and jump")
	check(a.position.y != y, "magic retains vertical physics")
	check(not m.fighters[1].buffer.peek("jump").is_empty(), "rejected jump not consumed")
	# External launch through existing actor seam must cancel before event too.
	a.apply_combat_launch(Vector3(5, 2, 0), 20)
	await step(m)
	check(m.fighters[1].force == null, "preexisting hitstun cancels force")
	check(a.velocity.x == 5, "magic lock never overwrites hitstun launch")
	for i in 20: await step(m)
	check(m.projectiles.is_empty(), "interrupted anticipation cannot emit later")
	m.reset({1: Vector3.ZERO})
	for axis in [Vector2.ZERO, Vector2.DOWN]:
		m.reset({}); await step(m, {1: press(axis)})
		if axis == Vector2.ZERO:
			check(m.fighters[1].force == null and m.fighters[1].recovery == null and m.fighters[1].grab != null, "neutral special selects grab rather than force or recovery")
			check(m.fighters[1].buffer.peek("special").is_empty(), "accepted grab consumes special once")
		else:
			check(m.fighters[1].force == null and m.fighters[1].recovery == null and m.fighters[1].grab == null and not m.fighters[1].buffer.peek("special").is_empty(), "unsupported down special unconsumed")
	for axis in [Vector2.UP, Vector2(1, -1)]:
		m.reset({}); await step(m, {1: press(axis)})
		check(m.fighters[1].force == null and m.fighters[1].recovery != null, "up special selects recovery rather than force")
		check(m.fighters[1].buffer.peek("special").is_empty(), "accepted recovery consumes special once")
	a.free()
	if not failures: print("PASS: force restrictions")
	quit(1 if failures else 0)
