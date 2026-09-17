extends RefCounted
const Frame = preload("res://scripts/core/input/input_frame.gd")
var window_ticks: int = 6
var _pending: Array[Dictionary] = []
var _sequence: int = 0
var _last_event_tick: Dictionary = {}
var _last_aged_tick: int = -9223372036854775807

func advance(frame: Frame, hitstop: bool = false) -> void:
	if not hitstop and frame.tick != _last_aged_tick:
		_last_aged_tick = frame.tick
		for request in _pending:
			request.age += 1
		_pending = _pending.filter(func(request): return request.age < window_ticks)
	for action in ["jump", "attack", "special", "shield", "down"]:
		if not frame.pressed.get(action, false):
			continue
		var identity: String = frame.source_id + ":" + action
		if frame.tick <= int(_last_event_tick.get(identity, -9223372036854775807)):
			continue
		_last_event_tick[identity] = frame.tick
		_sequence += 1
		_pending.append({"action": action, "sequence": _sequence, "tick": frame.tick,
			"axis": frame.axis, "age": 0})

func peek(action: String) -> Dictionary:
	for request in _pending:
		if request.action == action:
			return request.duplicate(true)
	return {}

func consume(action: String) -> Dictionary:
	for index in range(_pending.size()):
		if _pending[index].action == action:
			var request := _pending[index].duplicate(true)
			_pending.remove_at(index)
			return request
	return {}

func clear() -> void:
	_pending.clear()
	_last_event_tick.clear()

func debug_pending() -> Array:
	return _pending.duplicate(true)
