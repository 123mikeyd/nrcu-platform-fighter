extends Control
# NRCU hand cursor — one persistent service, two presentation modes.
#
# MOUSE MODE (§1): the interactive hotspot IS the exact physical mouse
# position. Nothing springs or eases the authoritative hotspot; hit testing,
# hover geometry and clicks all use it directly. The pleasant softness lives
# in the VISUAL ARTICULATION around the fingertip: filtered-velocity lean,
# tiny spring squash and the click press frame.
#
# FOCUS MODE (§2/§4/§5): controller/keyboard focus places the same hand at the
# focused component's authored CursorAnchor. The physical mouse is never
# moved. On MOUSE -> FOCUS the spring starts from the CURRENT rendered hand hot
# spot with rebased velocity — the hand never snaps to the first target. The
# motion is a frame-rate-invariant critically damped second-order response
# (closed form, FOCUS_OMEGA), identical at 30/60/120+ Hz.
#
# Modality (§2) follows meaningful frontend input only: ui_up/down/left/right,
# ui_accept, ui_cancel, intentional stick navigation above the hysteresis
# threshold and an approved controller Start. Modifier-only keys, gameplay
# keys and analog drift never claim FOCUS. Classification is shared with the
# FrontendInput semantic service — events are never decoded in
# _unhandled_key_input(), which cannot see JoypadButton events (§7).
# On FOCUS -> MOUSE the hand reacquires the pointer immediately (the user just
# asked for pointer control) with a short pose settle, never a slow fly.
#
# Pose semantics: point = ordinary navigation; press = click/confirm; carry =
# grab pose + a separate PlayerTokenView owned by the screen and attached into
# this layer (`set_carry`). The baked hand_carry sprite is retired from
# production use.
#
# Hover arming (§3): a stationary pointer does not drive semantic hover on a
# newly entered screen or under a newly appearing control until genuine mouse
# motion or a click. is_mouse_mode() and is_pointer_hover_armed() are separate
# questions — one method never answers both.
#
# Scope (§9): FRONTEND shows the hand and allows semantic focus; GAMEPLAY hides
# it and clears carry/hover/focus. FrontendInput.set_scope() drives this.


signal hover_changed(target: Control)
signal modality_changed(mouse_mode: bool)

enum Mode { MOUSE, FOCUS }
enum Visual { REGULAR, CARRY }

# §5: frame-rate-invariant critically damped response, closed form.
# omega = 31.5 rad/s puts the acceptance windows at ~124–126 ms for 90%
# arrival and ~211–214 ms for visual settle — identical at 30/60/120 Hz.
const FOCUS_OMEGA := 31.5
const LEAN_SCALE := 0.0013
const LEAN_MAX := 0.30
const PRESS_SECONDS := 0.12
const MOTION_EPSILON := 0.4
const SETTLE_SECONDS := 0.14   # pose settle after modality reacquisition

# §9 scopes (mirrored by FrontendInput, which is the transition authority).
const SCOPE_FRONTEND := "frontend"
const SCOPE_GAMEPLAY := "gameplay"

# §2 classification is shared with the semantic input service so the hand and
# the service can never disagree about what is meaningful input.
const Semantics = preload("res://scripts/frontend/frontend_input.gd")
const AnalogNavGate = preload("res://scripts/frontend/analog_nav_gate.gd")


const HAND_SCALE := 0.33
const TIP_POINT := Vector2(15.5, 1.0)
const TIP_CARRY := Vector2(67.5, 32.0)   # approved baked carry pose's anchor
const TIP_GRAB := Vector2(50.0, 1.0)
const TIP_PRESS := Vector2(49.0, 22.0)
# Where a carried token sits relative to the fingertip (texture space), so it
# reads as held between the fingers of the grab pose.
# Carried token CENTER relative to the hotspot. Derived from the retired baked
# carry pose ((CHIP_TEX_POS 35.5,34.0 - TIP_CARRY 67.5,32.0) * 0.33) and then
# The token slot renders BELOW the hand, so the fingers overlap the token
# exactly like the artist's reference composition (fingers in front of the
# coin).
const CARRY_CENTER := Vector2(-10.6, 0.7)

