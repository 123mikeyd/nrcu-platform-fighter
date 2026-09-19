extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1, a); m.register_actor(2, b)
	m.reset({1: Vector3(0, 20, 0), 2: Vector3(0.5, 21, 0)})
	await step(m, {1: press()})
	check(m.fighters[2].percent == 12, "post-movement recovery hits for 12")
	if not m.events.is_empty():
		check(m.events[0].base_knockback == 5.5 and m.events[0].direction == Vector3(0.2, 1, 0), "source push payload")
	var identity: String = m.fighters[1].activation_id
	for i in 22:
		b.position = a.position + Vector3(0.5, 1, 0)
		await step(m)
	check(m.fighters[2].percent == 12, "one victim hit per activation across 23 queries")
	check(m.fighters[1].recovery == null, "23rd advancement retires active recovery")
	# Newly entering victim on final active tick still hits; on following tick does not.
	for entry_age in [23, 24]:
		m.reset({1: Vector3(0, 20, 0), 2: Vector3(20, 20, 0)})
		await step(m, {1: press(Vector2(-1, -1))})
		for i in entry_age - 2: await step(m)
		b.position = a.position + Vector3(-0.5, 1, 0)
		await step(m)
		check(m.fighters[2].percent == (12 if entry_age == 23 else 0), "final-call query endpoint age %d" % entry_age)
		if not m.events.is_empty(): check(m.events[0].direction.x < 0, "left-facing launch mirrors x")
		check(m.fighters[1].activation_id != identity, "reset/new activation identity distinct")
	for initial_y in [2.7, -0.3]:
		m.reset({1: Vector3(0, 20, 0), 2: Vector3(0.5, 20 + initial_y, 0)})
		await step(m, {1: press()})
		check(m.fighters[2].percent == (12 if initial_y == 2.7 else 0), "origin box samples after both actors move, offset %s" % initial_y)
	var ability = load("res://scripts/core/combat/recovery_ability.gd").new(1, "geometry")
	check(ability.has_method("contains"), "recovery has exact origin-box query")
	if ability.has_method("contains"):
		for point in [Vector3(1.3, 1, 0), Vector3(-1.3, 1, 0), Vector3(0, 1, 1), Vector3(0, 1, -1), Vector3(0, -0.4, 0), Vector3(0, 2.6, 0)]:
			check(not ability.contains(point), "strict boundary excluded %s" % point)
		for point in [Vector3.ZERO, Vector3(1.299, 2.599, 0.999), Vector3(-1.299, -0.399, -0.999)]:
			check(ability.contains(point), "interior origin included %s" % point)
	a.free(); b.free()
	if not failures: print("PASS: recovery contacts (%d checks)" % checks)
	quit(1 if failures else 0)
