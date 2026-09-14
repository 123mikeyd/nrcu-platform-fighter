extends Control
# PlayerBay — Doc 04 §9 (LOCKED). One of four tall player stations.
#
# The bay is a plain Control with DISTINCT SEMANTIC CONTROLS inside it — never
# one large Button with nested Buttons (Doc 04 §22 hostile gate). Clicking a
# non-control region activates that player; the kind/difficulty/team controls
# own their own hit areas.
#
# Anatomy (authored in PlayerBay.tscn):
#   PlayerHeader        P# + kind control (HMN/CPU/EMPTY) + structural player
#                       color block (Doc 04 §9.1/§9.2)
#   FighterRenderArea   hosts one FighterRenderView (render-on-change)
#   FighterNamePlate    the only place the fighter name appears in the bay
#   SecondaryControls   Human input readout (Doc 04 §7) XOR CPU difficulty row,
#                       + team control (teams)
#   ActivePlayerMarker  slight material lift + ONE small warm notch — never a
#                       full amber perimeter (Doc 04 §10)
#   CursorAnchor        near the player header, not over the model/name
#
# Bay geometry at 1280x720 reference: ~284x268 (Doc 04 §8). Bands are fixed
# typographic strips; the render area flexes with the bay size.

const Tokens = preload("res://scripts/ui_tokens.gd")
const RenderView = preload("res://scripts/frontend/fighter_render_view.gd")

const KINDS := ["human", "bot", "empty"]
const KIND_LABELS := {"human": "HMN", "bot": "CPU", "empty": "EMPTY"}

const HEADER_H := 46.0
const HEADER_BLOCK_W := 12.0
const NAME_H := 32.0
const SECONDARY_H := 28.0
const INSET := 8.0
const NOTCH_W := 22.0
const NOTCH_H := 3.0

signal bay_activated(index: int)
signal kind_clicked(index: int)
signal difficulty_clicked(index: int)
signal team_clicked(index: int)
signal input_clicked(index: int)

@onready var bay_plate: Panel = $BayPlate
@onready var header: Control = $PlayerHeader
@onready var header_plate: Panel = $PlayerHeader/HeaderPlate
@onready var player_block: Panel = $PlayerHeader/PlayerBlock
@onready var player_label: Label = $PlayerHeader/PlayerLabel
@onready var kind_control: Button = $PlayerHeader/KindControl
@onready var render_area: Control = $FighterRenderArea
@onready var name_plate: Control = $FighterNamePlate
@onready var fighter_name: Label = $FighterNamePlate/FighterName
@onready var secondary: Control = $SecondaryControls
@onready var input_row: Control = $SecondaryControls/InputRow
@onready var input_label: Label = $SecondaryControls/InputRow/InputLabel
@onready var input_control: Button = $SecondaryControls/InputRow/InputControl
@onready var difficulty_row: Control = $SecondaryControls/DifficultyRow
@onready var difficulty_label: Label = $SecondaryControls/DifficultyRow/DifficultyLabel
@onready var difficulty_control: Button = $SecondaryControls/DifficultyRow/DifficultyControl
@onready var team_control: Button = $SecondaryControls/TeamControl
@onready var notch: Panel = $ActiveNotch
@onready var _anchor: Control = $CursorAnchor
# Nested state controls carry their OWN authored anchors (Doc 03 §6): the
# kind/input/difficulty/team readouts are focusable Buttons, so each one must
# have a hand target of its own instead of falling back to the bay's anchor.
@onready var _kind_anchor: Control = $PlayerHeader/KindControl/CursorAnchor
@onready var _input_anchor: Control = $SecondaryControls/InputRow/InputControl/CursorAnchor
@onready var _difficulty_anchor: Control = $SecondaryControls/DifficultyRow/DifficultyControl/CursorAnchor
@onready var _team_anchor: Control = $SecondaryControls/TeamControl/CursorAnchor

