extends Control
# Story Fighter Select — the first production Story step (Doc 05 §85-106).
#
# This is deliberately separate from the Encounter Briefing. It owns the
# configured single-player roster, the selected fighter preview and the
# Story-select Back route; Briefing owns the encounter and its Start action.
# The selected fighter is emitted as a semantic request and MatchFlow writes it
# into MatchFlowState/AppState. No gameplay/debug setup is constructed here.

signal chosen(id: String)
signal continue_requested(id: String)
signal back_requested
signal exit_finished

const Tokens = preload("res://scripts/ui_tokens.gd")
const Roster = preload("res://scripts/roster.gd")
const PortraitData = preload("res://scripts/frontend/portrait_data.gd")
const TileScene = preload("res://scenes/components/FighterTile.tscn")
const RenderViewScript = preload("res://scripts/frontend/fighter_render_view.gd")
const Factory = preload("res://scripts/frontend/fighter_presentation_factory.gd")
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")

const TILE_W := 108.0      # authored MAXIMUM tile size (the strip never exceeds it)
const TILE_H := 86.0
const TILE_GAP := 12.0
# Owner corrective pass (Story composition): the roster strip is a FIXED column
# (authored 640 px wide). The authored six-fighter roster at the 108+12 pitch
# reached x 764 and the last tile — plate, portrait and its own name band —
# crossed into the preview zone where the "SELECTED FIGHTER" / fighter-name
# block starts (no gutter at all). The strip now FITS its column: the pitch
# shrinks to the widest pitch that keeps the whole row inside the strip (never
# past the authored maximum), and the tile keeps the reference aspect.
const TILE_MIN := 24.0
const EXIT_SECONDS := 13.0 / 60.0
const ENTER_SECONDS := 10.0 / 60.0
const EXIT_LOCK := 0.5

var _ids: Array[String] = []
var _tiles: Array = []
var _selected := ""
var _render_view: Control = null
var _exiting := false
var _input_lock := 0.0
var _ready_state := true

@onready var _field: Panel = $Field
@onready var _frame: Control = $ReferenceFrame
@onready var _title: Label = $ReferenceFrame/Header/Title
@onready var _step: Label = $ReferenceFrame/Header/StepLabel
@onready var _back: Button = $ReferenceFrame/Header/BackAction
@onready var _back_rail: Panel = $ReferenceFrame/Header/BackRail
@onready var _roster_strip: Control = $ReferenceFrame/SelectBody/RosterZone/RosterStrip
@onready var _fighter_name: Label = $ReferenceFrame/SelectBody/PreviewZone/FighterName
@onready var _preview_label: Label = $ReferenceFrame/SelectBody/PreviewZone/PreviewLabel
@onready var _render_holder: Control = $ReferenceFrame/SelectBody/PreviewZone/RenderHolder
@onready var _encounter: Label = $ReferenceFrame/SelectBody/BriefingZone/Encounter
@onready var _briefing_copy: Label = $ReferenceFrame/SelectBody/BriefingZone/Copy
@onready var _continue: Button = $ReferenceFrame/ContinueButton
@onready var _continue_rail: Panel = $ReferenceFrame/ContinueRail
@onready var _continue_top_rule: Panel = $ReferenceFrame/ContinueTopRule
@onready var _anchor_continue: Control = $ReferenceFrame/AnchorContinue

func _ready() -> void:
	theme = Tokens.make_theme()
	_style()
	_wire()
	_build_render_view()
	_refresh_selection()
	_refresh_focus_graph()

