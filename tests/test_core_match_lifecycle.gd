extends "res://tests/test_core_match_strikes.gd"
const Match = preload("res://scripts/core/match/match_simulation.gd")
func run() -> void:
	var m = Match.new()
	if not m.has_method("reset") or not m.has_method("cancel_action") or not m.has_method("set_enabled"):
		check(false, "explicit match reset/cancel/disable lifecycle exists")
	else:
		await lifecycle(m)
		var forward: Array = await trade(false, false)
		var reverse: Array = await trade(true, true)
		check(forward == reverse, "reversed node/registration order and visual removal preserve trades")
	if failures == 0: print("PASS: core match lifecycle (%d checks)" % checks)
	quit(1 if failures else 0)
func floor_body():
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 6)
	shape.shape = box
	floor.position.y = -0.5
	floor.add_child(shape)
	root.add_child(floor)
	return floor
func lifecycle(m) -> void:
	var floor = floor_body()
	var a = Actor.new()
	var b = Actor.new()
	root.add_child(a)
	root.add_child(b)
	m.register_actor(10, a)
	m.register_actor(20, b)
	m.reset({10: Vector3.ZERO, 20: Vector3(10, 0, 0)})
	for i in range(8): await tick(m)
	await tick(m, {10: frame(true)})
	check(m.fighters[10].move_id == "SIDE STRIKE", "ground acceptance selects SIDE STRIKE")
	var first: String = m.fighters[10].activation_id
	var accepted: int = m.tick - 1
	for i in range(19):
		var f = frame(false, 1.0)
		f.held.attack = true
		await tick(m, {10: f})
	check(m.fighters[10].activation_id == first and m.tick == accepted + 20, "holding does not repeat; cooldown blocks through t+19")
	check(a.position.x > 0.5, "generic cooldown never locks approved movement")
	await tick(m, {10: frame(true)})
	check(m.fighters[10].activation_id != first, "fresh edge accepted at t+20 ceil boundary")
	for i in range(16): await tick(m)
	await tick(m, {10: frame(true, -1.0)})
	check(not m.fighters[10].buffer.peek("attack").is_empty(), "illegal early edge remains buffered")
	var second: String = m.fighters[10].activation_id
	for i in range(3): await tick(m)
	check(m.fighters[10].activation_id != second and m.fighters[10].buffer.peek("attack").is_empty() and m.fighters[10].facing == -1, "buffer consumed only after legal with press-time facing")
	m.cancel_action(10, "test")
	m.cancel_action(10, "test")
	check(m.fighters[10].activation_id.is_empty() and m.fighters[10].move_id.is_empty(), "cancel is idempotent")
	m.set_enabled(10, false)
	var at: Vector3 = a.position
	await tick(m, {10: frame(true, 1.0)})
	check(a.position == at and m.fighters[10].activation_id.is_empty(), "disabled actor cannot move or activate")
	var generation: int = m.generation
	m.reset({10: Vector3.ZERO, 20: Vector3(1.5, 0, 0)})
	check(m.generation == generation + 1 and m.tick == 0 and m.events.is_empty(), "reset changes identity generation and clears events/tick")
	check(m.fighters[10].buffer.debug_pending().is_empty() and m.fighters[10].percent == 0 and a.runtime.hitstun_left == 0, "reset clears queue/damage/status")
	for i in range(8): await tick(m)
	await tick(m, {10: frame(true)})
	check(m.fighters[20].percent == 8, "new activation can hit same victim after reset")
	check(m.fighters[20].activation_id.is_empty(), "hit cancels victim action")
	var stun: int = b.runtime.hitstun_left
	for i in range(stun): await tick(m)
	check(b.runtime.hitstun_left == 0 and b.runtime.states.status == "normal", "hitstun ends after exact subsequent movement ticks")
	a.free()
	b.free()
	floor.free()
func trade(reverse: bool, remove_visual: bool) -> Array:
	var m = Match.new()
	var a = Actor.new()
	var b = Actor.new()
	var visual := Node3D.new()
	a.add_child(visual)
	for actor in ([b, a] if reverse else [a, b]): root.add_child(actor)
	if remove_visual: visual.free()
	if reverse:
		m.register_actor(20, b)
		m.register_actor(10, a)
	else:
		m.register_actor(10, a)
		m.register_actor(20, b)
	m.reset({10: Vector3(0, 5, 0), 20: Vector3(1.5, 5, 0)})
	await tick(m, {10: frame(true, 1.0), 20: frame(true, -1.0)})
	check(m.fighters[10].percent == 8 and m.fighters[20].percent == 8 and m.events.size() == 2, "both valid trade candidates survive hit cancellation")
	check(m.fighters[10].activation_id.is_empty() and m.fighters[20].activation_id.is_empty(), "trade interrupts both actions")
	var result := [m.fighters[10].percent, m.fighters[20].percent, a.velocity, b.velocity, a.position, b.position, m.events]
	a.free()
	b.free()
	return result
