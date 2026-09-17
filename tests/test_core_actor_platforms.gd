extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _init() -> void: call_deferred("run")
func tick(actor, commands: Dictionary = {}) -> void:
	await physics_frame
	actor.simulate(commands)
func body(at: Vector3, size: Vector3, one_way: bool = false) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.position = at
	var c := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	c.shape = shape
	b.add_child(c)
	if one_way:
		b.add_to_group("core_pass_through")
		b.set_meta("top_y", at.y + size.y / 2)
	root.add_child(b)
	return b
func run() -> void:
	Engine.physics_ticks_per_second = 60
	var floor = body(Vector3(0, -0.5, 0), Vector3(20, 1, 4))
	var platform = body(Vector3(0, 1.6, 0), Vector3(4, 0.2, 4), true)
	var a = load("res://scripts/core/fighter/fighter_actor.gd").new()
	root.add_child(a)
	a.reset_at(Vector3.ZERO)
	for i in range(15): await tick(a)
	await tick(a, {"jump": true, "jump_held": true})
	var crossed := false
	for i in range(100):
		await tick(a, {"jump_held": true})
		crossed = crossed or a.position.y > 1.75
	check(crossed, "capsule jumps through one-way underside")
	check(a.runtime.grounded and absf(a.position.y - 1.7) < 0.04, "descent lands on platform top")
	if crossed:
		await tick(a, {"down": true, "jump": true, "jump_held": true})
		check(a.runtime.states.locomotion == "jump_startup", "jump takes priority over same-tick drop")
		for i in range(100): await tick(a, {"jump_held": true})
		await tick(a, {"down": true})
		for i in range(60): await tick(a)
		check(a.runtime.grounded and absf(a.position.y) < 0.04, "down edge drops to solid floor without snap-back")
		await tick(a, {"down": true})
		for i in range(20): await tick(a)
		check(a.runtime.grounded and absf(a.position.y) < 0.04, "solid floor cannot be dropped through")
		a.reset_at(Vector3(0, 3, 0))
		for i in range(60): await tick(a)
		check(absf(a.position.y - 1.7) < 0.04, "reset clears platform exceptions")
		for i in range(40):
			await tick(a, {"move_x": 1.0})
			if not a.runtime.grounded: break
		check(not a.runtime.grounded and a.runtime.air_jumps_left == 1, "platform walkoff retains only air jump")
		await tick(a, {"jump": true, "jump_held": true})
		check(a.runtime.air_jumps_left == 0 and a.velocity.y > 0, "platform walkoff air jump executes")
	a.free()
	platform.free()
	floor.free()
	if failures == 0: print("PASS: core actor platforms (%d checks)" % checks)
	quit(1 if failures else 0)