func _style() -> void:
	_field.add_theme_stylebox_override("panel", Tokens.flat(Tokens.BASE))
	for label in [_title, _fighter_name, _preview_label]:
		label.add_theme_font_override("font", Tokens.font("semibold"))
		label.add_theme_color_override("font_color", Tokens.CREAM)
	_step.add_theme_font_override("font", Tokens.font("medium"))
	_step.add_theme_color_override("font_color", Tokens.CREAM_DIM)
	_encounter.add_theme_font_override("font", Tokens.font("semibold"))
	_encounter.add_theme_color_override("font_color", Tokens.ACCENT)
	_briefing_copy.add_theme_font_override("font", Tokens.font("regular"))
	_briefing_copy.add_theme_color_override("font_color", Tokens.CREAM_DIM)
	_briefing_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for rule in [$ReferenceFrame/SelectBody/RuleTop, $ReferenceFrame/SelectBody/RuleMiddle]:
		rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE))
	Tokens.apply_styles(_back, {
		"normal": Tokens.flat(Color(0, 0, 0, 0)),
		"hover": Tokens.flat(Color(1, 1, 1, 0.05)),
		"pressed": Tokens.flat(Color(1, 1, 1, 0.09)),
		"focus": Tokens.flat(Color(0, 0, 0, 0)),
	})
	_back.add_theme_font_override("font", Tokens.font("semibold"))
	_back.add_theme_color_override("font_color", Tokens.CREAM_DIM)
	_back.add_theme_color_override("font_hover_color", Tokens.CREAM)
	_back.add_theme_color_override("font_focus_color", Tokens.CREAM)
	_back_rail.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
	_back_rail.hide()
	Tokens.apply_styles(_continue, {
		"normal": Tokens.flat(Tokens.SURFACE_1),
		"hover": Tokens.flat(Tokens.SURFACE_2),
		"pressed": Tokens.flat(Tokens.SURFACE_2),
		"focus": Tokens.flat(Tokens.SURFACE_2),
		"disabled": Tokens.flat(Tokens.SURFACE_1),
	})
	_continue.add_theme_font_override("font", Tokens.font("semibold"))
	_continue.add_theme_color_override("font_color", Tokens.CREAM)
	_continue.add_theme_color_override("font_hover_color", Tokens.CREAM)
	_continue.add_theme_color_override("font_focus_color", Tokens.CREAM)
	_continue.add_theme_color_override("font_disabled_color", Tokens.DISABLED)
	_continue_rail.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
	_continue_top_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
	_continue_top_rule.hide()

func _wire() -> void:
	_back.pressed.connect(_on_back_pressed)
	_back.focus_entered.connect(_on_back_focused)
	_back.focus_exited.connect(_on_back_unfocused)
	_continue.pressed.connect(_on_continue_pressed)
	_continue.focus_entered.connect(_on_continue_focused)
	_continue.focus_exited.connect(_on_continue_unfocused)
	if not FrontendInput.confirm_pressed.is_connected(_on_semantic_accept):
		FrontendInput.confirm_pressed.connect(_on_semantic_accept)
	if not FrontendInput.cancel_pressed.is_connected(_on_semantic_cancel):
		FrontendInput.cancel_pressed.connect(_on_semantic_cancel)

func _on_semantic_accept() -> void:
	if not is_visible_in_tree() or _exiting or not _ready_state:
		return
	if FrontendInput.confirm_source() == FrontendInput.SOURCE_MOUSE:
		return
	var focused := FrontendInput.focus_owner()
	var index: int = _tiles.find(focused)
	if index >= 0 and index < _ids.size():
		_select_by_id(_ids[index])
		return
	# Native Buttons own their semantic ui_accept activation.

func _on_semantic_cancel() -> void:
	if is_visible_in_tree() and not _exiting:
		_on_back_pressed()

func _on_back_pressed() -> void:
	back_requested.emit()

func _on_continue_pressed() -> void:
	if _selected == "" or _exiting:
		return
	continue_requested.emit(_selected)

func _on_back_focused() -> void:
	FocusGraph.track(self, _back)
	_back_rail.show()
	_back.add_theme_color_override("font_color", Tokens.CREAM)
	var hand = _hand()
	if hand != null and hand.mode == 1:
		hand.set_focus_target($ReferenceFrame/Header/AnchorBack)

func _on_back_unfocused() -> void:
	_back_rail.hide()
	_back.add_theme_color_override("font_color", Tokens.CREAM_DIM)