var targets: Array[Control] = []
var hovered: Control = null
var mode: Mode = Mode.MOUSE
var visual: Visual = Visual.REGULAR
var scope := SCOPE_FRONTEND
var hotspot := Vector2.ZERO          # authoritative interaction point
var _mouse := Vector2.ZERO
var _hover_armed := false

var _focus_anchor: Control = null
var _focus_pos := Vector2.ZERO
var _focus_vel := Vector2.ZERO
var _has_focus_pos := false

var _stick := Vector2.ZERO
var _nav_gate = AnalogNavGate.new()

var _vel_visual := Vector2.ZERO      # filtered, for lean/squash only
var _lean := 0.0
var _press := 0.0
var _press_held := false
var _settle := 0.0
var _carrying_token: Control = null
var _carry_offset := Vector2.ZERO

var _tex_point: Texture2D
var _tex_grab: Texture2D
var _tex_press: Texture2D
var _tex_carry: Texture2D
var _hand: Control
var _token_slot: Control

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    z_index = 0
    _hand = Control.new()
    _hand.name = "HandVisual"
    _hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hand.draw.connect(_draw_hand)
    _token_slot = Control.new()
    _token_slot.name = "CarriedToken"
    _token_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_token_slot)   # below the hand: fingers overlap the carried token
    add_child(_hand)
    _tex_point = load("res://assets/ui/hand_point.png")
    _tex_grab = load("res://assets/ui/hand_grab.png")
    _tex_press = load("res://assets/ui/hand_press.png")
    # The carry pose is the APPROVED BAKED sprite (hand + coin as one image,
    # pixel-identical to the artist's Krita reference). Layering the coin under
    # the hand was tried and abandoned together with William — the bake is the
    # robust result and must not be replaced by a runtime composite.
    _tex_carry = load("res://assets/ui/hand_carry.png")
    var vp := get_viewport()
    if vp != null:
        _mouse = vp.get_mouse_position()
        _focus_pos = _mouse
    hotspot = _mouse

# --- semantic screen lifecycle ------------------------------------------
func begin_screen(_screen_id: String) -> void:
    # Clears stale hover ownership. Never touches physical pointer position,
    # never forces modality, never snaps the rendered hand.
    clear_hover()
    _hover_armed = false
    if mode == Mode.FOCUS and _focus_anchor == null:
        # Focus continues across the transition only if the new screen sets a
        # focus target (authored default selection).
        pass
    _focus_anchor = null
    _has_focus_pos = false
    queue_redraw()

func clear_hover() -> void:
    if hovered != null:
        hovered = null
        hover_changed.emit(null)

func set_visual_mode(m: Visual) -> void:
    if visual == m:
        return
    visual = m
    queue_redraw()

func set_focus_target(anchor: Control) -> void:
    _focus_anchor = anchor
    if anchor != null and is_instance_valid(anchor):
        _has_focus_pos = true
        if mode != Mode.FOCUS:
            # §4: switching modality starts the spring from the CURRENT
            # rendered hotspot — the target is never snapped to.
            set_mode(Mode.FOCUS)
    queue_redraw()

func set_mode(m: Mode) -> void:
    if mode == m:
        return
    mode = m
    if m == Mode.MOUSE:
        hotspot = _mouse            # immediate reacquisition, no fly
        _hover_armed = false        # re-arm on genuine motion (device just switched)
        _settle = SETTLE_SECONDS
    else:
        # §4: focus_visual_position = current rendered hand hotspot;
        # focus_velocity rebased to zero (the pointer's visual velocity is not
        # focus intent). No snap to the first target.
        _focus_pos = hotspot
        _focus_vel = Vector2.ZERO
    modality_changed.emit(m == Mode.MOUSE)
    queue_redraw()

func claim_focus() -> void:
    # §2: the semantic service claims FOCUS through this method so the hand
    # decides HOW the transition happens (spring from the current hotspot).
    set_mode(Mode.FOCUS)

func is_mouse_mode() -> bool:
    # §3: modality question, answered alone.
    return mode == Mode.MOUSE

func is_pointer_hover_armed() -> bool:
    # §3: hover-arming question, answered alone (genuine pointer movement or a
    # click on the current screen). A stationary pointer under a newly
    # appearing control is NOT armed.
    return _hover_armed

