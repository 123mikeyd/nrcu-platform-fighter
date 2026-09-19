extends SceneTree
const Frame = preload("res://scripts/core/input/input_frame.gd")
var failures: int = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var path := "res://scripts/core/input/input_buffer.gd"
	if not ResourceLoader.exists(path):
		push_error("InputBuffer implementation missing")
		quit(1)
		return
	var buffer = load(path).new()
	buffer.window_ticks = 2
	var frame = Frame.new()
	frame.tick = 10
	frame.axis = Vector2.LEFT
	frame.pressed = {"jump": true, "attack": true}
	buffer.advance(frame)
	var request: Dictionary = buffer.peek("jump")
	check(request.tick == 10 and request.axis == Vector2.LEFT, "press-time context")
	request.axis = Vector2.RIGHT
	check(buffer.consume("jump").axis == Vector2.LEFT, "peek detached")
	check(buffer.consume("jump").is_empty(), "consume once")
	buffer.advance(frame)
	check(buffer.peek("jump").is_empty(), "duplicate sample cannot requeue consumed press")
	frame.tick += 1
	frame.pressed = {}
	buffer.advance(frame, true)
	check(not buffer.peek("attack").is_empty(), "hitstop freezes aging")
	buffer.advance(frame)
	check(not buffer.peek("attack").is_empty(), "valid before age endpoint")
	frame.tick += 1
	buffer.advance(frame)
	check(buffer.peek("attack").is_empty(), "expires at window endpoint")
	frame.tick += 1
	frame.pressed = {"down": true, "attack": true}
	buffer.advance(frame)
	check(buffer.peek("down").sequence > request.sequence, "monotonic event identity")
	check(buffer.debug_pending().size() == 2, "debug queue")
	buffer.clear()
	check(buffer.debug_pending().is_empty(), "restart flush")
	if failures == 0: print("PASS core input buffer")
	quit(failures)
