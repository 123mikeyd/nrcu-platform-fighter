extends SceneTree
var failures: int = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var path := "res://scripts/core/input/player_input_source.gd"
	if not ResourceLoader.exists(path):
		push_error("PlayerInputSource implementation missing")
		quit(1)
		return
	var source = load(path).new()
	var frame = source.sample_snapshot(1, {KEY_A: true, KEY_D: true, KEY_SPACE: true})
	check(frame.axis.x == 0 and frame.pressed.get("jump", false), "opposites neutral, jump edge")
	frame = source.sample_snapshot(2, {KEY_SPACE: true})
	check(frame.held.jump and not frame.pressed.has("jump"), "held is not repeated edge")
	frame = source.sample_snapshot(3, {})
	check(frame.released.jump, "release retained")
	source.sample_snapshot(4, {KEY_SPACE: true})
	source.reset()
	frame = source.sample_snapshot(5, {KEY_SPACE: true})
	check(not frame.held.jump and frame.pressed.is_empty(), "reset suppresses held button")
	source.sample_snapshot(6, {})
	check(source.sample_snapshot(7, {KEY_SPACE: true}).pressed.jump, "release rearms reset")
	source.slot = 1
	frame = source.sample_snapshot(8, {KEY_RIGHT: true, KEY_ENTER: true})
	check(frame.axis.x == 1 and not frame.pressed.has("jump"), "reassignment suppresses initial held")
	source.sample_snapshot(9, {})
	check(source.sample_snapshot(10, {KEY_ENTER: true}).pressed.jump, "P2 defaults")
	source.bindings.jump = KEY_Z
	source.sample_snapshot(11, {})
	check(source.sample_snapshot(12, {KEY_Z: true}).pressed.jump, "key rebinding")
	source.device = 4
	source.sample_snapshot(13, {}, {}, Vector2.ZERO, true)
	frame = source.sample_snapshot(14, {}, {JOY_BUTTON_A: true}, Vector2(0.6, 0.1), true)
	check(is_equal_approx(frame.axis.x, 0.6) and frame.axis.y == 0, "analog preserved with axial deadzone")
	check(frame.pressed.jump, "pad mapped jump")
	frame = source.sample_snapshot(15, {}, {}, Vector2.ONE, false)
	check(not source.connected and frame.axis == Vector2.ZERO and frame.pressed.is_empty() and frame.held.is_empty(), "disconnect neutralizes")
	frame = source.sample_snapshot(16, {}, {JOY_BUTTON_A: true}, Vector2.ZERO, true)
	check(source.connected and not frame.held.jump, "reconnect held suppressed")
	source.sample_snapshot(17, {}, {}, Vector2.ZERO, true)
	source.tap_jump = true
	frame = source.sample_snapshot(18, {}, {}, Vector2(0, -0.8), true)
	check(frame.pressed.jump, "analog tap jump")
	frame = source.sample_snapshot(19, {}, {}, Vector2(0, 0.8), true)
	check(frame.pressed.down and frame.released.jump, "down edge plus jump release")
	Input.joy_connection_changed.emit(4, false)
	check(not source.connected, "hotplug signal updates connection between ticks")
	Input.joy_connection_changed.emit(4, true)
	frame = source.sample_snapshot(20, {}, {JOY_BUTTON_A: true}, Vector2.ZERO, true)
	check(frame.pressed.is_empty() and not frame.held.jump, "hotplug pair between samples suppresses phantom press")
	source.device = -1
	source.sample(20)
	check(source.connected, "real keyboard backend available")
	if failures == 0: print("PASS core input player")
	quit(failures)
