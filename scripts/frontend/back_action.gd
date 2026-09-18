extends Button
# Shared header Back action. The component owns the quiet idle treatment, the
# right-aligned optical inset, the warm hover/focus rail, and its hand anchor so
# screen routes only need the ordinary Button signal.

const Tokens = preload("res://scripts/ui_tokens.gd")

@export var cursor_x_ratio := 0.80
@export var cursor_y_ratio := 0.72
@export var cursor_optical_offset := Vector2.ZERO

@onready var _anchor: Control = $CursorAnchor
@onready var _rail: Panel = $BackRail

var _pointer_over := false

func _ready() -> void:
    focus_mode = Control.FOCUS_ALL
    alignment = HORIZONTAL_ALIGNMENT_RIGHT
    text = "BACK"
    _configure_anchor()
    _style()
    mouse_entered.connect(_on_mouse_entered)
    mouse_exited.connect(_on_mouse_exited)
    focus_entered.connect(_on_focus_entered)
    focus_exited.connect(_on_focus_exited)
    _update_rail()

func _configure_anchor() -> void:
    _anchor.x_ratio = cursor_x_ratio
    _anchor.y_ratio = cursor_y_ratio
    _anchor.optical_offset = cursor_optical_offset

func _style() -> void:
    var transparent := Color(0, 0, 0, 0)
    var idle := _style_box(transparent)
    var hover := _style_box(Color(1, 1, 1, 0.05))
    var pressed := _style_box(Color(1, 1, 1, 0.09))
    Tokens.apply_styles(self, {
        "normal": idle,
        "hover": hover,
        "pressed": pressed,
        "focus": hover,
        "disabled": idle,
    })
    add_theme_font_override("font", Tokens.font("semibold"))
    add_theme_font_size_override("font_size", Tokens.T_ACTION)
    add_theme_color_override("font_color", Tokens.CREAM_DIM)
    add_theme_color_override("font_hover_color", Tokens.CREAM)
    add_theme_color_override("font_focus_color", Tokens.CREAM)
    add_theme_color_override("font_pressed_color", Tokens.CREAM)
    _rail.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT, Color(0, 0, 0, 0), 0, Tokens.RADIUS_FLAT))

func _style_box(background: Color) -> StyleBoxFlat:
    var box := Tokens.flat(background, Color(0, 0, 0, 0), 0, Tokens.RADIUS_FLAT)
    box.content_margin_right = Tokens.S24
    return box

func _on_mouse_entered() -> void:
    _pointer_over = true
    _update_rail()

func _on_mouse_exited() -> void:
    _pointer_over = false
    _update_rail()

func _on_focus_entered() -> void:
    _update_rail()

func _on_focus_exited() -> void:
    _update_rail()

func _update_rail() -> void:
    if _rail != null and is_instance_valid(_rail):
        _rail.visible = _pointer_over or has_focus()

func cursor_anchor() -> Control:
    return _anchor

func back_rail() -> Panel:
    return _rail