func is_mouse_active() -> bool:
    # Compatibility combination for callers that genuinely need both facts
    # ("is the mouse both authoritative AND armed"). New code asks the two
    # separate questions above instead.
    return is_mouse_mode() and _hover_armed

# --- scope (§9) ------------------------------------------------------------
func set_scope(next_scope: String) -> void:
    scope = next_scope if next_scope == SCOPE_GAMEPLAY else SCOPE_FRONTEND
    _stick = Vector2.ZERO
    _nav_gate.reset()
    if scope == SCOPE_GAMEPLAY:
        # Gameplay owns input: the custom hand disappears and every frontend
        # interaction state it carried is cleared.
        clear_carry()
        clear_hover()
        _focus_anchor = null
        _focus_vel = Vector2.ZERO
        _hover_armed = false
        _press_held = false
        if mode != Mode.MOUSE:
            set_mode(Mode.MOUSE)
        visible = false
    else:
        visible = true
    queue_redraw()

# --- carry (token lives in the screen; the cursor only carries it) -------
func set_carry(token: Control = null) -> void:
    # `token` is the screen-owned PlayerTokenView. A legacy caller may pass
    # nothing (carry pose only); the production CSS always passes its token.
    _carrying_token = token
    if token != null:
        if token.get_parent() != _token_slot:
            token.reparent(_token_slot)
        var ts := token.size
        if ts.x <= 0.0:
            ts = Vector2(26.0, 26.0)
        token.position = CARRY_CENTER - ts * 0.5
        # The baked carry sprite carries the coin in its art; the particle
        # token object keeps its state but does not draw on top of the hand.
        token.visible = _tex_carry == null
        token.visible = true
    set_visual_mode(Visual.CARRY)

func clear_carry() -> void:
    _carrying_token = null
    set_visual_mode(Visual.REGULAR)
    for child in _token_slot.get_children():
        child.visible = false

func is_carrying() -> bool:
    return _carrying_token != null

func carried_token() -> Control:
    return _carrying_token

# --- hover targets -------------------------------------------------------
func add_target(target: Control) -> void:
    if target == null or targets.has(target):
        return
    targets.append(target)

func drop_targets() -> void:
    targets.clear()
    clear_hover()

func active_target() -> Control:
    if hovered != null and is_instance_valid(hovered) and hovered.is_visible_in_tree():
        return hovered
    return null

# --- input ---------------------------------------------------------------
func _input(event: InputEvent) -> void:
    if scope != SCOPE_FRONTEND:
        return   # §9: gameplay owns input; semantic focus is inactive
    if event is InputEventMouseMotion:
        _mouse = event.position
        if event.relative.length() >= MOTION_EPSILON:
            if mode != Mode.MOUSE:
                set_mode(Mode.MOUSE)
            _hover_armed = true  # the reacquiring motion itself arms hover
    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            press_visual(event.pressed)   # §8: same press pose as key/pad
        if mode != Mode.MOUSE:
            set_mode(Mode.MOUSE)
        _hover_armed = true
    elif event is InputEventJoypadMotion:
        # §2: analog judged by the shared hysteresis gate — tiny drift never
        # claims FOCUS, intentional navigation does.
        _feed_stick(event)
    elif Semantics.is_meaningful_frontend_input(event):
        # §2: ONLY ui_up/down/left/right, ui_accept and ui_cancel (plus their
        # mapped pad forms) claim FOCUS. Modifier-only keys and gameplay keys
        # fall through here and change nothing. Controller Start is claimed by
        # the semantic service, gated on a valid Ready state.
        set_mode(Mode.FOCUS)

func _feed_stick(event: InputEventJoypadMotion) -> void:
    if event.axis == JOY_AXIS_LEFT_X:
        _stick.x = event.axis_value
    elif event.axis == JOY_AXIS_LEFT_Y:
        _stick.y = event.axis_value
    else:
        return
    if _nav_gate.feed(_stick) != &"":
        set_mode(Mode.FOCUS)

func press_visual(pressed: bool) -> void:
    # §8: mouse-left, keyboard accept and controller A all reach this one
    # short press pose (never four different feedbacks).
    if pressed:
        _press_held = true
        _press = PRESS_SECONDS
    else:
        _press_held = false

