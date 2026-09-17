extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _init() -> void:
	var r = load("res://scripts/core/fighter/fighter_runtime.gd").new()
	if not r.has_method("can_accept_jump"):
		check(false, "runtime exposes jump legality")
	else:
		test_jump(r)
	if failures == 0: print("PASS: core movement jump (%d checks)" % checks)
	quit(1 if failures else 0)
func test_jump(r) -> void:
	var p = load("res://scripts/core/fighter/movement_profile.gd").new()
	r.reset(true)
	check(r.can_accept_jump(), "ground jump legal")
	r.step({"jump": true, "jump_held": true})
	check(r.states.locomotion == "jump_startup" and r.velocity.y == 0, "startup does not launch immediately")
	check(not r.can_accept_jump(), "startup cannot consume another jump")
	for i in range(p.jump_startup_ticks - 1):
		r.step({"jump_held": true})
		check(r.velocity.y == 0, "startup integer window retained")
	r.step({"jump_held": true})
	check(r.states.locomotion == "rising" and is_equal_approx(r.velocity.y, p.full_jump_speed), "full jump launches after startup")
	check(not r.grounded and r.air_jumps_left == 1, "ground launch preserves air resource")
	var full := trajectory(r, false)
	r.reset(true)
	r.step({"jump": true, "jump_held": true})
	r.step({"jump_released": true})
	for i in range(p.jump_startup_ticks - 1): r.step({"jump_held": true})
	check(is_equal_approx(r.velocity.y, p.short_jump_speed), "startup release is latched even after repress")
	var short := trajectory(r, false)
	check(short < full, "short hop apex lower than full hop")
	r.reset(true)
	r.step({"jump": true, "jump_held": true})
	for i in range(p.jump_startup_ticks): r.step({"jump_held": true})
	r.step({"jump_released": true})
	check(r.velocity.y <= p.short_jump_speed, "late rising release cuts jump")
	r.step({"jump": true, "jump_held": true})
	check(r.air_jumps_left == 0 and is_equal_approx(r.velocity.y, p.air_jump_speed), "air jump consumes separate resource")
	check(not r.can_accept_jump(), "no third jump")
	var before: float = r.velocity.y
	r.step({"jump": true, "jump_held": true})
	check(r.velocity.y < before, "illegal jump not executed")
	r.reset(true)
	r.reconcile_contact(false, Vector3.ZERO)
	check(r.states.locomotion == "falling" and r.air_jumps_left == 1, "walkoff loses ground opportunity only")
	r.step({"jump": true, "jump_held": true})
	check(r.air_jumps_left == 0 and r.velocity.y == p.air_jump_speed, "walkoff jump is air jump without coyote")
func trajectory(r, release: bool) -> float:
	var y := 0.0
	var apex := 0.0
	for i in range(120):
		y += r.velocity.y / 60.0
		apex = maxf(apex, y)
		r.step({"jump_held": not release})
	return apex
