extends Control
# NRCU hand cursor — Melee-CSS grammar in placeholder art.
#
# Visual-only layer: follows the real mouse with velocity easing, leans into
# motion, changes pose over targets (pointing / open-hand hover), squashes on
# click. It never consumes input — the real Buttons underneath still receive
# the original mouse events, so keyboard focus and programmatic `.pressed`
# emissions behave exactly as before.
#
# MOUSE INTENT (frontend brief §5, QA dossier §2.1 — P0):
#   * the hand never moves itself. Controller/keyboard focus never drags it;
#     focus is shown by the focused control's own frame, not by the pointer.
#   * `reset_for_screen()` re-anchors the graphic from the viewport's CURRENT
#     pointer position (read-only — the OS pointer is never warped).
#   * a stationary pointer does not take over a newly entered screen: hover is
#     only evaluated after genuine mouse motion. The last real input modality
#     arbitrates, exposed via `is_mouse_active()` for screens that care.
#   * coordinates equal canvas space (full-rect child of the cursor layer).

signal hover_changed(target: Control)
signal modality_changed(mouse_active: bool)

enum Pose { POINT, HOVER, PRESS }

const CREAM := Color("fff0cb")
const INK := Color("16292b")
const GOLD := Color("e5ad69")

# Feel tuning — snappy mouse tracking with a hint of life.
# The hand is a cursor, not a vehicle: perceptible lag reads as broken input.
const SPRING := 600.0
const DAMP := 26.0
const LEAN_SCALE := 0.0016
const LEAN_MAX := 0.38
const BASE_TILT := -0.42
const PRESS_SECONDS := 0.12  # minimum tap-frame flash (hold keeps it longer)
# Sub-pixel motion jitter must not count as "the player moved the mouse".
const MOTION_EPSILON := 0.4

# Texture poses (art in assets/ui; anchors = fingertip in texture space).
const HAND_SCALE := 0.33
const TIP_POINT := Vector2(15.5, 1.0)
const TIP_OPEN := Vector2(59.0, 1.0)
const TIP_GRAB := Vector2(50.0, 1.0)
const TIP_CARRY := Vector2(67.5, 32.0)
const TIP_PRESS := Vector2(49.0, 22.0)  # tap frame: glove tip (spark marks excluded)

# Carried chip: William's pose 1 carries the chip INSIDE the art — the coin
# (one of his generated coins) is baked into hand_carry.png at the pose's
# built-in placeholder spot, exactly like his Krita reference. CHIP_TEX_POS
# stays as the chip's texture-space center, used for the placement origin.
const CHIP_TEX_POS := Vector2(35.5, 34.0)

var targets: Array[Control] = []
var hovered: Control = null

var _pos := Vector2.ZERO
var _vel := Vector2.ZERO
var _lean := BASE_TILT
var _pose: Pose = Pose.POINT
var _press := 0.0
var _pressed_held := false
var _started := false
var _mouse := Vector2.ZERO
var _tex_point: Texture2D
var _tex_open: Texture2D
var _tex_carry: Texture2D
var _tex_press: Texture2D
var carrying := false
# True only after genuine mouse motion/click on the current screen. Screens
# read this to decide whether the pointer may drive hover/selection.
var mouse_active := false
# Kept for callers that suppress focus-driven feedback around programmatic
# focus grabs (results screen). The hand itself never moves on focus.
var attract_enabled := true
# Tap-frame on mouse-down; the story selection turns it off (carry pose rules there).
var press_frame_enabled := true

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    z_index = 50
    _tex_point = load("res://assets/ui/hand_point.png")
    _tex_open = load("res://assets/ui/hand_open.png")
    _tex_carry = load("res://assets/ui/hand_carry.png")
    _tex_press = load("res://assets/ui/hand_press.png")
    var vp := get_viewport()
    if vp != null:
        _mouse = vp.get_mouse_position()
        _pos = _mouse
        _started = true

func add_target(target: Control) -> void:
    if target == null or targets.has(target):
        return
    targets.append(target)

func drop_targets() -> void:
    targets.clear()
    hovered = null

# Focus feedback is the control's own frame; the pointer must not chase it.
func attract_to(_target: Control) -> void:
    pass

func is_mouse_active() -> bool:
    return mouse_active

func set_mouse_active(value: bool) -> void:
    if mouse_active == value:
        return
    mouse_active = value
    if not value and hovered != null:
        hovered = null
        hover_changed.emit(null)
    modality_changed.emit(mouse_active)

# Screen entry / backtracking: anchor the graphic at the pointer as it is
# right now. Never warps the OS pointer, never inherits the previous screen's
# hover, and waits for real motion before accepting pointer-driven hover.
func reset_for_screen() -> void:
    var vp := get_viewport()
    if vp != null:
        _mouse = vp.get_mouse_position()
    _pos = _mouse
    _vel = Vector2.ZERO
    _started = true
    _press = 0.0
    _pressed_held = false
    _lean = BASE_TILT
    if hovered != null:
        hovered = null
        hover_changed.emit(null)
    set_mouse_active(false)

func reset() -> void:
    reset_for_screen()

func set_carry() -> void:
    carrying = true
    queue_redraw()

