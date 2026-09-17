extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _init() -> void:
	var path := "res://scripts/core/fighter/fighter_runtime.gd"
	if not ResourceLoader.exists(path):
		check(false, "pure movement runtime exists")
	else:
		test_ground(load(path))
	if failures == 0:
		print("PASS: core movement (%d checks)" % checks)
	quit(1 if failures else 0)
func test_ground(runtime_script) -> void:
	var p = load("res://data/characters/teknium_movement.tres")
	var r = runtime_script.new(p)
	r.reset(true)
	r.step({"move_x": 0.4})
	check(r.velocity.x > 0 and r.velocity.x < p.run_speed, "analog ground acceleration")
	check(r.states.locomotion == "walk", "analog walk state")
	for i in range(60): r.step({"move_x": 0.4})
	check(is_equal_approx(r.velocity.x, p.run_speed * 0.4), "analog steady speed preserved")
	r.reset(true)
	r.step({"move_x": 1.0})
	check(r.states.locomotion == "initial_dash", "full input starts dash window")
	check(r.velocity.x > p.ground_acceleration / 60.0, "initial dash has distinct launch acceleration")
	for i in range(p.initial_dash_ticks): r.step({"move_x": 1.0})
	check(r.states.locomotion == "run", "dash expires to run")
	r.step({"move_x": -1.0})
	check(r.states.locomotion == "turn", "reversal has explicit turn")
	r.step({})
	check(r.states.locomotion == "brake", "neutral brakes momentum")
	for i in range(60): r.step({})
	check(r.velocity.x == 0 and r.states.locomotion == "idle", "friction stops motion")
	var other = runtime_script.new(p)
	other.reset(true)
	other.step({"move_x": -0.4})
	r.reset(true)
	r.step({"move_x": 0.4})
	check(is_equal_approx(r.velocity.x, -other.velocity.x), "mirrored acceleration")
	var original: float = p.run_speed
	p.run_speed = original * 2
	for i in range(60): r.step({"move_x": 0.4})
	check(is_equal_approx(r.velocity.x, original * 0.4), "runtime snapshots tunable definition")
	p.run_speed = original
	r.step({"shield": true, "move_x": 1.0})
	check(r.velocity.x == 0 and r.states.action == "movement_lock", "action arbitrates movement")
	r.step({})
	check(r.states.action == "neutral", "action lock releases")
	check(not r.states.transition("locomotion", "imaginary", "invalid"), "unknown transition rejected")
	check(r.states.transition_reason != "", "real transition reason recorded")
