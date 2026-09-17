extends "res://tests/test_core_force_acceptance.gd"
func emit(m):
	await step(m, {1: press()})
	for i in 14: await step(m)
func run():
	var m = Match.new(); var a = Actor.new(); root.add_child(a); m.register_actor(1, a)
	for reason in ["hit", "disable", "ko", "reset", "ttl", "early"]:
		m.reset({1: Vector3(0, 20, 0)})
		if reason == "early":
			await step(m, {1: press()}); m.cancel_action(1, "hit")
			for i in 20: await step(m)
			check(m.projectiles.is_empty(), "cancel before emission spawns nothing"); continue
		await emit(m)
		check(m.projectiles.size() == 1, "live shot before " + reason)
		match reason:
			"hit":
				m.cancel_action(1, "hit"); await step(m)
				check(m.projectiles.size() == 1, "ordinary cancellation retains emitted shot")
			"disable":
				m.set_enabled(1, false)
				check(m.projectiles.is_empty(), "disable expires owned shots immediately")
			"ko":
				if m.has_method("expire_source"): m.expire_source(1, "ko")
				check(m.projectiles.is_empty() and m.fighters[1].force == null, "KO seam expires source action and shots")
			"reset":
				m.reset({}); check(m.projectiles.is_empty(), "reset clears live shot")
			"ttl":
				for i in 95: await step(m)
				check(m.projectiles.size() == 1 and m.projectiles[0].ttl == 1, "TTL95 travel ticks")
				await step(m); check(m.projectiles.is_empty(), "TTL96 expires before travel")
	a.free()
	if not failures: print("PASS: force lifecycle")
	quit(1 if failures else 0)