var index := 0
var kind := "human"
var difficulty := "normal"
var team := 0
var mode := 0
var input_text := ""              # quiet device readout (Doc 04 §7)
var input_valid := true           # false = the Human slot cannot ready
var _active := false
var _render_view = null
var _focus_rule: Panel = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	bay_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	render_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fighter_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	secondary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	difficulty_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_label.add_theme_font_override("font", Tokens.font("bold"))
	player_label.add_theme_font_size_override("font_size", Tokens.T_NAV)
	player_label.add_theme_color_override("font_color", Tokens.CREAM)
	fighter_name.clip_text = true
	fighter_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fighter_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fighter_name.add_theme_font_override("font", Tokens.font("bold"))
	fighter_name.add_theme_font_size_override("font_size", Tokens.T_ACTION)
	fighter_name.add_theme_color_override("font_color", Tokens.CREAM)
	_style_state_button(kind_control, Tokens.T_META)
	_style_state_button(input_control, Tokens.T_META)
	_style_state_button(difficulty_control, Tokens.T_META)
	_style_state_button(team_control, Tokens.T_META)
	input_label.add_theme_font_size_override("font_size", Tokens.T_META)
	input_label.add_theme_color_override("font_color", Tokens.CREAM_DIM)
	difficulty_label.add_theme_font_size_override("font_size", Tokens.T_META)
	difficulty_label.add_theme_color_override("font_color", Tokens.CREAM_DIM)
	notch.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
	# §6 control emphasis: the bay is a custom Control, so its focus signal is a
	# dedicated 2 px structural edge (never a color-only state).
	_focus_rule = Panel.new()
	_focus_rule.name = "FocusRule"
	_focus_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
	_focus_rule.visible = false
	header.add_child(_focus_rule)
	kind_control.pressed.connect(func() -> void: kind_clicked.emit(index))
	input_control.pressed.connect(func() -> void: input_clicked.emit(index))
	difficulty_control.pressed.connect(func() -> void: difficulty_clicked.emit(index))
	team_control.pressed.connect(func() -> void: team_clicked.emit(index))
	resized.connect(_layout)
	_setup_plate()
	_layout()
	_refresh_state()

func _setup_plate() -> void:
	bay_plate.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_PLATE))
	header_plate.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_2))

func _style_state_button(button: Button, font_size: int) -> void:
	# State readout, not a generic embedded button: flat field with a quiet
	# rule that warms on hover/focus (Doc 04 §9.2).
	button.add_theme_font_override("font", Tokens.font("semibold"))
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Tokens.CREAM)
	button.add_theme_color_override("font_hover_color", Tokens.CREAM)
	button.add_theme_color_override("font_pressed_color", Tokens.CREAM)
	button.add_theme_color_override("font_focus_color", Tokens.CREAM)
	button.add_theme_stylebox_override("normal", Tokens.flat(Color(0, 0, 0, 0), Tokens.RULE_WARM, Tokens.STROKE))
	button.add_theme_stylebox_override("hover", Tokens.flat(Color(1, 1, 1, 0.05), Tokens.ACCENT, Tokens.STROKE))
	button.add_theme_stylebox_override("pressed", Tokens.flat(Color(1, 1, 1, 0.09), Tokens.ACCENT, Tokens.STROKE_STRONG))
	button.add_theme_stylebox_override("focus", Tokens.flat(Color(0, 0, 0, 0), Tokens.ACCENT, Tokens.STROKE_STRONG))
	button.add_theme_stylebox_override("disabled", Tokens.flat(Color(0, 0, 0, 0), Tokens.RULE, Tokens.STROKE))

func _gui_input(event: InputEvent) -> void:
	# Clicks outside the semantic controls belong to the player region.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		bay_activated.emit(index)
		accept_event()

# --- API -------------------------------------------------------------------

func setup(bay_index: int) -> void:
	index = bay_index
	player_label.text = "P" + str(index + 1)
	player_block.add_theme_stylebox_override("panel", Tokens.flat(Tokens.PLAYER_COLORS[index % Tokens.PLAYER_COLORS.size()]))
	if _render_view == null:
		_render_view = RenderView.new()
		_render_view.name = "FighterRenderView"
		render_area.add_child(_render_view)
		_render_view.set_profile(RenderView.PROFILE_PLAYER_BAY)
	_layout()

func set_slot_state(slot_kind: String, fighter_id := "", slot_name := "", slot_difficulty := "normal", slot_team := 0, slot_mode = 0, slot_input := "", slot_input_ok := true) -> void:
	kind = slot_kind if KINDS.has(slot_kind) else "human"
	difficulty = slot_difficulty
	team = int(slot_team)
	mode = 1 if _is_teams(slot_mode) else 0
	input_text = str(slot_input)
	input_valid = bool(slot_input_ok)
	kind_control.text = KIND_LABELS.get(kind, "HMN")
	fighter_name.text = slot_name.to_upper() if fighter_id != "" else ""
	if _render_view != null:
		if fighter_id != "" and kind != "empty":
			_render_view.visible = true
			var ids: Array[String] = _render_view.subjects()
			if ids.size() != 1 or ids[0] != fighter_id:
				_render_view.set_subjects([fighter_id])
		else:
			_render_view.clear_subjects()
			_render_view.visible = false
	_refresh_state()
	_layout()

