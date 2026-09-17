extends "res://tests/test_core_directional_up.gd"
func run() -> void:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 4); shape.shape = box
	floor.position = Vector3(0, -0.5, 0); floor.add_child(shape); root.add_child(floor)
	var m = Match.new(); var a = Actor.new(); root.add_child(a); m.register_actor(1, a)
	for y in [-1.0, 1.0]:
		m.reset({1: Vector3(0, 0.01, 0)})
		a.runtime.velocity.y = -2
		check(not a.runtime.grounded, "starts airborne immediately above physical floor")
		await tick(m, {1: aim(Vector2(0, y))})
		check(a.runtime.grounded, "body lands on acceptance simulation tick")
		check(m.fighters[1].move_id == ("UP AIR" if y < 0 else "DOWN STRIKE"), "same-tick landing cannot retroactively turn accepted air basic into ground")
		var ready: int = m.fighters[1].ready_tick
		for i in 20: await tick(m)
		check(a.runtime.grounded and m.fighters[1].ready_tick == ready, "landing adds no basic-specific cooldown")
		await tick(m, {1: aim(Vector2(0, y))})
		check(m.fighters[1].move_id == ("UPPERCUT" if y < 0 else "LOW SWEEP"), "later settled acceptance chooses grounded name")
	a.free(); floor.free()
	if not failures: print("PASS: directional landing (%d checks)" % checks)
	quit(1 if failures else 0)
