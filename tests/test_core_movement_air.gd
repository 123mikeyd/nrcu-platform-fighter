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
	r.reset(false)
	r.step({"move_x": 0.5})
	check(r.velocity.x > 0, "analog aerial acceleration")
	if r.velocity.x > 0: test_air(r)
	if failures == 0: print("PASS: core movement air (%d checks)" % checks)
	quit(1 if failures else 0)
func test_air(r) -> void:
	var p = load("res://scripts/core/fighter/movement_profile.gd").new()
	check(is_equal_approx(r.velocity.x, p.air_acceleration / 60.0), "air acceleration tuning")
	for i in range(180): r.step({"move_x": 0.5})
	check(is_equal_approx(r.velocity.x, p.air_speed * 0.5), "analog aerial target")
	check(r.velocity.y == -p.fall_speed, "normal fall terminal cap")
	r.step({"down": true})
	check(r.states.locomotion == "fast_fall" and r.velocity.y == -p.fast_fall_speed, "down edge engages fast fall during fall")
	r.step({})
	check(r.velocity.y == -p.fast_fall_speed, "fast fall persists without held down")
	r.step({"jump": true, "jump_held": true, "down": true})
	check(r.states.locomotion == "rising" and r.velocity.y > 0, "air jump clears fast fall and down cannot cancel rise")
	r.step({"down": true, "jump_held": true})
	check(r.velocity.y > 0, "fast fall rejected while rising")
	r.reconcile_contact(true, Vector3.ZERO)
	check(r.states.locomotion == "landing" and r.states.action == "landing_lock", "contact enters distinct landing lock")
	check(r.air_jumps_left == p.air_jumps, "landing replenishes air jumps")
	check(not r.can_accept_jump(), "landing initially rejects jump")
	for i in range(p.landing_ticks):
		r.step({"jump": true, "jump_held": true, "move_x": 1.0})
		check(r.velocity == Vector3.ZERO, "landing lock owns motion for integer window")
		r.reconcile_contact(true, Vector3.ZERO)
	check(r.can_accept_jump(), "repeated floor contact does not restart landing delay")
	r.step({"jump": true, "jump_held": true})
	check(r.states.locomotion == "jump_startup", "external buffered request accepted once landing legal")
	r.reset(false)
	r.step({"shield": true})
	check(r.velocity.y < 0, "movement lock cannot suspend aerial gravity")
	r.states.transition("status", "disabled", "test status")
	check(not r.can_accept_jump(), "status priority blocks action")
	check(not r.states.transition("action", "neutral", "blocked"), "status rejects lower priority transitions")
	r.reset(true)
	check(r.states.status == "normal" and r.states.action == "neutral" and r.tick == 0, "reset clears clocks status action")
	check(r.states.trace.is_empty() and r.air_jumps_left == 1, "ground reset clears trace and restores jumps")
