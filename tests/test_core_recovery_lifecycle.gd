extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1, a); m.register_actor(2, b)
	for reason in ["cancel", "hit", "preexisting_hit", "disable", "reset"]:
		m.reset({1: Vector3(0, 20, 0), 2: Vector3(10, 20, 0)})
		await step(m, {1: press()})
		if reason == "cancel":
			m.cancel_action(1, "test"); m.cancel_action(1, "test")
		elif reason == "hit":
			b.position = a.position + Vector3(1, 0, 0)
			await step(m, {2: press(Vector2.LEFT, "attack")})
			check(m.fighters[1].percent == 8 and m.fighters[2].percent == 12, "recovery/strike snapshot trade survives source interruption")
		elif reason == "preexisting_hit":
			a.apply_combat_launch(Vector3(3, 8, 0), 5)
			await step(m, {1: press()})
			check(is_equal_approx(a.velocity.y, 8 - 32.0/60) and a.velocity.x == 3, "hitstun owns launch and gravity, not recovery")
		elif reason == "disable":
			m.set_enabled(1, false); m.set_enabled(1, false)
		else:
			m.reset({1: Vector3(0, 20, 0), 2: Vector3(10, 20, 0)})
			m.reset({})
		check(m.fighters[1].recovery == null and m.fighters[1].move_id == "", "idempotent cleanup " + reason)
		check(not a.runtime.recovery_motion, "motion ownership released " + reason)
		check(a.runtime.recovery_spent == (reason != "reset"), "cancel does not refund spent resource " + reason)
		check(m.fighters[1].ready_tick == (0 if reason == "reset" else 39), "cancel preserves cooldown " + reason)
		if reason == "disable":
			b.position = a.position + Vector3(0.5, 1, 0)
			await step(m)
			check(m.fighters[2].percent == 0, "disabled recovery cannot hit")
	# Spent resource is not a blanket special-fall lock.
	m.reset({1: Vector3(0, 50, 0), 2: Vector3(20, 50, 0)})
	await step(m, {1: press()})
	for i in 38: await step(m)
	await step(m, {1: press()})
	check(m.fighters[1].recovery == null and a.runtime.recovery_spent, "repeat recovery denied at expired cooldown")
	check(not m.fighters[1].buffer.peek("special").is_empty(), "illegal repeat remains buffered")
	for i in 6: await step(m)
	check(m.fighters[1].buffer.peek("special").is_empty(), "illegal repeat expires without acceptance")
	await step(m, {1: press(Vector2.RIGHT, "attack")})
	check(m.fighters[1].move_id == "AIR STRIKE", "spent recovery allows later basic")
	for i in 20: await step(m)
	await step(m, {1: press(Vector2.RIGHT)})
	check(m.fighters[1].move_id == "FORCE PUSH", "spent recovery allows later force")
	for i in 14: await step(m)
	check(m.projectiles.size() == 1, "later force emits normally")
	m.cancel_action(1, "hit")
	check(m.projectiles.size() == 1, "recovery cleanup does not remove emitted force")
	a.free(); b.free()
	if not failures: print("PASS: recovery lifecycle (%d checks)" % checks)
	quit(1 if failures else 0)
