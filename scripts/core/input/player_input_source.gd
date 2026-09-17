extends RefCounted
const Frame = preload("res://scripts/core/input/input_frame.gd")
const ACTIONS = ["jump", "attack", "special", "shield", "down"]
## Binding names: left/right/up/down/jump/attack/special/shield; physical keycodes.
## Setting slot selects defaults. Rebind afterwards. No global InputMap mutation.
var device: int = -1:
	set(value):
		if device != value:
			device = value
			reset()
var slot: int = 0:
	set(value):
		if slot != value:
			slot = value
			bindings = _default_bindings(value)
			reset()
var tap_jump: bool = false
## Axial deadzone: inside threshold is zero, outside retains raw magnitude.
var deadzone: float = 0.2
var connected: bool = true
var bindings: Dictionary = _default_bindings(0)
var pad_bindings: Dictionary = {"jump": JOY_BUTTON_A, "attack": JOY_BUTTON_X,
	"special": JOY_BUTTON_B, "shield": JOY_BUTTON_LEFT_SHOULDER}
var _previous: Dictionary = {}
var _suppressed: Dictionary = {}
var _suppress_next: bool = false

func _init() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _on_joy_connection_changed(changed_device: int, is_connected: bool) -> void:
	if changed_device == device:
		connected = is_connected
		reset()

static func _default_bindings(index: int) -> Dictionary:
	if index == 1:
		return {"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN,
			"jump": KEY_ENTER, "attack": KEY_K, "special": KEY_L, "shield": KEY_O}
	return {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S,
		"jump": KEY_SPACE, "attack": KEY_F, "special": KEY_G, "shield": KEY_E}

func sample(tick: int) -> Frame:
	var keys: Dictionary = {}
	var buttons: Dictionary = {}
	var stick := Vector2.ZERO
	var present: bool = device < 0 or Input.get_connected_joypads().has(device)
	if device < 0:
		for key in bindings.values():
			keys[key] = Input.is_physical_key_pressed(key)
	elif present:
		for button in pad_bindings.values():
			buttons[button] = Input.is_joy_button_pressed(device, button)
		stick = Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	return sample_snapshot(tick, keys, buttons, stick, present)

## Deterministic physical-state seam; uses exactly the live sample normalization.
func sample_snapshot(tick: int, keys: Dictionary = {}, buttons: Dictionary = {},
		stick: Vector2 = Vector2.ZERO, present: bool = true) -> Frame:
	var frame := Frame.new()
	frame.tick = tick
	frame.source_id = ("keyboard:%d" % slot) if device < 0 else ("pad:%d" % device)
	if device >= 0 and not present:
		connected = false
		reset()
		return frame
	if not connected:
		reset()
	connected = true
	var raw: Dictionary = {}
	if device < 0:
		frame.axis = Vector2(int(keys.get(bindings.right, false)) - int(keys.get(bindings.left, false)),
			int(keys.get(bindings.down, false)) - int(keys.get(bindings.up, false)))
		for action in ACTIONS:
			raw[action] = bool(keys.get(bindings.get(action, 0), false))
	else:
		var threshold: float = clampf(deadzone, 0.0, 0.99)
		frame.axis = Vector2(0.0 if absf(stick.x) <= threshold else clampf(stick.x, -1, 1),
			0.0 if absf(stick.y) <= threshold else clampf(stick.y, -1, 1))
		for action in ACTIONS:
			raw[action] = bool(buttons.get(pad_bindings.get(action, -1), false))
	# Opposite vertical keys also neutralize directional down and tap jump.
	raw.down = frame.axis.y > 0.5 or (device >= 0 and raw.down)
	raw.jump = raw.jump or (tap_jump and frame.axis.y < -0.5)
	for action in ACTIONS:
		if _suppress_next and raw[action]:
			_suppressed[action] = true
		if not raw[action]:
			_suppressed.erase(action)
		var active: bool = raw[action] and not _suppressed.has(action)
		frame.held[action] = active
		if active and not _previous.get(action, false):
			frame.pressed[action] = true
		if not active and _previous.get(action, false):
			frame.released[action] = true
	_previous = frame.held.duplicate()
	_suppress_next = false
	return frame

func save_profile(path: String = "user://core_input.cfg") -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	var section := "player_%d" % slot
	config.set_value(section, "bindings", bindings.duplicate(true))
	config.set_value(section, "pad_bindings", pad_bindings.duplicate(true))
	config.set_value(section, "deadzone", deadzone)
	config.set_value(section, "tap_jump", tap_jump)
	return config.save(path)

func load_profile(path: String = "user://core_input.cfg") -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return error
	var section := "player_%d" % slot
	if not config.has_section(section):
		return ERR_DOES_NOT_EXIST
	var new_keys = config.get_value(section, "bindings", _default_bindings(slot))
	var new_pad = config.get_value(section, "pad_bindings", pad_bindings)
	var new_deadzone = config.get_value(section, "deadzone", 0.2)
	var new_tap = config.get_value(section, "tap_jump", false)
	if not new_keys is Dictionary or not new_pad is Dictionary:
		return ERR_INVALID_DATA
	if not (new_deadzone is float or new_deadzone is int) or not new_tap is bool:
		return ERR_INVALID_DATA
	if not is_finite(float(new_deadzone)) or new_deadzone < 0 or new_deadzone >= 1:
		return ERR_INVALID_DATA
	for key in _default_bindings(slot):
		if not new_keys.get(key) is int or new_keys[key] <= 0:
			return ERR_INVALID_DATA
	for key in new_pad:
		if not key in ACTIONS or not new_pad[key] is int or new_pad[key] < 0 or new_pad[key] >= JOY_BUTTON_MAX:
			return ERR_INVALID_DATA
	bindings = new_keys.duplicate(true)
	pad_bindings = new_pad.duplicate(true)
	deadzone = float(new_deadzone)
	tap_jump = new_tap
	reset()
	return OK

## Call on pause, KO, rematch or reassignment; match owner must also clear buffer.
func reset() -> void:
	_previous.clear()
	_suppressed.clear()
	_suppress_next = true