func _process(delta: float) -> void:
    if _press > 0.0:
        _press = maxf(_press - delta, 0.0)
    if _settle > 0.0:
        _settle = maxf(_settle - delta, 0.0)
    if scope == SCOPE_GAMEPLAY:
        _vel_visual = _vel_visual.lerp(Vector2.ZERO, minf(8.0 * delta, 1.0))
        _apply_hand_position()
        return
    if mode == Mode.MOUSE:
        hotspot = _mouse
        # Hover only after genuine pointer input on this screen.
        var new_hover: Control = null
        if _hover_armed:
            var new_area := INF
            for target in targets:
                if not is_instance_valid(target) or not target.is_visible_in_tree():
                    continue
                var rect := target.get_global_rect()
                if rect.has_point(_mouse) and rect.get_area() < new_area:
                    new_hover = target
                    new_area = rect.get_area()
        if new_hover != hovered:
            hovered = new_hover
            hover_changed.emit(hovered)
        _vel_visual = _vel_visual.lerp(Vector2.ZERO, minf(8.0 * delta, 1.0))
    else:
        step_focus_spring(delta)
    var lean_goal := clampf(_vel_visual.x * LEAN_SCALE, -LEAN_MAX, LEAN_MAX)
    _lean = lerpf(_lean, lean_goal, minf(10.0 * delta, 1.0))
    _apply_hand_position()

func step_focus_spring(delta: float) -> void:
    # §5: frame-rate-invariant critically damped second-order response, solved
    # in closed form for the whole step. The old per-frame impulse/damp
    # integrator collapsed to a standstill at 30 Hz (1 - DAMP * delta <= 0);
    # the analytic step is exact at 30/60/120+ Hz and under any frame stall.
    if _focus_anchor == null or not is_instance_valid(_focus_anchor):
        return
    var target: Vector2 = _focus_anchor.get_global_rect().position
    _has_focus_pos = true
    var offset := _focus_pos - target
    var vel_term := _focus_vel + FOCUS_OMEGA * offset
    var decay := exp(-FOCUS_OMEGA * delta)
    _focus_pos = target + (offset + vel_term * delta) * decay
    _focus_vel = (vel_term - FOCUS_OMEGA * (offset + vel_term * delta)) * decay
    hotspot = _focus_pos
    _vel_visual = _focus_vel

func _apply_hand_position() -> void:
    _hand.position = hotspot
    _hand.queue_redraw()
    _token_slot.position = hotspot
    queue_redraw()

# --- drawing -------------------------------------------------------------
func _tex_ready() -> bool:
    return _tex_point != null and _tex_grab != null

func is_pressing() -> bool:
    return _press_held or _press > 0.0

func active_texture() -> Texture2D:
    if is_pressing() and _tex_press != null:
        return _tex_press
    if visual == Visual.CARRY:
        if _tex_carry != null:
            return _tex_carry
        if _tex_grab != null:
            return _tex_grab
    return _tex_point

func active_tip() -> Vector2:
    if is_pressing():
        return TIP_PRESS
    if visual == Visual.CARRY:
        return TIP_CARRY if _tex_carry != null else TIP_GRAB
    return TIP_POINT

func _draw_hand() -> void:
    if not _tex_ready():
        return
    var squash := 1.0
    if is_pressing():
        squash = 0.92
    elif _settle > 0.0:
        squash = 1.0 - 0.10 * (_settle / SETTLE_SECONDS)
    _hand.draw_set_transform(Vector2.ZERO, _lean, Vector2(HAND_SCALE, HAND_SCALE * squash))
    _hand.draw_texture(active_texture(), -active_tip())

# --- deprecated compatibility shims (removed after screen migration) ------
func reset_for_screen() -> void:
    begin_screen("")

func release_carry() -> Vector2:
    var at := hotspot
    clear_carry()
    return at

func chip_world_position() -> Vector2:
    return hotspot + CARRY_CENTER

func attract_to(_target: Control) -> void:
    pass

var _pos: Vector2:
    get:
        return hotspot

var attract_enabled := true

var press_frame_enabled := true
