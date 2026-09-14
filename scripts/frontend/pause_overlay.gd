extends Control
# WP-4 Pause surface.
#
# The overlay is deliberately a small, input-complete state machine. Gameplay
# owns the match and the adapter owns SceneTree.paused/input scope; this surface
# only owns the visible actions and emits semantic route requests.
#
# CLOSED --open(story)--> OPEN --resume()--> CLOSED
#                         |
#                         `--leave()--> LEAVING
#
# Gameplay entry: Esc / controller Start -> OPEN.
# OPEN: ui_cancel / RESUME -> CLOSED; LEAVE MATCH/ENCOUNTER -> LEAVING.

signal opened
signal resume_requested
signal leave_requested(mode: String)

const Tokens = preload("res://scripts/ui_tokens.gd")
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")
const AnchorScript = preload("res://scripts/frontend/cursor_anchor.gd")

const STATE_CLOSED := "closed"
const STATE_OPEN := "open"
const STATE_LEAVING := "leaving"

const PLATE_RECT := Rect2(410.0, 224.0, 460.0, 272.0)

var _state := STATE_CLOSED
var _story := false
var _dim: ColorRect
var _plate: Panel
var _title: Label
var _action_resume: Button
var _action_leave: Button
var _resume_rail: Panel
var _leave_rail: Panel
var _anchor_resume: Control
var _anchor_leave: Control

func _ready() -> void:
    name = "PauseOverlay"
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _build()
    hide()

func _build() -> void:
    _dim = ColorRect.new()
    _dim.name = "Dim"
    _dim.color = Color(0.0, 0.0, 0.0, 0.58)
    _dim.mouse_filter = Control.MOUSE_FILTER_STOP
    _dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(_dim)

    var frame := Tokens.make_reference_frame(self)
    _plate = Panel.new()
    _plate.name = "Plate"
    _plate.position = PLATE_RECT.position
    _plate.size = PLATE_RECT.size
    _plate.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_FLAT))
    frame.add_child(_plate)

    _title = Label.new()
    _title.name = "PauseTitle"
    _title.text = "PAUSED"
    _title.position = Vector2(40.0, 28.0)
    _title.size = Vector2(380.0, 40.0)
    _title.add_theme_font_override("font", Tokens.font("semibold"))
    _title.add_theme_font_size_override("font_size", 30)
    _title.add_theme_color_override("font_color", Tokens.CREAM)
    _plate.add_child(_title)

    _action_resume = _make_action("ActionResume", "RESUME", Vector2(40.0, 96.0))
    _resume_rail = _make_rail("ResumeRail", Vector2(40.0, 143.0), 250.0)
    _action_leave = _make_action("ActionLeave", "LEAVE MATCH", Vector2(40.0, 166.0))
    _leave_rail = _make_rail("LeaveRail", Vector2(40.0, 213.0), 250.0)
    _anchor_resume = _make_anchor("AnchorResume", NodePath("../ActionResume"))
    _anchor_leave = _make_anchor("AnchorLeave", NodePath("../ActionLeave"))

    _action_resume.pressed.connect(_on_resume_pressed)
    _action_leave.pressed.connect(_on_leave_pressed)
    _action_resume.focus_entered.connect(_on_action_focused.bind(_action_resume))
    _action_leave.focus_entered.connect(_on_action_focused.bind(_action_leave))
    _action_resume.focus_entered.connect(_set_active_action.bind(true))
    _action_leave.focus_entered.connect(_set_active_action.bind(false))

    # Pause is a trapped two-action surface. It never lets tree-order focus
    # escape to the gameplay HUD behind it.
    FocusGraph.chain([_action_resume, _action_leave], true)
    for direction in [&"left", &"right", &"top", &"bottom"]:
        FocusGraph.wire(_action_resume, _action_leave, [direction])
        FocusGraph.wire(_action_leave, _action_resume, [direction])
    _set_active_action(true)

