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
func run():
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(30, 1, 10)
	shape.shape = box; floor_body.add_child(shape); floor_body.position.y = -0.5; root.add_child(floor_body)
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1, a); m.register_actor(2, b); m.reset({1: Vector3.ZERO, 2: Vector3(1, 0, 0)})
	for i in 10: await step(m)
	var f = Frame.new(); f.pressed.special = true
	await step(m, {1: f})
	check(m.fighters[1].move_id == "ELECTRIC GRAB", "neutral special accepts actual grab")
	if m.fighters[1].move_id != "ELECTRIC GRAB":
		a.free(); b.free(); floor_body.free(); quit(1); return
	for i in 10: await step(m)
	check(m.fighters[2].caught_by == 0, "no immediate capture before .20")
	await step(m)
	check(m.fighters[2].caught_by == 1, "capture on twelfth completed tick")
	check(m.fighters[2].percent == 0, "capture is not damage")
	for i in 85: await step(m)
	check(m.fighters[2].percent == 10, "five electric ordinals total ten")
	check(b.runtime.hitstun_left == 0, "electric damage is status only")
	check(m.fighters[2].caught_by == 1, "retained through end start")
	for i in 13: await step(m)
	check(m.fighters[2].caught_by == 0, "source release event clears victim")
	check(b.get_collision_exceptions().is_empty(), "release clears collision exceptions")
	check(m.fighters[2].grab_immune_until > m.tick, "release grants immunity")
	for i in 20: await step(m)
	check(m.fighters[1].grab == null, "ending completes")
	a.free(); b.free(); floor_body.free()
	if not failures: print("PASS: grab vertical slice (%d checks)" % checks)
	quit(1 if failures else 0)
