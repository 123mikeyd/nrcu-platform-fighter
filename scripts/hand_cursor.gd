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
# the artist's TOP-LEFT grip pose (the one that HOLDS an object) with the baked
# coin MASKED OUT — hand_hold.png, cut from hand_carry.png — plus a separate
# PlayerTokenView owned by the screen and attached into this layer
# (`set_carry`). The carry pose and the per-player token are separate objects:
# no player identity is baked into hand art (Doc 01 §5, ledger C-008, G-031),
# which is exactly why the baked coin (a red disc labelled "P1") had to go.
#
# hover = the artist's EMPTY PINCH (sheet cell 2 of hand_sheet_v3.png,
# hand_hover.png, HOVER_TIP) — a hand hovering over a token it does not yet
# hold. It is the Visual.HOVER pose (the carry-art contract keeps it out of the
# carry path itself); a screen syncs the pose to its own state on entry and on
# every target/focus change.
#
# hand_grab.png stays available but is unused by the carry path.
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
enum Visual { REGULAR, CARRY, HOVER }

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
const TIP_GRAB := Vector2(50.0, 1.0)
const TIP_PRESS := Vector2(49.0, 22.0)
# --- the CARRY pose (hand_hold.png = the TOP-LEFT grip, baked coin masked off)
# Source: assets/ui/hand_carry.png, the artist's top-left grip pose
# (hand_sheet_v3.png top-left cell, 370x467, scaled to a 124x157 content box at
# (4,3) of a 129x160 canvas). That sprite is the grip that HOLDS an object; it
# shipped with a per-player token baked in (a red disc labelled "P1"), which
# tools/mask_carry_coin.py removes (fill + rim + label) while keeping the
# finger line-art that curls over the coin. Canvas and content placement are
# byte-identical to hand_carry.png, so the anchor below stays exact.
#
# TIP_CARRY is the cursor anchor of that pose: the point of the texture that
# lands on the logical hotspot.
const TIP_CARRY := Vector2(67.5, 32.0)
# The baked coin's centre inside that texture, MEASURED on hand_carry.png (a
# RANSAC circle fit on the red-fill boundary: 366 inlier boundary points,
# mean residual 0.28 px) -> (34.41, 33.45) with a fill radius of 30.67 px and
# an outermost coin pixel at radius 31.06 (mean over the unoccluded arc).
# The previously recorded value was (35.5, 34.0), 1.16 px away; the artist's
# chroma disc on the sheet would map to (36.9, 36.5) r 33.3.
const CHIP_TEX_POS := Vector2(34.45, 33.46)
# Where the carried token's CENTRE sits relative to the hotspot, in screen px:
# the coin's centre minus the anchor tip, at the hand's scale, so the token
# lands exactly on the texture pixel the baked coin occupied. The fingers of
# the glove draw OVER the token's near edge because the token slot is a sibling
# BELOW the hand node (fingers in front, exactly like the baked sprite).
const CARRY_CENTER := (CHIP_TEX_POS - TIP_CARRY) * HAND_SCALE
# --- the HOVER pose (hand_hover.png = sheet cell 2, the EMPTY pinch) --------
# The same grip with nothing in it: the hand hovering over a token it does not
# yet hold. Kept loaded and anchored for that future use; the CARRY path never
# draws it.
const HOVER_TEX := "res://assets/ui/hand_hover.png"
# The empty pocket between the two pinching digits spans x 8.6..37.6,
# y 33.9..56.0 of that 147x160 sprite, so its centre is (23.1, 45.0).
const HOVER_TIP := Vector2(23.1, 45.0)

var targets: Array[Control] = []
var hovered: Control = null
var mode: Mode = Mode.MOUSE
var visual: Visual = Visual.REGULAR
var scope := SCOPE_FRONTEND
var _native_pointer_suppressed := false
var hotspot := Vector2.ZERO          # authoritative interaction point
var _mouse := Vector2.ZERO
var _visual_mouse := Vector2.ZERO     # last sampled pointer position for art only
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
var _tex_hold: Texture2D
var _tex_press: Texture2D
var _tex_hover: Texture2D
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
    # CursorCarryLayer (Doc 04 §4): the ONE temporary parent of a carried token,
    # a sibling BELOW the hand so the gripping fingers overlap the token.
    _token_slot = Control.new()
    _token_slot.name = "CursorCarryLayer"
    _token_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_token_slot)
    add_child(_hand)
    _tex_point = load("res://assets/ui/hand_point.png")
    _tex_grab = load("res://assets/ui/hand_grab.png")
    _tex_hold = load("res://assets/ui/hand_hold.png")
    _tex_press = load("res://assets/ui/hand_press.png")
    _tex_hover = load(HOVER_TEX)
    var vp := get_viewport()
    if vp != null:
        _mouse = vp.get_mouse_position()
        _focus_pos = _mouse
    _visual_mouse = _mouse
    hotspot = _mouse

