extends SceneTree
# FrontendInput / cursor modality contract (Doc 03 §2/§3/§4/§5/§7/§8/§9).
#
# Contract covered here:
#   §2  FOCUS is claimed only by MEANINGFUL frontend input; modifier-only
#       keys, unrelated gameplay keys and tiny analog drift never claim it,
#       and intentional stick navigation uses deadzone + hysteresis;
#   §3  is_mouse_mode() and is_pointer_hover_armed() are separate answers —
#       a stationary pointer under a newly appearing control is not armed;
#   §4  MOUSE -> FOCUS starts from the CURRENT rendered hand hotspot (no
#       snap to the first target) with rebased velocity;
#   §5  the focus spring is frame-rate invariant (measured at 30/60/120 Hz);
#   §7  device events are decoded in _input()/_unhandled_input() — the pad
#       path works because a JoypadButton event actually reaches the service;
#   §8  mouse-left, keyboard accept and controller A produce the SAME short
#       press pose through confirm_pressed()/confirm_released();
#   §9  frontend/gameplay scope is centralized: gameplay hides the hand and
#       clears carry/focus/hover and semantic focus.
const Gate = preload("res://scripts/frontend/analog_nav_gate.gd")
const AnchorScene = preload("res://scripts/frontend/cursor_anchor.gd")

var failures := 0
var _nav: Array = []
var _presses := 0
var _releases := 0
var _cancels := 0
var _starts := 0
var service: Node = null
var hand: Control = null

func _initialize(): call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func frames(n: int) -> void:
	for i in n:
		await process_frame

