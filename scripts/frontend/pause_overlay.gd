extends Control
# WP-4 Pause route wrapper.
#
# Gameplay owns the pause/unpause state machine and route handoff. The shared
# ChoiceOverlay owns every visual detail: dim, shell, title, MenuRow choices,
# selection rails and focus anchors. Pause therefore cannot drift from Quit's
# visual grammar while keeping its own RESUME/LEAVE semantics.

signal opened
signal resume_requested
signal leave_requested(mode: String)

const ChoiceOverlayScene = preload("res://scenes/components/ChoiceOverlay.tscn")
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")

const STATE_CLOSED := "closed"
const STATE_OPEN := "open"
const STATE_LEAVING := "leaving"

const ITEM_RESUME := 0
const ITEM_LEAVE := 1

var _state := STATE_CLOSED
var _story := false
var _choice: Control
var _hover_connected := false

func _ready() -> void:
    name = "PauseOverlay"
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _choice = (ChoiceOverlayScene as PackedScene).instantiate()
    _choice.name = "ChoiceOverlay"
    add_child(_choice)
    _choice.configure("PAUSED", ["RESUME", "LEAVE MATCH"],
        ["RowResume", "RowLeave"], ["HitArea", "HitArea"])
    _choice.choice_pressed.connect(_on_choice_pressed)
    _choice.choice_focused.connect(_on_choice_focused)
    hide()

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
    _choice.configure("PAUSED", ["RESUME", "LEAVE ENCOUNTER" if _story else "LEAVE MATCH"],
        ["RowResume", "RowLeave"], ["HitArea", "HitArea"])
    _state = STATE_OPEN
    show()
    _choice.open()
    var hand = _hand()
    if hand != null:
        if not _hover_connected and not hand.hover_changed.is_connected(_on_hover_changed):
            hand.hover_changed.connect(_on_hover_changed)
            _hover_connected = true
        hand.begin_screen("pause")
        hand.add_target(action_resume())
        hand.add_target(action_leave())
    opened.emit()
    return true

func resume() -> bool:
    if _state != STATE_OPEN:
        return false
    _state = STATE_CLOSED
    _choice.close()
    hide()
    _drop_targets()
    resume_requested.emit()
    return true

func leave() -> bool:
    if _state != STATE_OPEN:
        return false
    _state = STATE_LEAVING
    _choice.close()
    hide()
    _drop_targets()
    leave_requested.emit("story" if _story else "vs")
    return true

# The adapter calls this after opening from a semantic keyboard/pad action.
# The physical pointer is never moved; a later genuine motion switches back to
# MOUSE mode via the shared cursor service.
func focus_default() -> void:
    if _state != STATE_OPEN:
        return
    action_resume().grab_focus()
    var hand = _hand()
    if hand != null:
        hand.claim_focus()
        hand.set_focus_target(focus_anchor_for(action_resume()))

func _on_choice_pressed(index: int) -> void:
    if index == ITEM_RESUME:
        resume()
    else:
        leave()

func _on_choice_focused(index: int) -> void:
    if _state != STATE_OPEN:
        return
    var control: Control = action(index)
    FocusGraph.track(self, control)
    _choice.set_active(index)
    var hand = _hand()
    if hand != null and hand.mode == 1:
        hand.set_focus_target(focus_anchor_for(control))

func _on_hover_changed(target: Control) -> void:
    if _state != STATE_OPEN or target == null:
        return
    var index: int = _choice.choice_index(target)
    if index >= 0:
        _choice.set_active(index)

func action(index: int) -> Button:
    return _choice.choice(index)

func action_resume() -> Button:
    return action(ITEM_RESUME)

func action_leave() -> Button:
    return action(ITEM_LEAVE)

func active_index() -> int:
    return _choice.active_index()

func _set_active_action(index: int) -> void:
    _choice.set_active(index)

func focus_anchor_for(control: Control) -> Control:
    return _choice.focus_anchor_for(control)

func _drop_targets() -> void:
    var hand = _hand()
    if hand != null:
        hand.drop_targets()

# --- public visual reads ---------------------------------------------------
func menu_rows() -> Array:
    return _choice.menu_rows()

func row_hit(index: int) -> Button:
    return _choice.choice(index)

func row_label(index: int) -> Label:
    return _choice.choice_label(index)

func item_plate(index: int) -> Panel:
    return _choice.item_plate(index)

func active_rail(index: int) -> Panel:
    return _choice.active_rail(index)

func quiet_rail(index: int) -> Panel:
    return _choice.quiet_rail(index)

func title_text() -> String:
    return _choice.title_text()

func resume_label() -> String:
    return str(row_label(ITEM_RESUME).text)

func leave_label() -> String:
    return str(row_label(ITEM_LEAVE).text)

func is_story_pause() -> bool:
    return _story

func plate_rect() -> Rect2:
    return _choice.plate_rect()

func _hand():
    var cursor = get_node_or_null("/root/Cursor")
    if cursor == null or cursor.hand == null:
        return null
    return cursor.hand