# --- semantic screen lifecycle ------------------------------------------
func begin_screen(_screen_id: String) -> void:
    # Clears stale hover ownership. Never touches physical pointer position,
    # never forces modality, never snaps the rendered hand.
    clear_hover()
    _hover_armed = false
    # A token that died with its screen can never stay carried: token ownership
    # belongs to the screen (Doc 04 §4), so a dead reference is dropped here —
    # there are no hidden cursor-owned tokens.
    if _carrying_token != null and not is_instance_valid(_carrying_token):
        clear_carry()
    # The pose belongs to the screen that owns the cursor: a new screen starts
    # from the ordinary pose and syncs it to its own state on entry (never the
    # previous screen's carry/hover pinch left behind).
    set_visual_mode(Visual.REGULAR)
    # Pointer sampling is presentation-only. Rebase it at the screen boundary
    # so motion delivered before the new surface mounted cannot create a stale
    # lean on the first frame.
    _visual_mouse = _mouse
    _vel_visual = Vector2.ZERO
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

func set_native_pointer_suppressed(suppressed: bool) -> void:
    # The global Cursor service uses this guard while an authoring owner has the
    # OS pointer. Screen lifecycle/scope code may still run during a remount,
    # but it must not reveal the game hand until the final owner releases it.
    _native_pointer_suppressed = suppressed
    if suppressed:
        visible = false

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
        visible = not _native_pointer_suppressed
    queue_redraw()

# --- carry (token lives in the screen; the cursor only carries it) -------
func set_carry(token: Control = null) -> void:
    # `token` is the screen-owned PlayerTokenView. A legacy caller may pass
    # nothing (carry pose only); the production CSS always passes its token.
    # One token object exists visually, in the CursorCarryLayer while carried
    # (Doc 01 §5, ledger C-008: no baked identity, no contradictory visibility).
    _carrying_token = token
    if token != null:
        if token.get_parent() != _token_slot:
            token.reparent(_token_slot)
        token.position = CARRY_CENTER - token_size(token) * 0.5
        token.visible = true
    set_visual_mode(Visual.CARRY)

func token_size(token: Control) -> Vector2:
    # PlayerTokenView carries its reference size in the scene (22-28 px family,
    # Doc 04 §13); a caller that hands over an unsized Control still gets a
    # centred carry placement instead of a half-offset one.
    var s := token.size
    if s.x <= 0.0 or s.y <= 0.0:
        return Vector2(26.0, 26.0)
    return s

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
        # The old cursor eased its logical position. Keep that historical feel
        # only in the rendered hand: the authoritative hotspot above remains
        # exactly at the pointer, while this filtered velocity drives lean.
        var mouse_delta := _mouse - _visual_mouse
        _visual_mouse = _mouse
        if delta > 0.0 and mouse_delta.length_squared() > 0.0:
            var input_velocity := mouse_delta / delta
            _vel_visual = _vel_visual.lerp(input_velocity, minf(18.0 * delta, 1.0))
        else:
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
    return _tex_point != null and _tex_hold != null

func is_pressing() -> bool:
    return _press_held or _press > 0.0

func active_texture() -> Texture2D:
    if is_pressing() and _tex_press != null:
        return _tex_press
    if visual == Visual.CARRY and _tex_hold != null:
        # The carry pose is the artist's TOP-LEFT grip (the one that holds an
        # object) with the baked coin masked out; the per-player token is the
        # separate object in the CursorCarryLayer. The empty-pinch sprite is
        # the HOVER pose (hover_texture()) and no carry path draws it.
        return _tex_hold
    if visual == Visual.HOVER and _tex_hover != null:
        # The EMPTY PINCH: the hand over a roster chip it does not hold yet
        # (entry-focus seed / a pointer resting on a tile before the carry
        # starts). The carry path never draws it.
        return _tex_hover
    return _tex_point

func hover_texture() -> Texture2D:
    # The HOVER pose: the artist's empty pinch (hand_hover.png) — what the hand
    # draws while it is over a token it does not yet hold.
    return _tex_hover

func active_tip() -> Vector2:
    if is_pressing():
        return TIP_PRESS
    if visual == Visual.CARRY:
        return TIP_CARRY
    if visual == Visual.HOVER:
        return HOVER_TIP
    return TIP_POINT

func carry_pinch_point() -> Vector2:
    # Screen-space position the carried token's CENTRE must land on: the anchor
    # hotspot plus the measured coin offset at the hand's scale, i.e. the point
    # of the drawn sprite the baked coin occupied.
    return hotspot + CARRY_CENTER

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