# --- event helpers ---------------------------------------------------------
func key_event(keycode: Key, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	return event

func move_event(position: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	return event

func click_event(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event

func pad_button(index: JoyButton, pressed := true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	return event

func pad_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event

func route(event: InputEvent) -> void:
	# Production-shaped delivery: the hand cursor and the semantic service both
	# observe the device event (their _input callbacks), then the semantic
	# action path sees whatever the GUI did not consume.
	hand._input(event)
	service._input(event)
	service._unhandled_input(event)

func run():
	service = root.get_node_or_null("FrontendInput")
	check(service != null, "semantic input service autoload (FrontendInput) exists")
	var cursor = root.get_node_or_null("Cursor")
	check(cursor != null and cursor.hand != null, "cursor service reachable")
	if service == null or cursor == null or cursor.hand == null:
		quit(1)
		return
	hand = cursor.hand
	service.nav_action.connect(func(action: StringName) -> void: _nav.append(str(action)))
	service.confirm_pressed.connect(func() -> void: _presses += 1)
	service.confirm_released.connect(func() -> void: _releases += 1)
	service.cancel_pressed.connect(func() -> void: _cancels += 1)
	service.start_pressed.connect(func() -> void: _starts += 1)

	var host := Control.new()
	host.name = "InputContractHost"
	root.add_child(host)
	var near := AnchorScene.new()
	near.place_at(Vector2(160.0, 120.0))
	host.add_child(near)
	var far := AnchorScene.new()
	far.place_at(Vector2(660.0, 520.0))
	host.add_child(far)
	var tile := Control.new()
	tile.position = Vector2(600.0, 340.0)
	tile.size = Vector2(120.0, 40.0)
	host.add_child(tile)
	await frames(1)

	hand.drop_targets()
	hand.begin_screen("contract")
	hand.set_mode(0)   # HandCursor.Mode.MOUSE
	service.set_scope("frontend")
	service.set_controller_start_approved(false)

	# --- §2: meaningful modality claims ------------------------------------
	var P := Vector2(500.0, 300.0)
	route(move_event(P, Vector2(12.0, 0.0)))
	check(hand.is_mouse_mode(), "pointer motion claims MOUSE mode")
	check(hand.is_pointer_hover_armed(), "pointer motion arms hover")

	route(key_event(KEY_SHIFT))
	check(hand.is_mouse_mode(), "a modifier-only key never claims FOCUS (mode %d)" % hand.mode)

	route(key_event(KEY_F))
	check(hand.is_mouse_mode(), "an unrelated gameplay key never claims FOCUS")

	route(pad_axis(JOY_AXIS_LEFT_X, 0.2))
	check(hand.is_mouse_mode(), "tiny analog drift never claims FOCUS")
	check(not service.is_navigation_active(), "tiny analog drift never activates navigation")
	check(_nav.is_empty(), "no nav action was routed by meaningless input")

	route(key_event(KEY_DOWN))
	check(hand.mode == 1, "ui_down claims FOCUS")
	check(_nav == ["ui_down"], "ui_down is routed as a semantic nav action (got %s)" % str(_nav))

	route(pad_axis(JOY_AXIS_LEFT_X, 0.6))
	check(hand.mode == 1, "intentional stick navigation claims FOCUS")
	check(service.is_navigation_active(), "the hysteresis gate reports active navigation")
	check(str(_nav.back()) == "ui_right", "the stick routes ui_right (got %s)" % str(_nav.back()))
	route(pad_axis(JOY_AXIS_LEFT_X, 0.34))
	check(service.is_navigation_active(), "0.34 stays latched above the 0.32 release threshold")
	route(pad_axis(JOY_AXIS_LEFT_X, 0.25))
	check(not service.is_navigation_active(), "0.25 releases navigation")
	var nav_held := _nav.size()
	route(pad_axis(JOY_AXIS_LEFT_X, 0.45))
	check(not service.is_navigation_active(), "hysteresis: 0.45 from rest stays inactive (0.50 to enter)")
	check(_nav.size() == nav_held, "hysteresis: nothing is routed between the thresholds")
	route(pad_axis(JOY_AXIS_LEFT_X, 0.0))

	route(click_event(true))
	check(hand.is_mouse_mode(), "a mouse click claims MOUSE mode")
	check(hand.is_pointer_hover_armed(), "a mouse click arms hover")
	route(click_event(false))

	# --- §3: modality and hover arming are separate questions --------------
	hand.drop_targets()
	hand.add_target(tile)
	hand._input(move_event(Vector2(650.0, 350.0), Vector2(12.0, 0.0)))
	hand.begin_screen("stationary")   # fresh screen: hover disarmed, pointer stays
	await frames(2)
	check(hand.is_mouse_mode(), "screen entry keeps MOUSE mode")
	check(not hand.is_pointer_hover_armed(), "screen entry disarms pointer hover")
	check(service.is_mouse_mode() and not service.is_pointer_hover_armed(),
		"the service answers both questions separately (mouse=True armed=False)")
	check(hand.hovered == null, "a stationary pointer under a newly appearing control is not armed")
	hand._input(move_event(Vector2(655.0, 352.0), Vector2(6.0, 0.0)))
	await frames(2)
	check(hand.is_pointer_hover_armed() and hand.hovered == tile,
		"genuine pointer movement arms hover on the new control")
	check(service.is_pointer_hover_armed(), "the service mirrors the hover-arming state")

	# --- §4: MOUSE -> FOCUS starts from the current rendered hotspot --------
	hand.drop_targets()
	hand.begin_screen("spring")
	hand.set_mode(0)
	route(move_event(P, Vector2(14.0, 0.0)))
	await frames(1)
	check(hand.hotspot.distance_to(P) < 0.001, "the mouse hand renders exactly at the pointer")
	var start: Vector2 = hand.hotspot
	var target_pos: Vector2 = far.get_global_rect().position
	var travel := start.distance_to(target_pos)
	hand.set_process(false)   # drive the spring step-by-step from here
	hand.set_focus_target(far)
	check(hand.mode == 1, "an authored anchor switches the hand to FOCUS")
	check(hand.hotspot.distance_to(start) < 0.001,
		"MOUSE -> FOCUS keeps the current rendered position (no snap to the target)")
	check(hand._focus_vel == Vector2.ZERO, "MOUSE -> FOCUS rebases the focus velocity")
	hand.step_focus_spring(1.0 / 60.0)
	var moved: float = hand.hotspot.distance_to(start)
	check(moved > 0.0 and moved < travel * 0.15,
		"the first spring step is a bounded move, not a jump (%.1f px of %.1f)" % [moved, travel])
	for i in 90:
		hand.step_focus_spring(1.0 / 60.0)
	check(hand.hotspot.distance_to(target_pos) < 0.5, "the focus hand settles at the authored anchor")

	# --- §5: frame-rate invariance at 30/60/120 Hz -------------------------
	var rates := [30.0, 60.0, 120.0]
	var t90: Array = []
	var settle: Array = []
	for rate in rates:
		hand.set_mode(0)   # rewind to MOUSE at the same pointer position
		hand.set_focus_target(far)
		var dt: float = 1.0 / float(rate)
		var span: float = hand.hotspot.distance_to(target_pos)
		var prev_t := 0.0
		var prev_f := 0.0
		var found90 := -1.0
		var found99 := -1.0
		for i in int(float(rate) * 2.0):
			hand.step_focus_spring(dt)
			var t: float = float(i + 1) * dt
			var progress: float = 1.0 - float(hand.hotspot.distance_to(target_pos)) / span
			if found90 < 0.0 and progress >= 0.90:
				found90 = prev_t + (0.90 - prev_f) / maxf(progress - prev_f, 0.0000001) * dt
			if found99 < 0.0 and progress >= 0.99:
				found99 = prev_t + (0.99 - prev_f) / maxf(progress - prev_f, 0.0000001) * dt
			prev_t = t
			prev_f = progress
		t90.append(found90)
		settle.append(found99)
		print("SPRING %d Hz: 90%% arrival %.1f ms, visual settle %.1f ms" % [
			int(rate), found90 * 1000.0, found99 * 1000.0])
	for i in rates.size():
		check(t90[i] >= 0.115 and t90[i] <= 0.160,
			"90%% arrival at %d Hz lands in the 120-150 ms window (%.1f ms)" % [int(rates[i]), t90[i] * 1000.0])
		check(settle[i] >= 0.175 and settle[i] <= 0.235,
			"visual settle at %d Hz lands in the 180-220 ms window (%.1f ms)" % [int(rates[i]), settle[i] * 1000.0])
	check(maxf(t90[0], maxf(t90[1], t90[2])) - minf(t90[0], minf(t90[1], t90[2])) <= 0.02,
		"90%% arrival matches across 30/60/120 Hz within 20 ms")
	check(maxf(settle[0], maxf(settle[1], settle[2])) - minf(settle[0], minf(settle[1], settle[2])) <= 0.03,
		"visual settle matches across 30/60/120 Hz within 30 ms")

	# --- §8: confirm press pose from all three sources ---------------------
	hand.set_mode(0)
	var presses0 := _presses
	var releases0 := _releases
	route(click_event(true))
	check(_presses == presses0 + 1, "mouse-left press reaches confirm_pressed()")
	check(hand.is_pressing() and hand._press_held, "mouse-left shows the shared press pose")
	route(click_event(false))
	check(_releases == releases0 + 1 and not hand._press_held, "mouse-left release reaches confirm_released()")
	route(key_event(KEY_ENTER, true))
	check(_presses == presses0 + 2, "keyboard accept press reaches confirm_pressed()")
	check(hand.is_pressing() and hand._press_held, "keyboard accept shows the same press pose")
	route(key_event(KEY_ENTER, false))
	check(_releases == releases0 + 2 and not hand._press_held, "keyboard accept release reaches confirm_released()")
	check(hand._press > 0.0, "the release keeps the short press visual (not an instant cut)")
	route(pad_button(JOY_BUTTON_A, true))
	check(_presses == presses0 + 3, "controller A press reaches confirm_pressed() through the pad event path")
	check(hand.is_pressing() and hand._press_held, "controller A shows the same press pose")
	route(pad_button(JOY_BUTTON_A, false))
	check(_releases == releases0 + 3 and not hand._press_held, "controller A release reaches confirm_released()")

	# --- §2: controller Start is approved only on a valid Ready ------------
	hand.set_mode(0)
	var starts0 := _starts
	route(pad_button(JOY_BUTTON_START, true))
	check(_starts == starts0 + 1, "controller Start is routed through the pad event path")
	check(hand.is_mouse_mode(), "Start does not claim FOCUS while Ready is not valid")
	service.set_controller_start_approved(true)
	route(pad_button(JOY_BUTTON_START, false))
	route(pad_button(JOY_BUTTON_START, true))
	check(_starts == starts0 + 2, "an approved Start keeps routing the semantic event")
	check(hand.mode == 1, "approved controller Start claims FOCUS for the shortcut")

	# --- §9: frontend <-> gameplay scope -----------------------------------
	hand.set_process(true)
	var box := Control.new()
	box.position = Vector2(620.0, 340.0)
	box.size = Vector2(120.0, 40.0)
	host.add_child(box)
	await frames(1)
	hand.drop_targets()
	hand.add_target(box)
	hand._input(move_event(Vector2(650.0, 350.0), Vector2(9.0, 0.0)))
	await frames(2)
	check(hand.hovered == box, "precondition: hover is owned before the scope change")
	hand.set_carry(box)
	check(hand.is_carrying(), "precondition: the hand carries a token")
	service.set_scope("gameplay")
	check(service.scope() == "gameplay", "the service exposes the active scope")
	check(not service.is_semantic_focus_active(), "semantic focus is inactive in gameplay scope")
	check(not hand.visible, "gameplay hides the custom hand")
	check(not hand.is_carrying() and hand.carried_token() == null, "gameplay clears the carry")
	check(hand.hovered == null, "gameplay clears hover")
	check(hand._focus_anchor == null, "gameplay clears the focus target")
	check(hand.mode == 0, "gameplay drops semantic focus out of FOCUS mode")
	var nav_before := _nav.size()
	route(key_event(KEY_DOWN))
	check(hand.mode == 0, "ui_down does not claim FOCUS while gameplay owns input")
	check(_nav.size() == nav_before, "no semantic nav is routed in gameplay scope")
	# §9/§11: Pause must still be openable from gameplay; controller B is not.
	var cancels_before := _cancels
	var starts_before := _starts
	route(key_event(KEY_ESCAPE))
	check(_cancels == cancels_before + 1, "Esc still routes in gameplay scope (it opens Pause)")
	route(pad_button(JOY_BUTTON_START, true))
	route(pad_button(JOY_BUTTON_START, false))
	check(_starts == starts_before + 1, "controller Start still routes in gameplay scope (it opens Pause)")
	route(pad_button(JOY_BUTTON_B, true))
	route(pad_button(JOY_BUTTON_B, false))
	check(_cancels == cancels_before + 1, "controller B is not cancel during gameplay")
	check(not hand.visible and hand.mode == 0, "gameplay routing leaves the hand out of it")
	service.set_scope("frontend")
	check(hand.visible, "frontend restores the custom hand")
	check(service.is_semantic_focus_active(), "frontend re-enables semantic focus")
	route(key_event(KEY_DOWN))
	check(hand.mode == 1, "frontend semantic focus works again after the transition")

	# --- §7: the real tree-routed event path (no direct calls) -------------
	hand.begin_screen("routed")
	hand.set_mode(0)
	hand._input(move_event(Vector2(300.0, 200.0), Vector2(9.0, 0.0)))
	await frames(1)
	hand.drop_targets()
	var nav_routed := _nav.size()
	Input.parse_input_event(key_event(KEY_DOWN))
	await frames(3)
	check(hand.mode == 1, "a tree-routed ui_down claims FOCUS through the real event path")
	check(_nav.size() == nav_routed + 1 and str(_nav.back()) == "ui_down",
		"the service routes the tree-routed nav action")

	if failures > 0:
		print("FAILURES: %d" % failures)
		quit(1)
		return
	print("PASS: frontend input contract (semantic modality, hysteresis, hover arming, frame-invariant spring, confirm pose, scope)")
	quit(0)
