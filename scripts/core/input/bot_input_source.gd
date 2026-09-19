extends RefCounted
## Minimal intent-only pursuit dummy, not stage-aware recovery/combat AI.
const Frame = preload("res://scripts/core/input/input_frame.gd")
var approach_distance: float = 1.5
var jump_height: float = 1.0
var _previous: Dictionary = {}

func sample(tick: int, actor_position: Vector3, target_position: Vector3) -> Frame:
	var frame := Frame.new()
	frame.tick = tick
	frame.source_id = "bot"
	var difference := target_position - actor_position
	frame.axis.x = signf(difference.x) if absf(difference.x) > approach_distance else 0.0
	frame.held = {"jump": difference.y > jump_height,
		"attack": absf(difference.x) <= approach_distance, "special": false,
		"shield": false, "down": false}
	for action in frame.held:
		if frame.held[action] and not _previous.get(action, false):
			frame.pressed[action] = true
		if not frame.held[action] and _previous.get(action, false):
			frame.released[action] = true
	_previous = frame.held.duplicate()
	return frame

func reset() -> void:
	_previous.clear()
