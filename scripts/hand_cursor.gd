extends Control
# NRCU hand cursor — one persistent service, two presentation modes (Step 0).
#
# MOUSE MODE (§11): the interactive hotspot IS the exact physical mouse
# position. Nothing springs or eases the authoritative hotspot; hit testing,
# hover geometry and clicks all use it directly. The pleasant softness lives
# in the VISUAL ARTICULATION around the fingertip: filtered-velocity lean,
# tiny spring squash and the click press frame.
#
# FOCUS MODE (§12): controller/keyboard focus places the same hand at the
# focused component's authored CursorAnchor with a critically damped spring.
# The physical mouse is never moved. Screen entry in focus mode moves the
# hand to the new screen's authored default anchor.
#
# Modality (§13) follows the last MEANINGFUL input: pointer motion above an
# epsilon or a mouse button => mouse; navigation/confirm/back key or pad input
# => focus. On focus->mouse the hand reacquires the pointer immediately (the
# user just asked for pointer control) with a short pose settle, never a slow
# fly across the screen.
#
# Pose semantics (§13A): point = ordinary navigation; press = click/confirm;
# carry = grab pose + a separate PlayerTokenView owned by the screen and
# attached into this layer (`set_carry`). The baked hand_carry sprite is
# retired from production use.
#
# Hover arming (§14): a stationary pointer does not drive semantic hover on a
# newly entered screen until genuine mouse motion or a click.

signal hover_changed(target: Control)
signal modality_changed(mouse_mode: bool)

enum Mode { MOUSE, FOCUS }
enum Visual { REGULAR, CARRY }

const SPRING := 180.0          # focus-mode positional spring (critically controlled)
const DAMP := 30.0
const LEAN_SCALE := 0.0013
const LEAN_MAX := 0.30
const PRESS_SECONDS := 0.12
const MOTION_EPSILON := 0.4
const SETTLE_SECONDS := 0.14   # pose settle after modality reacquisition

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
var hotspot := Vector2.ZERO          # authoritative interaction point
var _mouse := Vector2.ZERO
var _hover_armed := false

var _focus_anchor: Control = null
var _focus_pos := Vector2.ZERO
var _focus_vel := Vector2.ZERO
var _has_focus_pos := false

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
        var target: Vector2 = anchor.get_global_rect().position
        if not _has_focus_pos:
            _focus_pos = target
            _has_focus_pos = true
        if mode != Mode.FOCUS:
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
    modality_changed.emit(m == Mode.MOUSE)
    queue_redraw()

func is_mouse_active() -> bool:
    return mode == Mode.MOUSE and _hover_armed

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
    if event is InputEventMouseMotion:
        _mouse = event.position
        if event.relative.length() >= MOTION_EPSILON:
            if mode != Mode.MOUSE:
                set_mode(Mode.MOUSE)
            _hover_armed = true  # the reacquiring motion itself arms hover
    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                _press_held = true
                _press = PRESS_SECONDS
            else:
                _press_held = false
        if mode != Mode.MOUSE:
            set_mode(Mode.MOUSE)
        _hover_armed = true
    elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
        set_mode(Mode.FOCUS)
    elif event is InputEventKey and event.pressed and not event.echo:
        set_mode(Mode.FOCUS)

func _process(delta: float) -> void:
    if _press > 0.0:
        _press = maxf(_press - delta, 0.0)
    if _settle > 0.0:
        _settle = maxf(_settle - delta, 0.0)
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
        # Focus mode: spring the presentation hand to the authored anchor.
        if _focus_anchor != null and is_instance_valid(_focus_anchor):
            var target: Vector2 = _focus_anchor.get_global_rect().position
            _has_focus_pos = true
            _focus_vel += (target - _focus_pos) * SPRING * delta
            _focus_vel *= maxf(1.0 - DAMP * delta, 0.0)
            _focus_pos += _focus_vel * delta
            _vel_visual = _focus_vel
        hotspot = _focus_pos
    var lean_goal := clampf(_vel_visual.x * LEAN_SCALE, -LEAN_MAX, LEAN_MAX)
    _lean = lerpf(_lean, lean_goal, minf(10.0 * delta, 1.0))
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
