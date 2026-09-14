extends RefCounted
# AnalogNavGate — reusable stick deadzone + hysteresis for semantic navigation
# (Doc 03 §2).
#
# Intentional navigation ENTERS around magnitude 0.50 and RELEASES around
# 0.30–0.35. The band between the thresholds is the hysteresis: a held stick
# never flickers in and out around one value, and tiny analog drift (a resting
# pad reports ±0.1–0.25) can never claim FOCUS or navigate.
#
# feed() is edge-based: it returns the ui_* action on a NEW navigation edge
# (activation or a fresh dominant axis) and &"" otherwise. Direction is
# snapped to the dominant axis so one stick produces clean cardinal ui_* moves.
#
# Tune with a physical controller; the defaults are the contract's values.

const ENTER_DEFAULT := 0.50
const RELEASE_DEFAULT := 0.32   # inside the contract's 0.30–0.35 band

var enter_threshold := ENTER_DEFAULT
var release_threshold := RELEASE_DEFAULT

var _active := false
var _direction := Vector2.ZERO

func feed(axis: Vector2) -> StringName:
	var mag := axis.length()
	if not _active:
		if mag < enter_threshold:
			return &""
		_active = true
		_direction = snap(axis)
		return action_for(_direction)
	if mag < release_threshold:
		_active = false
		_direction = Vector2.ZERO
		return &""
	var snapped := snap(axis)
	if snapped != _direction:
		_direction = snapped
		return action_for(snapped)
	return &""

func is_active() -> bool:
	return _active

func direction() -> Vector2:
	return _direction

func reset() -> void:
	_active = false
	_direction = Vector2.ZERO

func set_thresholds(enter_value: float, release_value: float) -> void:
	enter_threshold = enter_value
	release_threshold = release_value

static func snap(axis: Vector2) -> Vector2:
	if absf(axis.x) >= absf(axis.y):
		return Vector2(signf(axis.x), 0.0)
	return Vector2(0.0, signf(axis.y))

static func action_for(dir: Vector2) -> StringName:
	if dir.x > 0.0:
		return &"ui_right"
	if dir.x < 0.0:
		return &"ui_left"
	if dir.y > 0.0:
		return &"ui_down"
	return &"ui_up"
