extends SceneTree
const Match = preload("res://scripts/core/match/match_simulation.gd")
const Actor = preload("res://scripts/core/fighter/fighter_actor.gd")
const Frame = preload("res://scripts/core/input/input_frame.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: " + message)
func _init(): call_deferred("run")
func step(m, frames := {}):
	await physics_frame
	m.simulate(frames)
func press(axis := Vector2.UP, action := "special"):
	var f = Frame.new(); f.axis = axis; f.pressed[action] = true
	return f
func run():
	var m = Match.new(); var a = Actor.new(); root.add_child(a)
	m.register_actor(1, a); m.reset({1: Vector3(0, 20, 0)})
	a.runtime.velocity.x = 3.0
	await step(m, {1: press(Vector2(-1, -1))})
	check(m.fighters[1].move_id == "RISING STRIKE", "up takes precedence over horizontal special")
	check(m.fighters[1].buffer.peek("special").is_empty(), "accepted recovery consumes buffered edge")
	check(m.fighters[1].ready_tick == 39, "recovery cooldown is 39 ticks")
	check(is_equal_approx(a.velocity.y, 13.5), "acceptance launches at exactly 13.5 before gravity")
	check(is_equal_approx(a.velocity.x, 3.0), "acceptance retains horizontal velocity")
	check(a.runtime.air_jumps_left == 0 and not a.can_accept_jump(), "recovery spends jump budget")
	a.free()
	if not failures: print("PASS: recovery acceptance (%d checks)" % checks)
	quit(1 if failures else 0)