func preview_fighter(fighter_id: String, slot_name: String, palette_index: int) -> void:
	# Doc 04 §12 / ledger C-047: the active bay large-previews the CANDIDATE
	# before commit, without touching the committed state. Cleared by the next
	# set_slot_state() (the committed presentation).
	if _render_view == null or fighter_id == "":
		return
	_render_view.visible = true
	_render_view.set_subjects([fighter_id])
	_render_view.set_palette(int(palette_index))
	fighter_name.text = slot_name.to_upper()

func presented_fighter() -> String:
	# The fighter the bay currently PRESENTS (candidate while browsing, else the
	# committed fighter) — the read the preview contract is asserted through.
	if _render_view == null or not _render_view.visible:
		return ""
	var ids: Array[String] = _render_view.subjects()
	return str(ids[0]) if ids.size() > 0 else ""

func presented_palette() -> int:
	return int(_render_view.palette_index()) if _render_view != null else 0

func set_palette_variant(index: int) -> void:
	# The RESOLVED duplicate-fighter variant (Doc 04 §14), applied to the
	# bay's presentation so the preview matches gameplay and the snapshot.
	if _render_view != null:
		_render_view.set_palette(int(index))

func input_readout() -> String:
	return input_text

func input_readout_valid() -> bool:
	return input_valid

func _is_teams(slot_mode) -> bool:
	if typeof(slot_mode) == TYPE_STRING:
		return String(slot_mode).to_lower().begins_with("team")
	return bool(slot_mode)

func set_active(active: bool) -> void:
	_active = active
	# Slight material lift + ONE small warm notch — never a full amber frame.
	bay_plate.add_theme_stylebox_override("panel",
		Tokens.flat(Tokens.SURFACE_2 if active else Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_PLATE))
	notch.visible = active

func is_active() -> bool:
	return _active

func render_view():
	return _render_view

func anchor() -> Control:
	return _anchor

func difficulty_row_visible() -> bool:
	return difficulty_row.visible

func team_control_visible() -> bool:
	return team_control.visible

func _refresh_state() -> void:
	# Doc 04 §6: kind transitions own their controls, and never a hidden
	# processor keeps focus (Doc 03 §6).
	#   HMN   -> quiet input readout (Doc 04 §7 device assignment);
	#   CPU   -> difficulty row visible, input assignment hidden;
	#   EMPTY -> neither (the bay recedes).
	# A Human slot whose device assignment is invalid (P3/P4 with no connected
	# pad, or a disconnected pad) explicitly reads CONNECT CONTROLLER and stays
	# out of the Ready gate (the ONE validation authority decides that).
	input_row.visible = kind == "human"
	input_control.focus_mode = Control.FOCUS_ALL if input_row.visible else Control.FOCUS_NONE
	input_control.text = input_text
	var input_color: Color = Tokens.CREAM if input_valid else Tokens.ACCENT
	input_control.add_theme_color_override("font_color", input_color)
	input_control.add_theme_color_override("font_hover_color", input_color)
	input_control.add_theme_color_override("font_pressed_color", input_color)
	input_control.add_theme_color_override("font_focus_color", input_color)
	difficulty_row.visible = kind == "bot"
	difficulty_control.focus_mode = Control.FOCUS_ALL if difficulty_row.visible else Control.FOCUS_NONE
	difficulty_control.text = difficulty.to_upper()
	team_control.visible = mode == 1 and kind != "empty"
	team_control.focus_mode = Control.FOCUS_ALL if team_control.visible else Control.FOCUS_NONE
	team_control.text = "TEAM " + ("A" if team == 0 else "B")
	team_control.add_theme_color_override("font_color", Tokens.CREAM)
	render_area.modulate = Color(1, 1, 1, 0.5) if kind == "empty" else Color(1, 1, 1, 1)

# --- layout (bands fixed, render area flexes) ------------------------------

