extends "res://tests/test_core_grab_slice.gd"
func run():
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 10); shape.shape = box; floor_body.add_child(shape); floor_body.position.y = -0.5; root.add_child(floor_body)
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1, a); m.register_actor(2, b); m.reset({1: Vector3.ZERO, 2: Vector3.RIGHT})
	var source = preload("res://scripts/core/input/player_input_source.gd").new()
	for i in 10: await step(m, {2: source.sample_snapshot(m.tick, {})})
	var f = Frame.new(); f.pressed.special = true
	await step(m, {1: f, 2: source.sample_snapshot(m.tick, {})})
	for i in 11: await step(m, {2: source.sample_snapshot(m.tick, {})})
	check(m.fighters[2].caught_by == 1, "real source capture setup")
	# Introduce actual fresh keyboard edges during restraint, retain held state across release.
	for i in 110:
		var input = source.sample_snapshot(m.tick, {KEY_F: true, KEY_SPACE: true})
		check(input.pressed.is_empty() if i > 0 else input.pressed.get("attack", false), "source edge history sampled throughout caught state")
		await step(m, {2: input})
	check(m.fighters[2].caught_by == 0 and m.fighters[2].move_id == "", "held keyboard does not replay caught attack")
	check(b.velocity.y <= 0 and m.fighters[2].buffer.debug_pending().is_empty(), "held keyboard does not replay caught jump")
	await step(m, {2: source.sample_snapshot(m.tick, {})})
	await step(m, {2: source.sample_snapshot(m.tick, {KEY_F: true})})
	check(m.fighters[2].move_id == "SIDE STRIKE", "fresh postrelease edge rearms normally")
	a.free(); b.free(); floor_body.free()
	if not failures: print("PASS: grab real input source (%d checks)" % checks)
	quit(1 if failures else 0)
