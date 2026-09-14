extends Node
# FrontendInput — the semantic input service (Doc 03 §2/§3/§7/§8/§9).
#
# FOCUS is claimed ONLY by meaningful frontend input (§2):
#   ui_up / ui_down / ui_left / ui_right / ui_accept / ui_cancel
#   + intentional stick navigation above the hysteresis enter threshold
#   + an approved controller Start on a valid Ready state.
# Modifier-only keys, unrelated gameplay keys and tiny analog drift never
# claim FOCUS (and never navigate).
#
# Device events are decoded in _input() (observe only — the service NEVER
# consumes an event) and _unhandled_input() (the semantic action path, after
# GUI). It is deliberately NOT _unhandled_key_input(): that callback only
# receives InputEventKey, so controller A/B/Start can never be decoded
# there (§7). Controller A/B are decoded explicitly because the engine's
# default InputMap binds only keyboard keys and the D-pad/left stick.
#
# The service exposes the confirm press pose (§8): mouse-left, keyboard
# accept and controller A all reach confirm_pressed()/confirm_released(),
# which drive the one shared short press visual on the hand cursor.
#
# Scope (§9) is centralized here. set_scope() is the transition function the
# screens use for Pause / Stage-confirm / Results / Debug Start:
#   frontend: custom hand visible, semantic navigation active;
#   gameplay: hand hidden, carry/focus/hover cleared, semantic focus inactive.

signal nav_action(action: StringName)
signal confirm_pressed()
signal confirm_released()
signal cancel_pressed()
signal start_pressed()
signal scope_changed(scope: String)

const SCOPE_FRONTEND := "frontend"
const SCOPE_GAMEPLAY := "gameplay"

# §8: every confirm press records WHERE it came from. Screens that own a
# semantic action for a custom control must not double-fire it for a mouse
# click (the control's own mouse path owns that), and a keyboard/pad accept is
# the only source that activates the focused custom control.
const SOURCE_MOUSE := "mouse"
const SOURCE_KEYBOARD := "keyboard"
const SOURCE_PAD := "pad"

const AnalogNavGate := preload("res://scripts/frontend/analog_nav_gate.gd")