func _on_continue_focused() -> void:
	FocusGraph.track(self, _continue)
	_continue_top_rule.show()
	var hand = _hand()
	if hand != null and hand.mode == 1:
		hand.set_focus_target(_anchor_continue)

func _on_continue_unfocused() -> void:
	_continue_top_rule.hide()

func build(playable_ids: Array = []) -> void:
	_ids.clear()
	if playable_ids.is_empty():
		for id in Roster.ids():
			if str(id) != "ice_mage":
				_ids.append(str(id))
	else:
		for id in playable_ids:
			if str(id) != "":
				_ids.append(str(id))
	for tile in _tiles:
		if is_instance_valid(tile):
			tile.queue_free()
	_tiles.clear()
	# The strip's own column decides the row: the widest pitch that ends the
	# last tile at the strip's right edge, never wider than the authored one.
	var strip_w: float = _roster_strip.size.x
	if strip_w < 24.0:
		strip_w = 640.0                      # authored width before the layout ran
	var pitch: float = minf(TILE_W + TILE_GAP, (strip_w + TILE_GAP) / float(maxi(_ids.size(), 1)))
	var tile_w: float = maxf(pitch - TILE_GAP, TILE_MIN)
	var tile_h: float = maxf(tile_w * TILE_H / TILE_W, TILE_MIN)
	for i in _ids.size():
		var id := _ids[i]
		var tile = TileScene.instantiate()
		tile.name = "FighterTile%d" % i
		tile.position = Vector2(i * pitch, 0.0)
		_roster_strip.add_child(tile)
		tile.set_tile_size(Vector2(tile_w, tile_h))
		tile.setup(id, Roster.display_name(id).to_upper(), PortraitData.portrait_texture(id))
		tile.focus_mode = Control.FOCUS_ALL
		tile.tile_pressed.connect(_select_by_id)
		tile.focus_entered.connect(_on_tile_focused.bind(i))
		tile.mouse_entered.connect(_select_by_id.bind(id))
		_tiles.append(tile)
	if _selected == "" or not _ids.has(_selected):
		_selected = "turbofit" if _ids.has("turbofit") else (_ids[0] if not _ids.is_empty() else "")
	_refresh_selection()
	_refresh_focus_graph()

func open(selected_id: String = "") -> void:
	_exiting = false
	_input_lock = 0.0
	_ready_state = true
	visible = true
	_continue.text = "CONTINUE TO BRIEFING"
	_continue.disabled = false
	if selected_id != "":
		set_selected_id(selected_id)
	_refresh_selection()
	_refresh_focus_graph()
	var hand = _hand()
	if hand != null:
		hand.begin_screen("story_select")
		if hand.mode == 1 and not _tiles.is_empty():
			_tiles[_selected_index()].grab_focus()
			hand.set_focus_target(_tiles[_selected_index()].anchor())
	_entry()

func reset() -> void:
	_exiting = false
	_input_lock = 0.0
	_ready_state = true
	_continue.disabled = false
	_continue.text = "CONTINUE TO BRIEFING"
	_refresh_selection()
	_refresh_focus_graph()

func set_selected_id(id: String) -> void:
	_selected = id if id == "" or _ids.has(id) else ""
	_refresh_selection()

func select_fighter(id: String) -> void:
	_select_by_id(id)

func _select_by_id(id: String) -> void:
	if not _ids.has(id):
		return
	var changed := id != _selected
	_selected = id
	_refresh_selection()
	if changed:
		chosen.emit(id)

func _on_tile_focused(index: int) -> void:
	if index < 0 or index >= _tiles.size():
		return
	FocusGraph.track(self, _tiles[index])
	_select_by_id(_ids[index])
	var hand = _hand()
	if hand != null and hand.mode == 1:
		hand.set_focus_target(_tiles[index].anchor())

func _selected_index() -> int:
	var index := _ids.find(_selected)
	return index if index >= 0 else 0

