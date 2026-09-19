extends SceneTree

var failures: int = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var path := "res://scripts/core/input/input_frame.gd"
	if not ResourceLoader.exists(path):
		check(false, "InputFrame implementation missing")
		quit(1)
		return
	var type = load(path)
	var frame = type.new()
	frame.tick = 12
	frame.axis = Vector2(-0.4, 0.7)
	frame.held = {"jump": true}
	frame.pressed = {"attack": true}
	frame.released = {"shield": true}
	frame.source_id = "keyboard:0"
	var data: Dictionary = frame.to_dict()
	var copy = type.from_dict(data)
	check(copy.tick == 12 and copy.axis.is_equal_approx(frame.axis), "typed tick/axis roundtrip")
	check(copy.source_id == frame.source_id and copy.released.shield, "source/release roundtrip")
	data.held.jump = false
	check(frame.held.jump and copy.held.jump, "serialization must detach dictionaries")
	check(type.from_dict({}).axis == Vector2.ZERO, "missing data is neutral")
	if failures == 0: print("PASS core input frame")
	quit(failures)