func _layout() -> void:
	var s := size
	bay_plate.position = Vector2.ZERO
	bay_plate.size = s
	header.position = Vector2.ZERO
	header.size = Vector2(s.x, HEADER_H)
	header_plate.position = Vector2.ZERO
	header_plate.size = Vector2(s.x, HEADER_H)
	player_block.position = Vector2.ZERO
	player_block.size = Vector2(HEADER_BLOCK_W, HEADER_H)
	player_label.position = Vector2(HEADER_BLOCK_W + 8.0, 0.0)
	player_label.size = Vector2(90.0, HEADER_H)
	kind_control.position = Vector2(s.x - INSET - 88.0, (HEADER_H - 28.0) * 0.5)
	kind_control.size = Vector2(88.0, 28.0)
	var render_top := HEADER_H + 4.0
	var render_h := maxf(s.y - HEADER_H - NAME_H - SECONDARY_H - 14.0, 24.0)
	render_area.position = Vector2(INSET, render_top)
	render_area.size = Vector2(maxf(s.x - INSET * 2.0, 24.0), render_h)
	if _render_view != null and is_instance_valid(_render_view):
		_render_view.position = Vector2.ZERO
		_render_view.size = render_area.size
	name_plate.position = Vector2(INSET, s.y - SECONDARY_H - NAME_H - 6.0)
	name_plate.size = Vector2(maxf(s.x - INSET * 2.0, 24.0), NAME_H)
	fighter_name.position = Vector2.ZERO
	fighter_name.size = name_plate.size
	secondary.position = Vector2(INSET, s.y - SECONDARY_H - 2.0)
	secondary.size = Vector2(maxf(s.x - INSET * 2.0, 24.0), SECONDARY_H)
	var half := maxf((secondary.size.x - 6.0) * 0.5, 40.0)
	input_row.position = Vector2.ZERO
	input_row.size = Vector2(half, SECONDARY_H)
	input_label.position = Vector2(0.0, (SECONDARY_H - 18.0) * 0.5)
	input_label.size = Vector2(38.0, 18.0)
	input_control.position = Vector2(40.0, 1.0)
	input_control.size = Vector2(maxf(half - 40.0, 40.0), SECONDARY_H - 2.0)
	difficulty_row.position = Vector2.ZERO
	difficulty_row.size = Vector2(half, SECONDARY_H)
	difficulty_label.position = Vector2(0.0, (SECONDARY_H - 18.0) * 0.5)
	difficulty_label.size = Vector2(38.0, 18.0)
	difficulty_control.position = Vector2(40.0, 1.0)
	difficulty_control.size = Vector2(maxf(half - 40.0, 40.0), SECONDARY_H - 2.0)
	team_control.position = Vector2(secondary.size.x - half, 1.0)
	team_control.size = Vector2(half, SECONDARY_H - 2.0)
	notch.position = Vector2((s.x - NOTCH_W) * 0.5, 0.0)
	notch.size = Vector2(NOTCH_W, NOTCH_H)
	_focus_rule.position = Vector2(0.0, HEADER_H - 2.0)
	_focus_rule.size = Vector2(s.x, 2.0)
	# Authored focus anchor: beside the header's lower-left, so the focus hand
	# never covers the model or the name (Doc 04 §10).
	_anchor.place_at(Vector2(INSET, HEADER_H + 8.0))
	# The nested state controls get their own authored hand targets, placed at
	# the control's lower-left (measured from the control, so the placement
	# survives any bay size).
	_kind_anchor.place_at(Vector2(-8.0, kind_control.size.y - 4.0))
	_input_anchor.place_at(Vector2(-8.0, input_control.size.y - 4.0))
	_difficulty_anchor.place_at(Vector2(-8.0, difficulty_control.size.y - 4.0))
	_team_anchor.place_at(Vector2(team_control.size.x + 8.0, team_control.size.y - 4.0))

# --- nested state controls (Doc 03 §6/§13) ----------------------------------

func state_control(role: String) -> Button:
	# The bay's own semantic controls, addressed by role. "device" is the quiet
	# Human input-assignment readout (Doc 04 §7).
	match role:
		"kind":
			return kind_control
		"device":
			return input_control
		"difficulty":
			return difficulty_control
		"team":
			return team_control
	return null

func state_anchor(role: String) -> Control:
	match role:
		"kind":
			return _kind_anchor
		"device":
			return _input_anchor
		"difficulty":
			return _difficulty_anchor
		"team":
			return _team_anchor
	return null

func state_controls() -> Array:
	# Surviving (visible) state controls in authored visual order: the bay's
	# internal focus chain is built from exactly this list, so a hidden control
	# can never be a neighbour.
	var out: Array = []
	for role in ["kind", "device", "difficulty", "team"]:
		var control := state_control(role)
		if control != null and control.visible:
			out.append(control)
	return out

func state_roles() -> Array:
	var out: Array = []
	for role in ["kind", "device", "difficulty", "team"]:
		var control := state_control(role)
		if control != null and control.visible:
			out.append(role)
	return out

# --- focus signal (§6) -------------------------------------------------------

func set_focus_signal(on: bool) -> void:
	if _focus_rule != null:
		_focus_rule.visible = on

func focus_signal_visible() -> bool:
	return _focus_rule != null and _focus_rule.visible
