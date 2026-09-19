extends "res://tests/test_core_recovery_acceptance.gd"
const Runtime = preload("res://scripts/core/fighter/fighter_runtime.gd")
func floor_body(at: Vector3, size: Vector3):
	var body = StaticBody3D.new(); body.position = at
	var c = CollisionShape3D.new(); var box = BoxShape3D.new(); box.size = size; c.shape = box
	body.add_child(c); root.add_child(body); return body
func run():
	var r = Runtime.new(); r.reset(true); r.velocity.x = 4
	r.step({"recovery_launch": true, "jump_released": true, "down": true})
	check(r.velocity == Vector3(4, 13.5, 0) and not r.grounded, "launch supersedes gravity/release/fastfall")
	r.reconcile_contact(true, r.velocity)
	check(not r.grounded and r.recovery_spent and r.air_jumps_left == 0, "stale upward floor cannot refund takeoff")
	r.step({"jump_released": true})
	check(is_equal_approx(r.velocity.y, 13.5 - 32.0/60), "jump release cannot clip recovery ascent; base gravity resumes")
	check(is_equal_approx(r.velocity.x, 4 - 22.0/60), "base air control resumes next tick")
	for i in 30: r.step({"down": true})
	check(r.velocity.y == -26, "new down after apex retains accepted fastfall policy")
	r.reconcile_contact(true, Vector3.ZERO)
	check(not r.recovery_spent and r.air_jumps_left == 1, "descending terrain restores air resources")
	r.reset(); check(not r.recovery_spent, "pure runtime reset restores resource")
	r.velocity.y = -1; r.step({"down": true})
	check(r.velocity.y == -26, "fixture enters active fastfall")
	r.step({"recovery_launch": true}); r.step({})
	check(is_equal_approx(r.velocity.y, 13.5 - 32.0/60), "recovery clears preexisting fastfall, not just same-tick down")
	r.reset(true); r.step({"jump": true, "jump_held": true})
	r.step({"recovery_launch": true})
	for i in 3: r.step({"jump_held": true})
	check(is_equal_approx(r.velocity.y, 13.5 - 3 * 32.0/60), "recovery replaces jump startup with no deferred jump impulse")
	var m = Match.new(); var a = Actor.new(); root.add_child(a); m.register_actor(1, a)
	var floor = floor_body(Vector3(0, -0.5, 0), Vector3(30, 1, 4))
	m.reset({1: Vector3(0, 1, 0)})
	for i in 40: await step(m)
	check(a.runtime.grounded, "real actor settled on terrain")
	var launch = press(); launch.pressed.jump = true; launch.pressed.down = true
	await step(m, {1: launch})
	check(a.position.y > 0.1 and a.velocity.y == 13.5 and not a.runtime.grounded, "actual ground takeoff survives reconciliation")
	check(not m.fighters[1].buffer.peek("jump").is_empty(), "simultaneous illegal jump not consumed by recovery")
	check(a.runtime.recovery_spent, "ground launch spends recovery")
	for i in 70: await step(m)
	check(a.runtime.grounded and not a.runtime.recovery_spent and a.can_accept_jump(), "actual landing restores resources after landing lock")
	await step(m, {1: press()})
	check(a.velocity.y == 13.5 and a.runtime.recovery_spent and m.fighters[1].recovery != null, "actual terrain landing permits next recovery activation")
	# Force an early descent during an active recovery, onto terrain before contacts.
	var b = Actor.new(); root.add_child(b); m.register_actor(2, b)
	m.reset({1: Vector3(0, 0.01, 0), 2: Vector3(5, 0.01, 0)})
	await step(m, {1: press()})
	a.position.y = 0.01; a.runtime.velocity.y = -10
	b.position = Vector3(0.5, 0.01, 0)
	await step(m)
	check(a.runtime.grounded and m.fighters[1].recovery == null, "landing cancels active recovery before contact collection")
	check(m.fighters[2].percent == 0, "same-tick landing cancels would-be recovery hit")
	# Ceiling is terrain, but never a restorative floor.
	var ceiling = floor_body(Vector3(0, 3.2, 0), Vector3(4, 0.2, 4))
	m.reset({1: Vector3(0, 0.1, 0), 2: Vector3(10, 0, 0)})
	await step(m, {1: press()})
	var head := false
	for i in 10:
		await step(m)
		if a.is_on_ceiling():
			head = true
			check(a.runtime.recovery_spent and not a.runtime.grounded and not a.can_accept_jump(), "head collision never restores resources")
	check(head, "actual recovery hits ceiling")
	floor.free(); ceiling.free()
	m.reset({1: Vector3(0, 4, 0), 2: Vector3(0, 0, 0)})
	m.set_enabled(2, false) # Frozen capsule is still present but is never terrain.
	await step(m, {1: press()})
	for i in 80: await step(m)
	check(a.position.y < b.position.y and not a.runtime.grounded and a.runtime.recovery_spent, "passing through a fighter head does not refresh recovery")
	a.free(); b.free()
	if not failures: print("PASS: recovery motion (%d checks)" % checks)
	quit(1 if failures else 0)
