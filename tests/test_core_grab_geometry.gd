extends "res://tests/test_core_grab_slice.gd"
const Grab = preload("res://scripts/core/combat/grab_ability.gd")
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); var c = Actor.new()
	root.add_child(a); root.add_child(b); root.add_child(c)
	m.register_actor(1, a); m.register_actor(2, b); m.register_actor(3, c)
	for facing in [1.0, -1.0]:
		for reason in ["closest", "tie", "shield", "team", "disabled", "frozen", "immune", "caught", "busy", "behind", "range", "wall"]:
			m.reset({1: Vector3(0, 10, 0), 2: Vector3(facing, 10, 0), 3: Vector3(facing * 1.3, 10, 0)})
			m.fighters[1].facing = facing
			var wall: StaticBody3D
			match reason:
				"tie": c.position = b.position
				"shield": m.fighters[2].shield_command = true
				"team": m.fighters[1].team = 1; m.fighters[2].team = 1
				"disabled": m.set_enabled(2, false)
				"frozen": m.set_frozen(2, true)
				"immune": m.fighters[2].grab_immune_until = 60
				"caught": m.fighters[2].caught_by = 3
				"busy": m.fighters[2].grab = Grab.new(-facing, "other")
				"behind": b.position.x = -facing
				"range": b.position.x = facing * 1.851
				"wall":
					wall = StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
					box.size = Vector3(0.1, 5, 5); shape.shape = box; wall.add_child(shape); wall.position = Vector3(facing * 0.5, 11, 0); root.add_child(wall)
			await physics_frame
			var g = Grab.new(facing, "test")
			var target := g.closest(1, m.fighters, 0)
			check(target == (2 if reason in ["closest", "tie"] else 0 if reason == "wall" else 3), "geometry " + reason + str(facing))
			m.fighters[2].caught_by = 0; m.fighters[1].team = -1; m.fighters[2].team = -1
			if wall != null: wall.free()
	# Two casters cannot capture one another while busy; lower stable ID wins victim.
	# Legal body spacing gives both casters equal reach without overlap recovery.
	m.reset({1: Vector3(-1, 10, 0), 2: Vector3(0, 10, 0), 3: Vector3(1, 10, 0)})
	m.fighters[3].facing = -1
	var f = Frame.new(); f.pressed.special = true
	await step(m, {1: f, 3: f})
	for i in 11: await step(m)
	check(m.fighters[2].caught_by == 1 and m.fighters[3].grab.victim == 0, "stable caster ID contest")
	m.cancel_action(1, "test")
	a.free(); b.free(); c.free()
	if not failures: print("PASS: grab geometry (%d checks)" % checks)
	quit(1 if failures else 0)
