extends "res://tests/test_core_directional_up.gd"
func run() -> void:
	for file in ["uppercut", "up_air", "low_sweep", "down_strike"]:
		var move = load("res://data/moves/%s.tres" % file)
		check(move.damage == 8 and move.base_knockback == 3.8 and move.cooldown_seconds == 0.32 and move.cooldown_ticks() == 20, file + " exact shared data")
		for facing in [-1.0, 1.0]:
			var q: Vector3 = move.query_direction(facing)
			# Axis-aligned endpoints are exactly representable. q*2.5 for a
			# tilted normalized vector can round OUTSIDE 2.5; never widen policy.
			var radial := Vector3(facing, 0, 0) if file == "low_sweep" else q
			check(move.contains(radial * 2.5, facing) and not move.contains(radial * 2.5001, facing), file + " inclusive range endpoint")
			check(not move.contains(q + Vector3(0, 0, 1.5), facing) and move.contains(q + Vector3(0, 0, 1.499), facing), file + " strict z endpoint")
			check(not move.contains(Vector3.ZERO, facing) and not move.contains(-q, facing), file + " zero/back excluded")
			if file != "low_sweep":
				check(not move.contains(Vector3(sqrt(0.84), q.y * 0.4, 0), facing), file + " exact dot endpoint excluded")
				check(move.contains(Vector3(sqrt(0.84), q.y * 0.401, 0), facing), file + " just inside dot included")
			else:
				check(q.is_equal_approx(Vector3(facing, -0.25, 0).normalized()), "sweep exact query")
				var launch := q; launch.y = 0.35
				check(move.launch_direction(facing) == launch and not launch.is_equal_approx(Vector3(facing, 0.35, 0)), "sweep launch retains normalized x, never approximates one")
				var tangent := Vector3(-q.y, q.x, 0)
				check(not move.contains(q * 0.3999 + tangent * sqrt(0.84), facing) and move.contains(q * 0.4001 + tangent * sqrt(0.84), facing), "sweep cone strict adjacent points")
	# Actual SceneTree range endpoint and post-movement query (same gravity for both).
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1, a); m.register_actor(2, b)
	for distance in [2.5, 2.5001]:
		m.reset({1: Vector3(0, 30, 0), 2: Vector3(0, 30 + distance, 0)})
		await tick(m, {1: aim(Vector2.UP)})
		check(m.fighters[2].percent == (8.0 if distance == 2.5 else 0.0), "real origin range endpoint %s" % distance)
	m.reset({1: Vector3(0, 30, 0), 2: Vector3(0, 32.51, 0)})
	a.runtime.velocity.y = 2
	await tick(m, {1: aim(Vector2.UP)})
	check(b.position.y - a.position.y < 2.5 and m.fighters[2].percent == 8, "post-movement up contact enters initially out-of-range target")
	# Opposed vertical basics trade even though each incoming hit cancels source identity.
	for reverse in [false, true]:
		m = Match.new()
		if reverse: m.register_actor(2, b); m.register_actor(1, a)
		else: m.register_actor(1, a); m.register_actor(2, b)
		m.reset({1: Vector3(0, 30, 0), 2: Vector3(0, 32, 0)})
		await tick(m, {1: aim(Vector2.UP), 2: aim(Vector2.DOWN)})
		check(m.events.size() == 2 and m.fighters[1].percent == 8 and m.fighters[2].percent == 8, "stable shared-snapshot vertical trade")
		check(a.velocity.y < 0 and b.velocity.y > 0 and m.fighters[1].activation_id.is_empty() and m.fighters[2].activation_id.is_empty(), "trade launches cancel both only after snapshot")
		check(m.resolver.resolve(m.events, {1: 8.0, 2: 8.0}).is_empty(), "same activation/victim cannot resolve twice")
		await tick(m)
		check(m.events.is_empty() and m.fighters[1].percent == 8 and m.fighters[2].percent == 8, "no repeat active volume")
	a.free(); b.free()
	if not failures: print("PASS: directional geometry (%d checks)" % checks)
	quit(1 if failures else 0)
