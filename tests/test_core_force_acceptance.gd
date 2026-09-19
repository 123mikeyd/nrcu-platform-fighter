extends SceneTree
const Match = preload("res://scripts/core/match/match_simulation.gd")
const Actor = preload("res://scripts/core/fighter/fighter_actor.gd")
const Frame = preload("res://scripts/core/input/input_frame.gd")
var failures := 0
func check(ok: bool, message: String):
	if not ok: failures += 1; printerr("FAIL: " + message)
func _init(): call_deferred("run")
func step(m, frames := {}):
	await physics_frame
	m.simulate(frames)
func press(axis := Vector2.RIGHT, action := "special"):
	var f = Frame.new(); f.axis = axis; f.pressed[action] = true
	return f
func run():
	var m = Match.new(); var a = Actor.new(); root.add_child(a)
	m.register_actor(1, a); m.reset({1: Vector3(0, 10, 0)})
	await step(m, {1: press()})
	check(m.fighters[1].move_id == "FORCE PUSH", "horizontal special accepted through actual buffer")
	check(m.fighters[1].buffer.peek("special").is_empty(), "accepted special consumed")
	check(m.fighters[1].ready_tick == 75, "legacy 1.25s cooldown")
	if m.fighters[1].move_id == "FORCE PUSH":
		check(m.projectiles.is_empty(), "no projectile on acceptance")
		for i in 13: await step(m)
		check(m.projectiles.is_empty(), "no emission before fifteenth advancement")
		await step(m)
		check(m.projectiles.size() == 1, "single emission at .25 seconds")
		for i in 45: await step(m)
		check(m.fighters[1].force == null and m.fighters[1].move_id == "", "phase ends at 1 second independently of cooldown")
		check(m.projectiles.size() == 1, "phase end retains projectile")
	a.free()
	if not failures: print("PASS: force acceptance clock")
	quit(1 if failures else 0)
