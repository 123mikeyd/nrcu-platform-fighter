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
# Explicit Node-owner event feed. One edge per action per simulation sample.
var _event_capture := false
var _event_keys: Dictionary = {}
var _event_buttons: Dictionary = {}
var _event_stick := Vector2.ZERO
var _event_previous: Dictionary = {}
var _event_suppressed: Dictionary = {}
var _pending_pressed: Dictionary = {}
var _pending_released: Dictionary = {}
var _binding_identity: Array = []

func enable_event_capture() -> void:
	_event_capture = true
	reset()

func _identity() -> Array:
	return [device, slot, bindings.duplicate(), pad_bindings.duplicate(), tap_jump, deadzone]

func _check_binding_identity(event: InputEvent = null) -> void:
	if not _event_capture or _binding_identity == _identity(): return
	var prior_keys := _event_keys.duplicate()
	var prior_buttons := _event_buttons.duplicate()
	var prior_stick := _event_stick
	reset()
	# Native Input already includes this event. Seed suppression from the state
	# BEFORE it, then let feed_event apply it once under the new bindings.
	if event is InputEventKey and device < 0:
		_event_keys[event.physical_keycode] = prior_keys.get(event.physical_keycode, false)
	elif device >= 0:
		# Direct-feed synthetic pads have no native inventory. Keep their known
		# prior state; live pads still seed all other controls from native Input.
		if not Input.get_connected_joypads().has(device):
			_event_buttons = prior_buttons
			_event_stick = prior_stick
		if event is InputEventJoypadButton and event.device == device:
			_event_buttons[event.button_index] = prior_buttons.get(event.button_index, false)
		elif event is InputEventJoypadMotion and event.device == device:
			if event.axis == JOY_AXIS_LEFT_X: _event_stick.x = prior_stick.x
			elif event.axis == JOY_AXIS_LEFT_Y: _event_stick.y = prior_stick.y
	_event_suppressed.clear()
	var state := _normalized(_event_keys, _event_buttons, _event_stick)
	for action in ACTIONS:
		if state.raw[action]: _event_suppressed[action] = true

## Forward unhandled events; releases may also be forwarded before GUI handling.
## Never connect this RefCounted to a global event dispatcher.
func feed_event(event: InputEvent) -> void:
	if not _event_capture: return
	_check_binding_identity(event)
	if event is InputEventKey:
		if device >= 0 or event.echo: return
		# Observe even unbound controls so a later rebind can distinguish a
		# genuinely pre-held control from the current freshly dispatched down.
		_event_keys[event.physical_keycode] = event.pressed
		if not bindings.values().has(event.physical_keycode): return
	elif event is InputEventJoypadButton:
		if device < 0 or event.device != device: return
		_event_buttons[event.button_index] = event.pressed
		if not pad_bindings.values().has(event.button_index): return
	elif event is InputEventJoypadMotion:
		if device < 0 or event.device != device: return
		if event.axis == JOY_AXIS_LEFT_X: _event_stick.x = event.axis_value
		elif event.axis == JOY_AXIS_LEFT_Y: _event_stick.y = event.axis_value
		else: return
	else: return
	var state := _normalized(_event_keys, _event_buttons, _event_stick)
	for action in ACTIONS:
		if not state.raw[action]: _event_suppressed.erase(action)
		var active: bool = state.raw[action] and not _event_suppressed.has(action)
		if active and not _event_previous.get(action, false) and not _pending_pressed.has(action):
			_pending_pressed[action] = state.axis
		if not active and _event_previous.get(action, false): _pending_released[action] = true
		_event_previous[action] = active

func shutdown() -> void:
	reset()
	_event_capture = false
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)

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
	_check_binding_identity()
	var keys: Dictionary = {}
	var buttons: Dictionary = {}
	var stick := Vector2.ZERO
	var present: bool = device < 0 or Input.get_connected_joypads().has(device)
	if device < 0:
		for key in bindings.values():
			# GUI-consumed downs must not re-enter through held-state polling.
			keys[key] = Input.is_physical_key_pressed(key) and (not _event_capture or _event_keys.get(key, false))
	elif present:
		for button in pad_bindings.values():
			buttons[button] = Input.is_joy_button_pressed(device, button)
		stick = Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	return sample_snapshot(tick, keys, buttons, stick, present, true)

## Deterministic physical-state seam. Existing callers remain polling-only.
## Tests of the event feed can opt into draining with capture_events=true;
## live sample() does this automatically after the Node owner enables capture.
func sample_snapshot(tick: int, keys: Dictionary = {}, buttons: Dictionary = {},
		stick: Vector2 = Vector2.ZERO, present: bool = true, capture_events: bool = false) -> Frame:
	_check_binding_identity()
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
	var state := _normalized(keys, buttons, stick)
	frame.axis = state.axis
	var raw: Dictionary = state.raw
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
	if _event_capture and capture_events:
		frame.held = _event_previous.duplicate()
		frame.pressed.clear()
		for action in _pending_pressed: frame.pressed[action] = true
		frame.pressed_axis = _pending_pressed.duplicate()
		frame.released = _pending_released.duplicate()
		_pending_pressed.clear()
		_pending_released.clear()
	return frame

func _normalized(keys: Dictionary, buttons: Dictionary, stick: Vector2) -> Dictionary:
	var axis := Vector2.ZERO
	var raw: Dictionary = {}
	if device < 0:
		axis = Vector2(int(keys.get(bindings.right, false)) - int(keys.get(bindings.left, false)),
			int(keys.get(bindings.down, false)) - int(keys.get(bindings.up, false)))
		for action in ACTIONS:
			raw[action] = bool(keys.get(bindings.get(action, 0), false))
	else:
		var threshold: float = clampf(deadzone, 0.0, 0.99)
		axis = Vector2(0.0 if absf(stick.x) <= threshold else clampf(stick.x, -1, 1),
			0.0 if absf(stick.y) <= threshold else clampf(stick.y, -1, 1))
		for action in ACTIONS:
			raw[action] = bool(buttons.get(pad_bindings.get(action, -1), false))
	# Opposite vertical keys also neutralize directional down and tap jump.
	raw.down = axis.y > 0.5 or (device >= 0 and raw.down)
	raw.jump = raw.jump or (tap_jump and axis.y < -0.5)
	return {"axis": axis, "raw": raw}

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
	# Retain the identities we have observed, not their stale held values.
	# A still-held unbound control may become a binding after this boundary.
	var observed_keys := _event_keys.keys()
	var observed_buttons := _event_buttons.keys()
	_previous.clear()
	_suppressed.clear()
	_suppress_next = true
	_pending_pressed.clear()
	_pending_released.clear()
	_event_keys.clear()
	_event_buttons.clear()
	_event_stick = Vector2.ZERO
	_event_previous.clear()
	_event_suppressed.clear()
	_binding_identity = _identity()
	if not _event_capture: return
	if device < 0:
		for key in observed_keys + bindings.values(): _event_keys[key] = Input.is_physical_key_pressed(key)
	elif Input.get_connected_joypads().has(device):
		for button in observed_buttons + pad_bindings.values(): _event_buttons[button] = Input.is_joy_button_pressed(device, button)
		_event_stick = Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	var state := _normalized(_event_keys, _event_buttons, _event_stick)
	for action in ACTIONS:
		if state.raw[action]: _event_suppressed[action] = true
