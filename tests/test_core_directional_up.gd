extends "res://tests/test_core_match_strikes.gd"
const Match = preload("res://scripts/core/match/match_simulation.gd")
func aim(axis: Vector2):
	var f = Frame.new()
	f.axis = axis
	f.pressed.attack = true
	return f
func run() -> void:
	for grounded in [false, true]:
		var m = Match.new()
		var a = Actor.new(); var b = Actor.new(); var c = Actor.new()
		for actor in [a, b, c]: root.add_child(actor)
		m.register_actor(1, a); m.register_actor(2, b); m.register_actor(3, c)
		m.reset({1: Vector3(0, 30, 0), 2: Vector3(0, 32, 0), 3: Vector3(0, 28, 0)})
		a.runtime.grounded = grounded
		await tick(m, {1: aim(Vector2(-1, -1))})
		check(m.fighters[1].move_id == ("UPPERCUT" if grounded else "UP AIR"), "up basic selects acceptance grounded context")
		check(m.fighters[2].percent == 8 and m.fighters[3].percent == 0, "up query hits above not below through real bodies")
		check(b.velocity.is_equal_approx(Vector3.UP * (3.8 + 8 * 0.065 + 8 * 0.12)), "up basic launches exactly upward")
		check(m.fighters[1].ready_tick == 20 and m.fighters[1].buffer.peek("attack").is_empty(), "accepted basic consumes edge and starts 20 tick cooldown")
		check(a.runtime.states.action == "neutral" and not a.runtime.recovery_spent, "no movement lock or recovery resource")
		for actor in [a, b, c]: actor.free()
	if not failures: print("PASS: directional up (%d checks)" % checks)
	quit(1 if failures else 0)
