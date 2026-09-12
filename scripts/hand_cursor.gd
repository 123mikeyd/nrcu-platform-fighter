extends Control
# NRCU hand cursor — Melee-CSS grammar in placeholder art.
#
# Visual-only layer: follows the real mouse with velocity easing, leans into
# motion, changes pose over targets (pointing / open-hand hover), squashes on
# click. It never consumes input — the real Buttons underneath still receive
# the original mouse events, so keyboard focus and programmatic `.pressed`
# emissions behave exactly as before.
#
# Coordinates: meant to be a full-rect child at its canvas origin, so local
# space equals canvas space for the game's full-screen UI panels.

signal hover_changed(target: Control)

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
const PRESS_SECONDS := 0.16
const ATTRACT_SECONDS := 0.9
const ATTRACT_RELEASE_DIST := 28.0

# Texture poses (art in assets/ui; anchors = fingertip in texture space).
const HAND_SCALE := 0.33
const TIP_POINT := Vector2(15.5, 1.0)
const TIP_OPEN := Vector2(59.0, 1.0)
const TIP_GRAB := Vector2(50.0, 1.0)
const TIP_CARRY := Vector2(67.5, 32.0)

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
var _attract: Control = null
var _attract_timer := 0.0
var _attract_anchor := Vector2.ZERO
var _started := false
var _mouse := Vector2.ZERO
var _tex_point: Texture2D
var _tex_open: Texture2D
var _tex_carry: Texture2D
var carrying := false
# Programmatic focus grabs (results screen) set this false so the hand is not
# pulled toward a target the user did not navigate to. See main.gd.
var attract_enabled := true

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    z_index = 50
    _tex_point = load("res://assets/ui/hand_point.png")
    _tex_open = load("res://assets/ui/hand_open.png")
    _tex_carry = load("res://assets/ui/hand_carry.png")

func add_target(target: Control) -> void:
    if target == null or targets.has(target):
        return
    targets.append(target)
    target.focus_entered.connect(attract_to.bind(target))

func attract_to(target: Control) -> void:
    if not attract_enabled:
        return
    _attract = target
    _attract_timer = ATTRACT_SECONDS
    _attract_anchor = _mouse

func reset() -> void:
    _mouse = get_global_mouse_position()
    _pos = _mouse
    _vel = Vector2.ZERO
    _started = true

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
    if _attract_timer > 0.0 and is_instance_valid(_attract):
        return _attract
    return null

func _process(delta: float) -> void:
    # Track the mouse from input EVENTS (same source the UI hovers use) — the
    # OS-polled get_global_mouse_position() disagrees with synthetic input and
    # with window-relative event coords.
    var mouse := _mouse
    if not _started:
        reset()
    if _attract_timer > 0.0:
        _attract_timer -= delta
        if mouse.distance_to(_attract_anchor) > ATTRACT_RELEASE_DIST:
            _attract_timer = 0.0
    if _press > 0.0:
        _press = maxf(_press - delta, 0.0)
    # Hover detection from the real mouse position, smallest visible target wins.
    var new_hover: Control = null
    var new_area := INF
    for target in targets:
        if not is_instance_valid(target) or not target.is_visible_in_tree():
            continue
        var rect := target.get_global_rect()
        if rect.has_point(mouse) and rect.get_area() < new_area:
            new_hover = target
            new_area = rect.get_area()
    if new_hover != hovered:
        hovered = new_hover
        hover_changed.emit(hovered)
    # Motion: eased follow of the mouse, attracted to a keyboard-focused target.
    var goal := mouse
    if _attract_timer > 0.0 and is_instance_valid(_attract) and _attract.is_visible_in_tree():
        goal = _attract.get_global_rect().get_center()
    _vel += (goal - _pos) * SPRING * delta
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
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _press = PRESS_SECONDS
        queue_redraw()

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

func _draw_texture_pose() -> void:
    var tex: Texture2D = _tex_point
    var tip := TIP_POINT
    if carrying:
        tex = _tex_carry
        tip = TIP_CARRY
    elif _pose == Pose.HOVER:
        tex = _tex_open
        tip = TIP_OPEN
    var squash := 0.92 if _press > 0.0 else 1.0
    draw_set_transform(_pos, _lean, Vector2(HAND_SCALE, HAND_SCALE * squash))
    draw_texture(tex, -tip)



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