func _make_action(node_name: String, text: String, at: Vector2) -> Button:
    var button := Button.new()
    button.name = node_name
    button.text = text
    button.position = at
    button.size = Vector2(300.0, 44.0)
    button.focus_mode = Control.FOCUS_ALL
    Tokens.apply_styles(button, {
        "normal": Tokens.flat(Color(0, 0, 0, 0)),
        "hover": Tokens.flat(Color(0, 0, 0, 0)),
        "pressed": Tokens.flat(Color(0, 0, 0, 0)),
        "focus": Tokens.flat(Color(0, 0, 0, 0)),
    })
    button.add_theme_font_override("font", Tokens.font("medium"))
    button.add_theme_font_size_override("font_size", 24)
    button.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    button.add_theme_color_override("font_hover_color", Tokens.CREAM)
    button.add_theme_color_override("font_focus_color", Tokens.CREAM)
    _plate.add_child(button)
    return button

func _make_rail(node_name: String, at: Vector2, width: float) -> Panel:
    var rail := Panel.new()
    rail.name = node_name
    rail.position = at
    rail.size = Vector2(width, 3.0)
    rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
    rail.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    _plate.add_child(rail)
    return rail

func _make_anchor(node_name: String, host_path: NodePath) -> Control:
    var anchor: Control = AnchorScript.new()
    anchor.name = node_name
    anchor.host_path = host_path
    _plate.add_child(anchor)
    return anchor

# --- state machine ----------------------------------------------------------
func state() -> String:
    return _state

func is_open() -> bool:
    return _state == STATE_OPEN

func is_leaving() -> bool:
    return _state == STATE_LEAVING

func open(story := false) -> bool:
    if _state != STATE_CLOSED:
        return false
    _story = bool(story)
    _action_leave.text = "LEAVE ENCOUNTER" if _story else "LEAVE MATCH"
    _state = STATE_OPEN
    show()
    _dim.modulate.a = 1.0
    _action_resume.grab_focus()
    _set_active_action(true)
    var hand = _hand()
    if hand != null:
        hand.begin_screen("pause")
        hand.add_target(_action_resume)
        hand.add_target(_action_leave)
    opened.emit()
    return true

func resume() -> bool:
    if _state != STATE_OPEN:
        return false
    _state = STATE_CLOSED
    _hide()
    _drop_targets()
    resume_requested.emit()
    return true

func leave() -> bool:
    if _state != STATE_OPEN:
        return false
    _state = STATE_LEAVING
    _hide()
    _drop_targets()
    leave_requested.emit("story" if _story else "vs")
    return true

# The adapter calls this after opening from a semantic keyboard/pad action.
# The physical pointer is never moved; a later genuine motion switches back to
# MOUSE mode via the shared cursor service.
func focus_default() -> void:
    if _state != STATE_OPEN:
        return
    _action_resume.grab_focus()
    var hand = _hand()
    if hand != null:
        hand.claim_focus()
        hand.set_focus_target(_anchor_resume)

# --- action/focus contract --------------------------------------------------
func _on_resume_pressed() -> void:
    resume()

func _on_leave_pressed() -> void:
    leave()

func _on_action_focused(control: Control) -> void:
    FocusGraph.track(self, control)
    var hand = _hand()
    if hand != null and hand.mode == 1:
        var anchor := focus_anchor_for(control)
        if anchor != null:
            hand.set_focus_target(anchor)

func _set_active_action(resume_active: bool) -> void:
    _resume_rail.visible = resume_active
    _leave_rail.visible = not resume_active
    _action_resume.add_theme_color_override("font_color", Tokens.CREAM if resume_active else Tokens.CREAM_DIM)
    _action_leave.add_theme_color_override("font_color", Tokens.CREAM if not resume_active else Tokens.CREAM_DIM)

func focus_anchor_for(control: Control) -> Control:
    if control == _action_resume:
        return _anchor_resume
    if control == _action_leave:
        return _anchor_leave
    return FocusGraph.anchor_of(control)

func _drop_targets() -> void:
    var hand = _hand()
    if hand != null:
        hand.drop_targets()

func _hide() -> void:
    hide()
    _dim.modulate.a = 0.0

# --- public reads -----------------------------------------------------------
func action_resume() -> Button:
    return _action_resume

func action_leave() -> Button:
    return _action_leave

func title_text() -> String:
    return str(_title.text)

func resume_label() -> String:
    return str(_action_resume.text)

func leave_label() -> String:
    return str(_action_leave.text)

func is_story_pause() -> bool:
    return _story

func plate_rect() -> Rect2:
    return _plate.get_global_rect()

func _hand():
    var cursor = get_node_or_null("/root/Cursor")
    if cursor == null or cursor.hand == null:
        return null
    return cursor.hand
