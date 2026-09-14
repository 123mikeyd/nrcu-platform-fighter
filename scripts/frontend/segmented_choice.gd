extends Control
# SegmentedChoice — Doc 04 §8 (LOCKED): the SHARED segmented control for an
# either/or screen state (Character Select's FREE-FOR-ALL | TEAMS mode is the
# first adopter; any surface that needs a segmented readout uses this instead
# of ad-hoc focusable labels).
#
# Grammar:
#   - one flat row of text segments + ONE structural rule under the ACTIVE
#     segment (never a boxed field, never a generic embedded button);
#   - mouse: ONLY the left button activates (a right/middle click changes
#     nothing — forensic ledger C-027);
#   - keyboard/controller: the focused segment activates through the semantic
#     `ui_accept` path the owning screen already routes (the same one every
#     other custom control on these surfaces uses);
#   - focus: every segment is focusable and carries its OWN authored
#     CursorAnchor (Doc 03 §6); left/right between segments is an authored
#     pair the owning screen wires.
#
# The component owns selection PRESENTATION and hit/activation plumbing. The
# SELECTION ITSELF stays with the screen state (the screen calls
# set_selected()); the component never changes screen state by itself.

signal changed(index: int)          # an activation request (mouse left / semantic)
signal segment_focused(index: int)
signal segment_unfocused(index: int)

const Tokens = preload("res://scripts/ui_tokens.gd")
const AnchorScript = preload("res://scripts/frontend/cursor_anchor.gd")

const RULE_H := 2.0
const SEGMENT_H := 34.0
const ACTIVE_ALPHA := 1.0
const INACTIVE_ALPHA := 0.45

@onready var _rule: Panel = $ActiveRule

var _segments: Array = []           # Label per choice
var _selected := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
	_rule.position = Vector2(0.0, SEGMENT_H + 4.0)
	_rule.size = Vector2(0.0, RULE_H)

# --- API -------------------------------------------------------------------

func setup(entries: Array) -> void:
	# entries: [{name, text, x, width}] — the screen authors the exact row; the
	# component creates the segments, their anchors and their activation paths.
	for entry in entries:
		var label := Label.new()
		label.name = str(entry.get("name", "Segment"))
		label.text = str(entry.get("text", ""))
		label.position = Vector2(float(entry.get("x", 0.0)), 0.0)
		label.size = Vector2(float(entry.get("width", 120.0)), SEGMENT_H)
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.focus_mode = Control.FOCUS_ALL
		label.add_theme_font_size_override("font_size", Tokens.T_NAV)
		label.add_theme_color_override("font_color", Tokens.CREAM)
		var index := _segments.size()
		label.set_meta("segment_index", index)
		label.gui_input.connect(_on_segment_gui_input.bind(index))
		label.focus_entered.connect(func() -> void: segment_focused.emit(index))
		label.focus_exited.connect(func() -> void: segment_unfocused.emit(index))
		var anchor := AnchorScript.new()
		anchor.name = "CursorAnchor"
		anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Authored override on the shared rule: a segment IS its own text, so the
		# fingertip rests just BELOW the segment's lower-right corner — on the
		# control's own accent rule — and the option stays fully readable.
		anchor.x_ratio = 0.80
		anchor.y_ratio = 1.0
		anchor.optical_offset = Vector2(0.0, 4.0)
		label.add_child(anchor)
		add_child(label)
		_segments.append(label)
	_apply_selection()

func segments() -> Array:
	return _segments

func segment_count() -> int:
	return _segments.size()

func segment(index: int) -> Control:
	if index < 0 or index >= _segments.size():
		return null
	return _segments[index]

func segment_anchor(index: int) -> Control:
	var label := segment(index)
	if label == null:
		return null
	return label.get_node_or_null("CursorAnchor")

func segment_index_of(control: Control) -> int:
	for i in _segments.size():
		if _segments[i] == control:
			return i
	return -1

func selected() -> int:
	return _selected

func set_selected(index: int) -> void:
	_selected = clampi(index, 0, maxi(_segments.size() - 1, 0))
	_apply_selection()

func activate(index: int) -> void:
	# The screen's semantic accept path calls this for the focused segment
	# (keyboard/controller ui_accept); it routes through the same request signal
	# as the mouse so there is exactly one activation path.
	if index < 0 or index >= _segments.size():
		return
	changed.emit(index)

func _apply_selection() -> void:
	for i in _segments.size():
		var label: Label = _segments[i]
		label.modulate = Color(1, 1, 1, ACTIVE_ALPHA if i == _selected else INACTIVE_ALPHA)
	var active: Control = segment(_selected)
	if active != null:
		_rule.position = Vector2(active.position.x, SEGMENT_H + 4.0)
		_rule.size = Vector2(active.size.x, RULE_H)

# --- input -----------------------------------------------------------------

func _on_segment_gui_input(event: InputEvent, index: int) -> void:
	# §8/ledger C-027: only the LEFT button activates by mouse.
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			activate(index)
			accept_event()