func is_carrying() -> bool:
    return carrying

func chip_world_position() -> Vector2:
    # Center of the carried chip in this control's space (used as the fall origin).
    var tip := TIP_CARRY if carrying else TIP_GRAB
    return _pos + ((CHIP_TEX_POS - tip) * HAND_SCALE).rotated(_lean)

func release_carry() -> Vector2:
    var at := chip_world_position()
    carrying = false
    queue_redraw()
    return at

func clear_carry() -> void:
    # Silent release (no fall origin) — used when leaving the selection screen.
    carrying = false
    queue_redraw()

func active_target() -> Control:
    if hovered != null and is_instance_valid(hovered) and hovered.is_visible_in_tree():
        return hovered
    return null

func _process(delta: float) -> void:
    if not _started:
        reset_for_screen()
    if _press > 0.0:
        _press = maxf(_press - delta, 0.0)
    # Hover detection: only after genuine mouse input on this screen.
    var new_hover: Control = null
    if mouse_active:
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
    # Motion: eased follow of the real pointer. Nothing else moves the hand.
    _vel += (_mouse - _pos) * SPRING * delta
    _vel *= maxf(1.0 - DAMP * delta, 0.0)
    _pos += _vel * delta
    # Pose
    if _press > 0.0:
        _pose = Pose.PRESS
    elif active_target() != null:
        _pose = Pose.HOVER
    else:
        _pose = Pose.POINT
    var lean_goal := clampf(BASE_TILT + _vel.x * LEAN_SCALE, BASE_TILT - LEAN_MAX, BASE_TILT + LEAN_MAX)
    _lean = lerpf(_lean, lean_goal, minf(10.0 * delta, 1.0))
    queue_redraw()

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        _mouse = event.position
        if event.relative.length() >= MOTION_EPSILON:
            set_mouse_active(true)
    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                _pressed_held = true
                _press = PRESS_SECONDS
            else:
                _pressed_held = false
            queue_redraw()
        set_mouse_active(true)
    elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
        set_mouse_active(false)
    elif event is InputEventKey and event.pressed and not event.echo:
        set_mouse_active(false)

func _draw() -> void:
    if _tex_ready():
        _draw_texture_pose()
        return
    var squash := 0.78 if _pose == Pose.PRESS else 1.0
    draw_set_transform(_pos, _lean, Vector2(1.0, squash))
    draw_circle(Vector2(2.0, 6.0), 13.0, Color(0.02, 0.05, 0.06, 0.35))
    if _pose == Pose.HOVER:
        _draw_open_hand()
    else:
        _draw_pointing_hand()
    if _pose == Pose.PRESS:
        draw_arc(Vector2(0.0, 16.0), 18.0, 0.0, TAU, 40, Color(GOLD, 0.75), 2.0, true)

func _tex_ready() -> bool:
    return _tex_point != null and _tex_open != null and _tex_carry != null

func is_pressing() -> bool:
    # True while the button is held, plus a minimum flash so quick taps register.
    return _pressed_held or _press > 0.0

func active_texture() -> Texture2D:
    if carrying and _tex_carry != null:
        return _tex_carry
    if is_pressing() and press_frame_enabled and _tex_press != null:
        return _tex_press
    if _pose == Pose.HOVER and _tex_open != null:
        return _tex_open
    return _tex_point

func active_tip() -> Vector2:
    if carrying:
        return TIP_CARRY
    if is_pressing() and press_frame_enabled:
        return TIP_PRESS
    if _pose == Pose.HOVER:
        return TIP_OPEN
    return TIP_POINT

func _draw_texture_pose() -> void:
    var squash := 0.92 if (is_pressing() and carrying) else 1.0
    draw_set_transform(_pos, _lean, Vector2(HAND_SCALE, HAND_SCALE * squash))
    draw_texture(active_texture(), -active_tip())



func _draw_pointing_hand() -> void:
    draw_line(Vector2(0, 16), Vector2(0, 2), INK, 10.0, true)
    draw_circle(Vector2(0, 2), 5.0, INK)
    draw_line(Vector2(0, 16), Vector2(0, 3), CREAM, 7.0, true)
    draw_circle(Vector2(0, 3), 3.5, CREAM)
    draw_circle(Vector2(0, 19), 12.5, INK)
    draw_circle(Vector2(0, 19), 10.0, CREAM)
    draw_circle(Vector2(-8, 12), 4.6, INK)
    draw_circle(Vector2(-8, 12), 3.2, CREAM)

func _draw_open_hand() -> void:
    for angle in [-0.42, 0.0, 0.42]:
        var dir := Vector2(sin(angle), -cos(angle))
        var base := Vector2(0, 16) + dir * 9.0
        var tip := base + dir * 7.0
        draw_line(base, tip, INK, 9.0, true)
        draw_circle(tip, 4.4, INK)
        draw_line(base, tip, CREAM, 6.0, true)
        draw_circle(tip, 3.0, CREAM)
    draw_circle(Vector2(0, 19), 13.0, INK)
    draw_circle(Vector2(0, 19), 10.5, CREAM)
    draw_circle(Vector2(-9, 13), 4.6, INK)
    draw_circle(Vector2(-9, 13), 3.2, CREAM)