func _refresh_selection() -> void:
	for i in _tiles.size():
		_tiles[i].set_candidate(_ids[i] == _selected)
	var valid := _selected != ""
	_fighter_name.text = Roster.display_name(_selected).to_upper() if valid else "SELECT A FIGHTER"
	_fighter_name.add_theme_color_override("font_color", Tokens.CREAM if valid else Tokens.CREAM_DIM)
	_continue.disabled = not valid
	if _render_view != null and is_instance_valid(_render_view):
		if valid:
			_render_view.set_subjects([_selected])
			_render_view.request_render()
		else:
			_render_view.clear_subjects()

func _build_render_view() -> void:
	_render_view = RenderViewScript.new()
	_render_view.name = "FighterRender"
	_render_holder.add_child(_render_view)
	_render_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_render_view.set_profile(RenderViewScript.PROFILE_PLAYER_BAY)
	_render_view.set_presentation_mode(Factory.MODE_LIVE_IDLE)

func _refresh_focus_graph() -> void:
	var chain: Array = []
	for tile in _tiles:
		chain.append(tile)
	chain.append(_continue)
	chain.append(_back)
	for i in chain.size():
		var control: Control = chain[i]
		control.focus_next = control.get_path_to(chain[(i + 1) % chain.size()])
		control.focus_previous = control.get_path_to(chain[(i - 1 + chain.size()) % chain.size()])
		control.focus_neighbor_left = control.get_path_to(chain[(i - 1 + chain.size()) % chain.size()])
		control.focus_neighbor_right = control.get_path_to(chain[(i + 1) % chain.size()])
	for i in _tiles.size():
		var tile: Control = _tiles[i]
		if i > 0:
			tile.focus_neighbor_left = tile.get_path_to(_tiles[i - 1])
		if i + 1 < _tiles.size():
			tile.focus_neighbor_right = tile.get_path_to(_tiles[i + 1])
		tile.focus_neighbor_top = tile.get_path_to(_back)
		tile.focus_neighbor_bottom = tile.get_path_to(_continue)
	if not _tiles.is_empty():
		_back.focus_neighbor_left = _back.get_path_to(_tiles[_tiles.size() - 1])
		_continue.focus_neighbor_top = _continue.get_path_to(_tiles[0])
	_back.focus_neighbor_bottom = _back.get_path_to(_continue)
	_ensure_focus_alive()

func _ensure_focus_alive() -> void:
	if not is_inside_tree():
		return
	var before := FrontendInput.focus_owner()
	var owner := FocusGraph.recover(get_viewport(), self, func() -> Control: return _continue if _selected == "" else _back)
	if owner != null and owner != before:
		var hand = _hand()
		if hand != null and hand.mode == 1:
			var anchor := focus_anchor_for(owner)
			if anchor != null:
				hand.set_focus_target(anchor)

func focus_anchor_for(control: Control) -> Control:
	if control == _continue:
		return _anchor_continue
	if control == _back:
		return $ReferenceFrame/Header/AnchorBack
	var index: int = _tiles.find(control)
	if index >= 0:
		return _tiles[index].anchor()
	return FocusGraph.anchor_of(control)

func roster_tiles() -> Array:
	return _tiles.duplicate()

func roster_ids() -> Array:
	return _ids.duplicate()

func selected_fighter_id() -> String:
	return _selected

func continue_button() -> Button:
	return _continue

func back_button() -> Button:
	return _back

func render_view() -> Control:
	return _render_view

func is_exiting() -> bool:
	return _exiting

func get_input_lock() -> float:
	return _input_lock

func play_exit() -> void:
	if _exiting:
		return
	_exiting = true
	_input_lock = EXIT_LOCK
	var tween := create_tween()
	tween.tween_property(_frame, "modulate:a", 0.0, EXIT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: exit_finished.emit())

func _process(delta: float) -> void:
	if _input_lock > 0.0:
		_input_lock = maxf(_input_lock - delta, 0.0)

func _entry() -> void:
	_frame.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_frame, "modulate:a", 1.0, ENTER_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _hand():
	var cursor = get_node_or_null("/root/Cursor")
	if cursor == null or cursor.hand == null:
		return null
	return cursor.hand
