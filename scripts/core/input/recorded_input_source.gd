extends RefCounted
const Frame = preload("res://scripts/core/input/input_frame.gd")
var frames: Array = []
var _cursor: int = 0

func record(frame: Frame) -> void:
	frames.append(frame.to_dict())

func rewind() -> void:
	_cursor = 0

func sample(tick: int) -> Frame:
	var frame := Frame.new()
	if _cursor < frames.size():
		frame = Frame.from_dict(frames[_cursor])
		_cursor += 1
	frame.tick = tick
	return frame

func save_recording(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": 1, "frames": frames}))
	var error := file.get_error()
	file.close()
	return error

func load_recording(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK:
		return ERR_INVALID_DATA
	var data = parser.data
	if not data is Dictionary or data.get("version") != 1 or not data.get("frames") is Array:
		return ERR_INVALID_DATA
	var loaded: Array = []
	for entry in data.frames:
		if not _valid_frame(entry):
			return ERR_INVALID_DATA
		loaded.append(Frame.from_dict(entry).to_dict())
	frames = loaded
	rewind()
	return OK

static func _valid_frame(entry: Variant) -> bool:
	if not entry is Dictionary or not entry.get("axis") is Array or entry.axis.size() != 2:
		return false
	for value in entry.axis:
		if not (value is float or value is int) or not is_finite(float(value)) or absf(float(value)) > 1:
			return false
	if not (entry.get("tick") is float or entry.get("tick") is int) or not entry.get("source_id") is String:
		return false
	for field in ["held", "pressed", "released"]:
		if not entry.get(field) is Dictionary:
			return false
		for action in entry[field]:
			if not action in ["jump", "attack", "special", "shield", "down"] or not entry[field][action] is bool:
				return false
	return true
