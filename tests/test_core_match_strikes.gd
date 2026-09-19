extends SceneTree
const Actor = preload("res://scripts/core/fighter/fighter_actor.gd")
const Frame = preload("res://scripts/core/input/input_frame.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _init() -> void: call_deferred("run")
func frame(attack := false, x := 0.0):
	var f = Frame.new()
	f.axis.x = x
	f.pressed.attack = attack
	return f
func tick(m, frames := {}) -> void:
	await physics_frame
	m.simulate(frames)
func run() -> void:
	var path := "res://scripts/core/match/match_simulation.gd"
	if not ResourceLoader.exists(path):
		check(false, "match-owned two-actor strike path exists")
	else:
		await vertical(load(path))
	if failures == 0: print("PASS: core match strikes (%d checks)" % checks)
	quit(1 if failures else 0)
func vertical(Match) -> void:
	var m = Match.new()
	var a = Actor.new()
	var b = Actor.new()
	root.add_child(a)
	root.add_child(b)
	a.reset_at(Vector3(0, 5, 0))
	b.reset_at(Vector3(2.51, 5, 0))
	m.register_actor(10, a)
	m.register_actor(20, b)
	await tick(m, {10: frame(true, 1.0), 20: frame(false, -1.0)})
	check(a.position.x > 0 and b.position.x < 2.51, "both real bodies move before contacts")
	check(m.fighters[20].percent == 8.0, "acceptance tick hits using post-movement origin cone")
	check(m.fighters[10].move_id == "AIR STRIKE", "air context chooses air strike")
	var strength := 3.8 + 8.0 * 0.065 + 8.0 * 0.12
	check(b.velocity.is_equal_approx(Vector3(1, 0.35, 0).normalized() * strength), "updated-percent launch committed to real body")
	var x: float = b.position.x
	var vx: float = b.velocity.x
	await tick(m, {20: frame(false, -1.0)})
	check(b.position.x > x and is_equal_approx(b.velocity.x, vx), "next tick opposing input cannot overwrite damage launch")
	check(b.runtime.states.status == "hitstun" and not b.can_accept_jump(), "actual status persists and interrupts movement commands")
	a.free()
	b.free()