const NAV_ACTIONS := [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]
const SEMANTIC_ACTIONS := [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_cancel"]
const MODIFIER_KEYS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

var _scope := SCOPE_FRONTEND
var _start_approved := false
var _gate = AnalogNavGate.new()
var _stick := Vector2.ZERO
var _confirm_source := SOURCE_KEYBOARD
var _consume_confirm := Callable()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # Pause keeps Esc/Start reachable

# --- classification (shared with the cursor internals) --------------------
static func is_meaningful_frontend_input(event: InputEvent) -> bool:
	# §2: the ONLY keys/inputs that may claim FOCUS.
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return false
		if key.keycode == KEY_NONE and key.physical_keycode == KEY_NONE:
			return false
		if key.keycode in MODIFIER_KEYS or key.physical_keycode in MODIFIER_KEYS:
			return false                      # modifier-only key: never claims
		return matches_any_action(event, SEMANTIC_ACTIONS)
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if not button.pressed:
			return false
		if button.button_index == JOY_BUTTON_A or button.button_index == JOY_BUTTON_B:
			return true                       # pad accept / frontend cancel
		return matches_any_action(event, SEMANTIC_ACTIONS)   # D-pad directions
	return false

static func matches_any_action(event: InputEvent, actions: Array) -> bool:
	for action in actions:
		if InputMap.event_is_action(event, action):
			return true
	return false

static func is_pressed_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return false

# --- device events (never consumed) ---------------------------------------
func _input(event: InputEvent) -> void:
	if _scope != SCOPE_FRONTEND:
		# §9: gameplay owns input — no focus claim, no nav, no confirm pose and
		# the hand is hidden. Esc / controller Start still surface (they open
		# Pause); controller B is NOT cancel during gameplay (§11).
		_route_gameplay_escape(event)
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_emit_confirm(mouse.pressed, SOURCE_MOUSE)
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.echo:
			return
		if InputMap.event_is_action(event, "ui_accept"):
			_emit_confirm(key.pressed, SOURCE_KEYBOARD)
		elif key.pressed and InputMap.event_is_action(event, "ui_cancel"):
			cancel_pressed.emit()
		if key.pressed and is_meaningful_frontend_input(event):
			_claim_focus()
		return
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.button_index == JOY_BUTTON_A:
			_emit_confirm(button.pressed, SOURCE_PAD)
		elif button.pressed and button.button_index == JOY_BUTTON_B:
			cancel_pressed.emit()
		elif button.pressed and button.button_index == JOY_BUTTON_START:
			start_pressed.emit()
			if _start_approved:
				_claim_focus()                     # §2 approved shortcut
		if is_meaningful_frontend_input(event):
			_claim_focus()
		return
	if event is InputEventJoypadMotion:
		_handle_stick(event as InputEventJoypadMotion)
		return

func _route_gameplay_escape(event: InputEvent) -> void:
	# The one frontend event that survives gameplay scope: opening Pause.
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and InputMap.event_is_action(event, "ui_cancel"):
			cancel_pressed.emit()
	elif event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			if (event as InputEventJoypadButton).button_index == JOY_BUTTON_START:
				start_pressed.emit()

func _unhandled_input(event: InputEvent) -> void:
	# Semantic navigation AFTER GUI: a focused control that already consumed
	# the action keeps ownership; everything else is routed as a nav action.
	if _scope != SCOPE_FRONTEND:
		return
	if not is_pressed_event(event):
		return
	for action in NAV_ACTIONS:
		if InputMap.event_is_action(event, action):
			nav_action.emit(action)
			return

func _handle_stick(event: InputEventJoypadMotion) -> void:
	if event.axis == JOY_AXIS_LEFT_X:
		_stick.x = event.axis_value
	elif event.axis == JOY_AXIS_LEFT_Y:
		_stick.y = event.axis_value
	else:
		return
	var action := _gate.feed(_stick)
	if action != &"":
		_claim_focus()
		nav_action.emit(action)

func _claim_focus() -> void:
	var hand := _hand()
	if hand != null:
		hand.claim_focus()

func _emit_confirm(pressed: bool, source: String) -> void:
	var hand := _hand()
	if hand != null:
		hand.press_visual(pressed)                 # §8: one shared press pose
	if not pressed:
		confirm_released.emit()
		return
	_confirm_source = source
	confirm_pressed.emit()
	if _consume_confirm.is_valid() and bool(_consume_confirm.call(source)):
		# The active surface claimed this confirm BEFORE the GUI stage (Results
		# completes its reveal with the first confirm and must not also activate
		# the button under it). One input, one action.
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()

func confirm_source() -> String:
	# §8: which device produced the last confirm press ("mouse"/"keyboard"/"pad").
	# A screen that owns a semantic action for a CUSTOM control uses this to
	# avoid double-firing on a mouse click (the control's mouse path owns it).
	return _confirm_source

func set_confirm_consumer(consumer: Callable) -> void:
	# §7: the semantic confirm reaches the GUI after this service. A surface
	# that must answer the confirm itself (and swallow it) registers here.
	_consume_confirm = consumer

func clear_confirm_consumer(consumer: Callable = Callable()) -> void:
	if consumer.is_valid() and _consume_confirm != consumer:
		return
	_consume_confirm = Callable()

func focus_owner() -> Control:
	# The engine's current GUI focus owner — the ONE logical focus (§6). Read
	# only; the screens never set it behind the semantic path.
	var viewport := get_viewport()
	return viewport.gui_get_focus_owner() if viewport != null else null

# --- scope (§9) ------------------------------------------------------------
func set_scope(next_scope: String) -> void:
	var target := SCOPE_GAMEPLAY if next_scope == SCOPE_GAMEPLAY else SCOPE_FRONTEND
	if target == _scope:
		_apply_scope()
		return
	_scope = target
	_gate.reset()
	_stick = Vector2.ZERO
	_apply_scope()
	scope_changed.emit(_scope)

func scope() -> String:
	return _scope

func is_semantic_focus_active() -> bool:
	return _scope == SCOPE_FRONTEND

func set_controller_start_approved(approved: bool) -> void:
	_start_approved = approved

func is_controller_start_approved() -> bool:
	return _start_approved

func _apply_scope() -> void:
	var hand := _hand()
	if hand != null:
		hand.set_scope(_scope)

# --- modality mirrors (§3 keeps the two questions separate) ---------------
func is_mouse_mode() -> bool:
	var hand := _hand()
	return hand != null and hand.is_mouse_mode()

func is_pointer_hover_armed() -> bool:
	var hand := _hand()
	return hand != null and hand.is_pointer_hover_armed()

# --- analog navigation state ----------------------------------------------
func is_navigation_active() -> bool:
	return _gate.is_active()

func navigation_direction() -> Vector2:
	return _gate.direction()

func set_analog_thresholds(enter_value: float, release_value: float) -> void:
	_gate.set_thresholds(enter_value, release_value)

func _hand() -> Control:
	var cursor := get_node_or_null("/root/Cursor")
	if cursor == null or cursor.hand == null:
		return null
	return cursor.hand
