extends RefCounted
## A detached snapshot for one simulation tick. Positive Y means down.
var tick: int = 0
var axis: Vector2 = Vector2.ZERO
var held: Dictionary = {}
var pressed: Dictionary = {}
var released: Dictionary = {}
var source_id: String = ""
## Optional per-edge direction; axis remains the current movement snapshot.
var pressed_axis: Dictionary = {}

func to_dict() -> Dictionary:
	var data := {"tick": tick, "axis": [axis.x, axis.y], "held": held.duplicate(true),
		"pressed": pressed.duplicate(true), "released": released.duplicate(true), "source_id": source_id}
	if not pressed_axis.is_empty():
		data["pressed_axis"] = {}
		for action in pressed_axis:
			data.pressed_axis[action] = [pressed_axis[action].x, pressed_axis[action].y]
	return data

static func from_dict(data: Dictionary):
	var frame = load("res://scripts/core/input/input_frame.gd").new()
	frame.tick = int(data.get("tick", 0))
	var values = data.get("axis", [0.0, 0.0])
	if values is Array and values.size() == 2:
		frame.axis = Vector2(float(values[0]), float(values[1]))
	for field in ["held", "pressed", "released"]:
		var value = data.get(field, {})
		if value is Dictionary:
			frame.set(field, value.duplicate(true))
	frame.source_id = str(data.get("source_id", ""))
	for action in data.get("pressed_axis", {}):
		var value = data.pressed_axis[action]
		if value is Array and value.size() == 2:
			frame.pressed_axis[action] = Vector2(float(value[0]), float(value[1]))
	return frame
