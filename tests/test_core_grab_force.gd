extends "res://tests/test_core_grab_slice.gd"
func run():
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 10); shape.shape = box; floor_body.add_child(shape); floor_body.position.y = -0.5; root.add_child(floor_body)
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1, a); m.register_actor(2, b); m.reset({1: Vector3.ZERO, 2: Vector3.RIGHT})
	for i in 10: await step(m)
	var force = Frame.new(); force.axis = Vector2.RIGHT; force.pressed.special = true
	await step(m, {2: force})
	for i in 59: await step(m)
	check(m.fighters[2].force == null and m.projectiles.size() == 1, "emitted force survives completed caster episode")
	var grab = Frame.new(); grab.pressed.special = true
	await step(m, {1: grab})
	for i in 11: await step(m)
	check(m.fighters[2].caught_by == 1, "former force caster can be captured")
	check(m.projectiles.size() == 1, "capture does not expire emitted force")
	m.cancel_action(2, "utility")
	check(m.projectiles.size() == 1 and m.fighters[2].caught_by == 0, "utility releases but preserves emitted force")
	var releases := 0
	for event in m.ability_events:
		if event.get("kind") == "grab_release": releases += 1
	m.cancel_action(1, "duplicate"); m.cancel_action(2, "duplicate")
	var repeated := 0
	for event in m.ability_events:
		if event.get("kind") == "grab_release": repeated += 1
	check(releases == 1 and repeated == 1, "release event exactly once across duplicate cancels")
	m.set_enabled(2, false)
	check(m.projectiles.is_empty(), "disable still expires source projectiles")
	a.free(); b.free(); floor_body.free()
	if not failures: print("PASS: grab force ownership (%d checks)" % checks)
	quit(1 if failures else 0)
