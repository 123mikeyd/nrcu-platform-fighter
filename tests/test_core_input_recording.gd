extends SceneTree
const Frame = preload("res://scripts/core/input/input_frame.gd")
var failures: int = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var path := "res://scripts/core/input/recorded_input_source.gd"
	if not ResourceLoader.exists(path):
		push_error("recorded source missing")
		quit(1)
		return
	var recorder = load(path).new()
	var frame := Frame.new()
	frame.tick = 3
	frame.axis = Vector2(0.4, -0.6)
	frame.pressed = {"jump": true}
	frame.held = {"jump": true}
	recorder.record(frame)
	frame.pressed.clear()
	frame.held.clear()
	frame.released = {"jump": true}
	recorder.record(frame)
	var replay = recorder.sample(99)
	check(replay.tick == 99 and replay.pressed.jump and replay.axis == frame.axis, "detached record, reticked playback")
	replay.pressed.clear()
	check(recorder.sample(100).released.jump, "playback release")
	check(recorder.sample(101).axis == Vector2.ZERO, "neutral at end")
	recorder.rewind()
	check(recorder.sample(0).pressed.jump, "rewind not mutated by playback")
	var file := "user://test_core_input_recording.json"
	check(recorder.save_recording(file) == OK, "save recording")
	var copy = load(path).new()
	check(copy.load_recording(file) == OK and copy.frames.size() == 2, "load recording")
	check(copy.sample(1).pressed.jump, "disk roundtrip")
	var output := FileAccess.open(file, FileAccess.WRITE)
	output.store_string('{"frames":[{"axis":["oops",{}]}]}')
	output.close()
	check(copy.load_recording(file) == ERR_INVALID_DATA and copy.frames.size() == 2, "malformed recording rejected atomically")
	check(copy.load_recording("user://missing_core_record.json") == ERR_FILE_NOT_FOUND, "missing recording safe error")
	check(copy.save_recording("user://absent_input_dir/record.json") != OK, "record write error")
	DirAccess.remove_absolute(file)
	if failures == 0: print("PASS core input recording")
	quit(failures)
