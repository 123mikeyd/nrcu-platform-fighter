extends Control
# Character Select — corrective package Doc 04 (Character Select corrective
# spec) + Doc 01 §2/§4/§5 (fresh defaults, device ownership, token grammar).
#
# This script is controller/state orchestration, NOT layout construction:
#   * fixed composition lives in scenes/character_select.tscn
#     (header · roster field · ready band · four player stations)
#   * roster tiles are data-driven instances of scenes/components/FighterTile.tscn
#   * player stations are PlayerBay component instances
#   * tokens are PlayerTokenView instances, one per player, with their own FSM
#   * the mode control is the shared SegmentedChoice component
#
# Ownership rules:
#   * NO fighter is ever preselected: the screen renders whatever state it is
#     given and never seeds a fighter (Doc 01 §2). P1 Human/P2 CPU/P3-P4 Empty
#     are the MatchFlowState fresh defaults; returning from SSS/Results restores
#     the state instead of re-applying defaults.
#   * candidate fighter != committed fighter. Hover/focus only changes the
#     candidate; only a confirm (click / semantic accept) edits the state.
#   * fighter selection NEVER silently turns an EMPTY slot into a Human one
#     (Doc 04 §6): kind is changed in the PlayerBay.
#   * token state is screen-local and complete
#     (UNASSIGNED/CARRIED/RETURNING/PLACING/PLACED): the committed fighter
#     lives in the persistent state.
#   * the hand carries the active player's SEPARATE token while browsing a
#     fighter (Doc 01 §5); the carry pose is the clean grab/pinch hand and no
#     player identity is baked into hand art (ledger C-008).
#   * Ready is decided by the ONE validation authority (MatchFlowState, reached
#     through the screen's selection mirror) — this screen holds no rule set of
#     its own (Doc 02 §2).

signal ready_requested
signal back_requested
signal exit_finished

const Tokens = preload("res://scripts/ui_tokens.gd")
const Roster = preload("res://scripts/roster.gd")
const PortraitData = preload("res://scripts/frontend/portrait_data.gd")
const TileScene = preload("res://scenes/components/FighterTile.tscn")
const TokenScene = preload("res://scenes/components/PlayerTokenView.tscn")
const TokenView = preload("res://scripts/frontend/player_token_view.gd")
# Doc 03 §6/§13: authored anchors + authored topology + focus recovery.
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")
# The ONE validation authority, used for its pure palette-resolution rule too.
const State = preload("res://scripts/match_flow_state.gd")

const COLS := 10                 # Doc 04 §5.1: 10 columns, up to 3 rows
const TILE_W := 108.0            # Doc 04 §5.2 reference tile
const TILE_H := 82.0
const GAP := 8.0
const ROW_PITCH := 90.0
const GRID_W := 1168.0
const ENTER_GUARD := 0.30
const EXIT_SECONDS := 14.0 / 60.0
const REVEAL_HEADER := 12.0 / 60.0
const REVEAL_ROSTER := 16.0 / 60.0
const REVEAL_BAYS := 18.0 / 60.0
# Roster interaction envelope: populated cells + internal gutters (ledger
# C-004/C-005). Leaving it ends the carry immediately.
const ROSTER_GUTTER := 10.0
# Authored token motion (Doc 01 §5 "short authored placement motion"; ledger
# C-007 alternative A — PLACING/RETURNING are REAL presentation states).
const PLACE_SECONDS := 0.14
const RETURN_SECONDS := 0.12
const KINDS := ["human", "bot", "empty"]
const DIFFICULTIES := ["easy", "normal", "hard"]
const KEYBOARD_LABELS := ["KEYBOARD 1", "KEYBOARD 2"]
const CONNECT_CONTROLLER := "CONNECT CONTROLLER"
# The two authored header segments of the shared SegmentedChoice (Doc 04 §8).
const MODE_SEGMENTS := [
	{"name": "ModeFree", "text": "FREE-FOR-ALL", "x": 0.0, "width": 220.0},
	{"name": "ModeTeams", "text": "TEAMS", "x": 250.0, "width": 130.0},
]

enum Phase { ENTERING, IDLE, EXITING }

var cursor: Control

var _state
var _cards: Array = []            # [{id, name, texture}]
var _tiles: Array = []            # FighterTile nodes
var _bays: Array = []             # PlayerBay nodes
var _tokens: Array = []           # PlayerTokenView per player
var _active := 0                  # active player index
var _candidate := -1              # hovered/focused tile index
var _token_state: Array = []      # TokenView.State per player
var _token_busy: Array = []       # players with an authored token motion in flight
var _token_tweens: Dictionary = {}  # player -> the ONE in-flight motion tween
var _carried_by := -1
var _seeding_focus := false
var _focus_check_pending := false
var _phase: Phase = Phase.ENTERING
var _guard := 0.0
var _focus_rules: Dictionary = {}     # header control -> structural focus signal
var _pads_override: Array = []        # injected device availability (tests/evidence)
var _pads_override_set := false

@onready var _frame: Control = $ReferenceFrame
@onready var _field_panel: Panel = $Field
@onready var _header: Control = $ReferenceFrame/Header
@onready var _title: Label = $ReferenceFrame/Header/Title
@onready var _mode_choice = $ReferenceFrame/Header/ModeControl
@onready var _back: Button = $ReferenceFrame/Header/BackAction
@onready var _field: Control = $ReferenceFrame/RosterField
@onready var _field_rule: Panel = $ReferenceFrame/RosterField/FieldRule
@onready var _grid: Control = $ReferenceFrame/RosterField/FighterGrid
@onready var _stations: Control = $ReferenceFrame/PlayerStations
@onready var _ready_band = $ReferenceFrame/ReadyBand
var _mode_free: Control
var _mode_teams: Control
var _token_layer: Control

func _ready() -> void:
	theme = Tokens.make_theme()
	var root = get_node_or_null("/root/Cursor")
	if root != null:
		cursor = root.hand
	_field_panel.add_theme_stylebox_override("panel", Tokens.flat(Tokens.BASE))
	_title.add_theme_color_override("font_color", Tokens.CREAM)
	_field_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE))
	Tokens.apply_styles(_back, Tokens.row_styles())
	_back.add_theme_color_override("font_color", Tokens.CREAM)
	_back.pressed.connect(_on_back_pressed)
	if cursor != null and not cursor.modality_changed.is_connected(_on_modality_changed):
		cursor.modality_changed.connect(_on_modality_changed)
	# Doc 04 §8: the mode control is the SHARED SegmentedChoice (never ad-hoc
	# focusable labels). Left click activates by mouse; the semantic ui_accept
	# path activates the focused segment.
	_mode_choice.setup(MODE_SEGMENTS)
	_mode_free = _mode_choice.segment(0)
	_mode_teams = _mode_choice.segment(1)
	_mode_choice.changed.connect(_set_mode)
	# Header destinations: each one owns an authored anchor and a structural
	# focus signal, so the atomic focus-enter holds here too (Doc 03 §6).
	_build_header_focus_rules()
	for control in [_back, _mode_free, _mode_teams]:
		(control as Control).focus_entered.connect(_on_header_focused.bind(control))
		(control as Control).focus_exited.connect(_on_header_unfocused.bind(control))
	_field.mouse_exited.connect(_leave_field)
	# Token layer: tokens live here while unassigned (TokenHomeLayer); the
	# cursor layer takes over while one is carried (Doc 04 §4 — every parent is
	# explicit, no hidden cursor-owned leftovers).
	_token_layer = Control.new()
	_token_layer.name = "TokenHomeLayer"
	_token_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_token_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_token_layer)
	for i in 4:
		var token = TokenScene.instantiate()
		token.name = "PlayerToken" + str(i)
		token.visible = false
		_token_layer.add_child(token)
		token.set_player(i)
		_tokens.append(token)
		_token_state.append(TokenView.State.UNASSIGNED)
	for i in 4:
		var bay = _stations.get_node("PlayerBay" + str(i))
		bay.setup(i)
		bay.focus_mode = Control.FOCUS_ALL
		bay.focus_entered.connect(_on_bay_focused.bind(i))
		bay.focus_exited.connect(_on_bay_unfocused.bind(i))
		bay.bay_activated.connect(_on_bay_activated)
		bay.kind_clicked.connect(_on_kind_clicked)
		bay.input_clicked.connect(_on_input_clicked)
		bay.difficulty_clicked.connect(_on_difficulty_clicked)
		bay.team_clicked.connect(_on_team_clicked)
		# Nested state controls: each one reports focus so the atomic
		# focus-enter (logical focus + control emphasis + hand target) holds
		# for them too (Doc 03 §6).
		for role in ["kind", "device", "difficulty", "team"]:
			var state_control: Button = bay.state_control(role)
			if state_control != null:
				state_control.focus_entered.connect(_on_bay_state_focused.bind(i, role))
				state_control.focus_exited.connect(_on_bay_unfocused.bind(i))
		_bays.append(bay)
		if cursor != null:
			cursor.add_target(bay)
	_ready_band.ready_pressed.connect(_on_ready_pressed)
	_ready_band.focus_mode = Control.FOCUS_ALL
	_ready_band.focus_entered.connect(_on_ready_band_focused)
	_ready_band.focus_exited.connect(_on_ready_band_unfocused)
	_ready_band.apply_reference_width(Tokens.DESIGN.x)
	_ready_band.position.x = (Tokens.DESIGN.x - _ready_band.size.x) * 0.5
	_ready_band.hide_band()
	if cursor != null:
		cursor.add_target(_back)
		cursor.add_target(_ready_band)
		cursor.add_target(_mode_free)
		cursor.add_target(_mode_teams)
	# Doc 03 §7/§11: the screen activates through the semantic input service —
	# never through ad-hoc key decoding in _unhandled_key_input() (which cannot
	# see a JoypadButton event at all).
	if not FrontendInput.confirm_pressed.is_connected(_on_semantic_accept):
		FrontendInput.confirm_pressed.connect(_on_semantic_accept)
	if not FrontendInput.cancel_pressed.is_connected(_on_semantic_cancel):
		FrontendInput.cancel_pressed.connect(_on_semantic_cancel)
	# Doc 04 §9: the approved controller Start invokes the SAME Ready semantic
	# action (and only while no candidate/carry is unresolved).
	if not FrontendInput.start_pressed.is_connected(_on_start_shortcut):
		FrontendInput.start_pressed.connect(_on_start_shortcut)
	# Doc 03 §10: hotplug refreshes device validity (never a stale read).
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)

func build(cards: Array = []) -> void:
	# Roster data (id/name, optional texture). Empty = the real roster.
	if cards.is_empty():
		cards = []
		for id in Roster.ids():
			cards.append({"id": str(id), "name": Roster.display_name(str(id)).to_upper()})
	_cards = []
	for entry in cards:
		var id := str(entry.get("id", ""))
		_cards.append({
			"id": id,
			"name": str(entry.get("name", Roster.display_name(id).to_upper())),
			"texture": entry.get("texture", PortraitData.portrait_texture(id)),
		})
	for tile in _tiles:
		if is_instance_valid(tile):
			tile.queue_free()
	_tiles.clear()
	# Tokens may be parented to tiles being rebuilt: bring them home first.
	for token in _tokens:
		if is_instance_valid(token):
			if token.get_parent() != _token_layer:
				token.reparent(_token_layer)
			token.visible = false
	for i in _token_state.size():
		_token_state[i] = TokenView.State.UNASSIGNED
		_kill_token_motion(i)
	_carried_by = -1
	_token_busy.clear()
	var n := _cards.size()
	for i in n:
		var entry: Dictionary = _cards[i]
		var tile = TileScene.instantiate()
		tile.name = "FighterTile" + str(i)
		tile.position = _tile_position(i, n)
		tile.tile_pressed.connect(_on_tile_pressed)
		tile.mouse_entered.connect(_on_tile_entered.bind(i))
		_grid.add_child(tile)
		# Components resolve their child nodes on tree entry: configure after.
		tile.set_tile_size(Vector2(TILE_W, TILE_H))
		tile.setup(str(entry["id"]), str(entry["name"]), entry.get("texture"))
		# Keyboard/controller parity: the tile root is focusable and reports
		# focus so the focus hand settles on its authored anchor (Step 0 §12).
		tile.focus_mode = Control.FOCUS_ALL
		tile.focus_entered.connect(_on_tile_focused.bind(i))
		tile.focus_exited.connect(_on_tile_unfocused.bind(i))
		_tiles.append(tile)
		if cursor != null:
			cursor.add_target(tile)
	_wire_focus_graph()
	_refresh()

func _tile_position(index: int, count: int) -> Vector2:
	# Fixed-density field: rows are centered inside the reserved 10-column
	# field and the tile size never changes with the roster count.
	var row: int = index / COLS
	var col: int = index % COLS
	var in_row: int = mini(count - row * COLS, COLS)
	var row_w: float = in_row * TILE_W + maxf(in_row - 1, 0) * GAP
	var x0: float = (GRID_W - row_w) * 0.5
	return Vector2(x0 + col * (TILE_W + GAP), row * ROW_PITCH)

# --- lifecycle -----------------------------------------------------------
func open_with(state) -> void:
	_state = state
	_active = 0
	_candidate = -1
	_carried_by = -1
	_token_busy.clear()
	for i in 4:
		_kill_token_motion(i)
	_phase = Phase.ENTERING
	_guard = ENTER_GUARD
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if cursor != null:
		cursor.visible = true
		cursor.begin_screen("css")
	_sync_devices()
	_refresh()
	_enter_choreography()
	_seed_focus()

func reopen() -> void:
	# Back from the stage page: every commit survives; transient carry does not.
	_phase = Phase.IDLE
	_guard = 0.25
	_candidate = -1
	for i in 4:
		_kill_token_motion(i)
	_clear_carry()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if cursor != null:
		cursor.visible = true
		cursor.begin_screen("css")
	_sync_devices()
	_refresh()
	_seed_focus()

func reset() -> void:
	_phase = Phase.IDLE
	_guard = 0.0
	_candidate = -1
	_clear_carry()
	_sync_devices()
	_refresh()

func play_exit() -> void:
	if _phase == Phase.EXITING:
		return
	_phase = Phase.EXITING
	# The Ready state is gone with the screen: the approved Start shortcut goes
	# with it (Doc 03 §2).
	FrontendInput.set_controller_start_approved(false)
	_clear_carry()
	_ready_band.hide_band()
	var tween := create_tween()
	tween.tween_property(_frame, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: exit_finished.emit())

func is_exiting() -> bool:
	return _phase == Phase.EXITING

# --- THE validation authority (Doc 02 §2) --------------------------------
func validation_error() -> String:
	# The screen holds NO rule set: it asks the MatchFlowState-backed selection
	# mirror for the ONE player-facing message ("" = may proceed). Ready, the
	# ReadyBand visibility and the launch gate all answer from this.
	if _state != null and _state.has_method("validation_error"):
		return str(_state.validation_error())
	return ""

func ready_allowed() -> bool:
	return _state != null and validation_error() == ""

func _enter_choreography() -> void:
	_header.modulate.a = 0.0
	_grid.modulate.a = 0.0
	_stations.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(_header, "modulate:a", 1.0, REVEAL_HEADER).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_grid, "modulate:a", 1.0, REVEAL_ROSTER).set_delay(0.04).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_stations, "modulate:a", 1.0, REVEAL_BAYS).set_delay(0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_frame, "modulate:a", 1.0, 0.18)

func _seed_focus() -> void:
	# Keyboard/controller: deterministic starting point. Never for a mouse user.
	if cursor == null or cursor.is_mouse_active():
		return
	if _tiles.is_empty():
		return
	var idx: int = _candidate if _candidate >= 0 else 0
	_seeding_focus = true
	_tiles[idx].grab_focus()
	_seeding_focus = false
	if cursor.mode == 1:
		cursor.set_focus_target(_tiles[idx].anchor())

# --- device availability (Doc 03 §10 / Doc 01 §4) ------------------------
func set_connected_pads(pads: Array) -> void:
	# Deterministic device availability for tests/evidence (never the live OS
	# list). The SAME list is handed to the validation authority.
	_pads_override = pads.duplicate()
	_pads_override_set = true
	refresh_devices()

func available_pads() -> Array:
	if _pads_override_set:
		return _pads_override.duplicate()
	return Input.get_connected_joypads()

func refresh_devices() -> void:
	# Re-derives every Human slot's assignment validity from the CURRENT device
	# list (hotplug) and re-gates Ready through the ONE authority, plus the Doc
	# 04 §7 "CONNECT CONTROLLER" resolution: a pad-only Human slot claims the
	# first available unclaimed pad as soon as one exists.
	_sync_devices()
	_reclaim_unassigned_pads()
	_refresh()

func _reclaim_unassigned_pads() -> void:
	if _state == null:
		return
	for i in 4:
		if slot_kind(i) != "human" or slot_input_valid(i):
			continue
		if slot_device(i) < 0 and not slot_allows_keyboard(i):
			var choices := device_choices(i)
			if not choices.is_empty():
				_state.slots[i]["device"] = int(choices[0])

func _sync_devices() -> void:
	if _state != null and _state.has_method("set_connected_pads"):
		_state.set_connected_pads(available_pads())

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	if _pads_override_set:
		return   # injected availability owns the answer (tests/evidence)
	refresh_devices()

func slot_kind(player: int) -> String:
	if _state == null or player < 0 or player >= _state.slots.size():
		return "empty"
	return str(_state.slots[player].get("kind", "human"))

func slot_device(player: int) -> int:
	# Legacy device encoding: -1 = "no pad" (Keyboard 1/2 on P1/P2, "connect a
	# controller" on P3/P4); >= 0 = pad id.
	return int(_state.slots[player].get("device", -1)) if _state != null else -1

func slot_allows_keyboard(player: int) -> bool:
	# Doc 01 §4: P1/P2 may use Keyboard 1/2; P3/P4 are pad-only.
	return player >= 0 and player < 2

func claimed_pads(except_player: int = -1) -> Array:
	var out: Array = []
	for other in 4:
		if other == except_player or slot_kind(other) != "human":
			continue
		var device := slot_device(other)
		if device >= 0 and not out.has(device):
			out.append(device)
	return out

func device_choices(player: int) -> Array:
	# The assignments a Human slot may take without ever duplicating a pad
	# another Human owns (Doc 01 §4 "no pad assigned to two Human slots").
	var out: Array = []
	if slot_allows_keyboard(player):
		out.append(-1)
	for pad in available_pads():
		if not (int(pad) in claimed_pads(player)):
			out.append(int(pad))
	return out

func slot_input_valid(player: int) -> bool:
	if slot_kind(player) != "human":
		return true
	var device := slot_device(player)
	if device < 0:
		return slot_allows_keyboard(player)
	return device in available_pads()

func slot_input_text(player: int) -> String:
	if slot_kind(player) != "human":
		return ""
	var device := slot_device(player)
	if device < 0:
		if slot_allows_keyboard(player):
			return KEYBOARD_LABELS[player]
		return CONNECT_CONTROLLER
	var pads: Array = available_pads()
	if not (device in pads):
		return CONNECT_CONTROLLER
	return "PAD " + str(pads.find(device) + 1)

# --- state refresh -------------------------------------------------------
func _refresh() -> void:
	if _state == null:
		return
	for i in _bays.size():
		_apply_bay_state(i)
		_bays[i].set_active(i == _active)
	# Doc 04 §8: selection presentation belongs to the shared component; the
	# screen only writes the state-driven selection.
	_mode_choice.set_selected(int(_state.mode))
	_recompute_tokens()
	if ready_allowed():
		_ready_band.show_band()
		_wire_ready_neighbors(true)
	else:
		_ready_band.hide_band()
		_wire_ready_neighbors(false)
	# §2: controller Start is an approved FOCUS shortcut only while READY is
	# actually valid on this screen (the same validity the band shows).
	FrontendInput.set_controller_start_approved(ready_allowed() and _ready_band.is_shown())
	# §13: the bay-internal topology depends on which state controls survive in
	# this configuration, and §6 recovery runs after every state change so a
	# control that just disappeared never keeps the focus.
	_wire_bay_state_graph()
	_ensure_focus_alive()

func _apply_bay_state(i: int) -> void:
	# The committed presentation of one station (candidate previews are applied
	# on top of it by _update_active_preview).
	var slot: Dictionary = _state.slots[i]
	var kind := str(slot.get("kind", "human"))
	var fid := str(slot.get("character", ""))
	var display := Roster.display_name(fid).to_upper() if fid != "" else ""
	_bays[i].set_slot_state(kind, fid if kind != "empty" else "", display,
		str(slot.get("difficulty", "normal")), int(slot.get("team", 0)), _state.mode,
		slot_input_text(i), slot_input_valid(i))
	_bays[i].set_palette_variant(_resolved_palette(i))

func _resolved_palette(player: int) -> int:
	# Doc 04 §14: the resolved duplicate-fighter variant comes from the
	# authority (never a screen-local rule).
	if _state != null and _state.has_method("resolved_palette"):
		return int(_state.resolved_palette(player))
	return player

func _recompute_tokens() -> void:
	# UNASSIGNED players hide their token at home; committed players rest on
	# their tile. Tokens with an authored motion in flight are left alone.
	for player in 4:
		if player == _carried_by or _token_busy.has(player):
			continue
		if not is_instance_valid(_tokens[player]):
			continue
		var slot: Dictionary = _state.slots[player]
		var fid := str(slot.get("character", ""))
		if str(slot.get("kind", "human")) == "empty" or fid == "":
			_home_token(player)
			continue
		var tile_index := _tile_index_of(fid)
		if tile_index < 0:
			_home_token(player)
			continue
		_place_token(player, tile_index, false)
	_update_candidate_visuals()

func _home_token(player: int) -> void:
	# Doc 04 §4 / ledger C-009: an unassigned token ALWAYS goes back to the
	# explicit home layer and hides — no cursor-owned leftovers.
	_token_state[player] = TokenView.State.UNASSIGNED
	var token = _tokens[player]
	if token == null or not is_instance_valid(token):
		return
	if token.get_parent() != _token_layer:
		token.reparent(_token_layer)
	token.visible = false
	token.settle()

func _place_token(player: int, tile_index: int, animated: bool) -> void:
	# Deterministic slot ordinals: everyone committed to this tile shares it,
	# never exact overlap (Doc 04 §16).
	var committed: Array = []
	for other in 4:
		if other == _carried_by:
			continue
		var slot: Dictionary = _state.slots[other]
		if str(slot.get("kind", "human")) != "empty" and str(slot.get("character", "")) == str(_cards[tile_index]["id"]):
			committed.append(other)
	var ordinal: int = committed.find(player)
	if ordinal < 0:
		ordinal = 0
	var tile = _tiles[tile_index]
	var token = _tokens[player]
	var start_global: Vector2 = token.global_position   # before any reparent
	if token.get_parent() != tile.token_layer():
		token.reparent(tile.token_layer())
	tile.place_token_view(token, ordinal, committed.size())
	token.visible = true
	if animated:
		var end: Vector2 = token.position          # the authored slot
		token.global_position = start_global       # back to the carried spot
		_animate_token(player, token, end, TokenView.State.PLACING, TokenView.State.PLACED)
		return
	_token_state[player] = TokenView.State.PLACED
	token.set_state(TokenView.State.PLACED)
	token.settle()

func _animate_token(player: int, token: Control, end_local: Vector2, en_route: int, arrival: int) -> void:
	# A REAL presentation motion (ledger C-007 alternative A): the token keeps
	# its current visual spot and eases into its authored target, then settles.
	_kill_token_motion(player)
	_token_busy.append(player)
	_token_state[player] = en_route
	token.set_state(en_route)
	token.visible = true
	var tween := create_tween()
	_token_tweens[player] = tween
	tween.tween_property(token, "position", end_local, PLACE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		_token_tweens.erase(player)
		_token_busy.erase(player)
		if not is_instance_valid(token):
			return
		if _carried_by == player or _token_state[player] != en_route:
			return   # re-lifted or superseded: never stomp the newer state
		_token_state[player] = arrival
		token.set_state(arrival)
		token.settle()
		_recompute_tokens())

func _tile_index_of(id: String) -> int:
	for i in _cards.size():
		if str(_cards[i]["id"]) == id:
			return i
	return -1

# --- token carry (Doc 01 §5 grammar) -------------------------------------
func _on_tile_entered(index: int) -> void:
	if cursor != null and not cursor.is_mouse_active():
		return
	if _phase == Phase.EXITING:
		return
	_set_candidate(index)
	_begin_carry(_active)

func _on_tile_focused(index: int) -> void:
	# Keyboard/controller parity: focus on a tile means candidate + focus hand
	# at the authored anchor + the active player's token in carry presentation.
	if index < 0 or index >= _tiles.size():
		return
	FocusGraph.track(self, _tiles[index])
	if cursor == null or cursor.mode != 1:
		return  # mouse clicks may focus too; that path is _on_tile_entered
	if _phase != Phase.IDLE or _state == null:
		return
	_set_candidate(index)
	if index < _tiles.size():
		cursor.set_focus_target(_tiles[index].anchor())
	if _seeding_focus:
		return  # programmatic entry seed: candidate + hand only, no carry
	_begin_carry(_active)

func _on_tile_unfocused(_index: int) -> void:
	# Doc 04 §3 / ledger C-006: carry reacts to the SEMANTIC focus region.
	# Focus leaving the roster for Mode/Back/Ready/bays/bay child controls exits
	# through the ONE shared cancellation transition.
	_focus_check_pending = true
	call_deferred("_settle_focus_region")

func _settle_focus_region() -> void:
	if not _focus_check_pending:
		return
	_focus_check_pending = false
	if _phase == Phase.EXITING or _state == null:
		return
	var owner := FrontendInput.focus_owner()
	if owner != null and _tiles.has(owner):
		return          # focus moved inside the roster: the candidate follows
	_cancel_roster_interaction()

func _on_modality_changed(is_mouse: bool) -> void:
	# Mouse -> focus switch while the screen is up: seed the logical selection
	# so the first keyboard confirm commits the candidate (Doc 00 §12.3).
	if is_mouse or not is_visible_in_tree():
		return
	var vp := get_viewport()
	if vp != null and vp.gui_get_focus_owner() != null:
		return  # focus is already established — never stomp it
	if _tiles.is_empty() or _phase == Phase.EXITING:
		return
	_seed_focus()

func _on_ready_band_focused() -> void:
	FocusGraph.track(self, _ready_band)
	if _ready_band != null:
		_ready_band.set_focus_signal(true)
	if cursor == null or cursor.mode != 1:
		return
	cursor.set_focus_target(_ready_band.anchor())

func _on_ready_band_unfocused() -> void:
	if _ready_band != null:
		_ready_band.set_focus_signal(false)

func _wire_ready_neighbors(band_shown: bool) -> void:
	# Doc 04 19/20A: the ready transition is keyboard/controller reachable.
	if _tiles.is_empty():
		return
	var n := _tiles.size()
	for i in n:
		var tile = _tiles[i]
		var col: int = i % COLS
		if band_shown:
			tile.focus_neighbor_bottom = tile.get_path_to(_ready_band)
		else:
			var below: int = i + COLS
			if below < n:
				tile.focus_neighbor_bottom = tile.get_path_to(_tiles[below])
			else:
				tile.focus_neighbor_bottom = tile.get_path_to(_bays[col % 4])
	if band_shown:
		_ready_band.focus_neighbor_top = _ready_band.get_path_to(_tiles[0])
		_ready_band.focus_neighbor_bottom = _ready_band.get_path_to(_bays[0])

func _on_bay_focused(index: int) -> void:
	if index < 0 or index >= _bays.size():
		return
	FocusGraph.track(self, _bays[index])
	_bays[index].set_focus_signal(true)
	if cursor == null or cursor.mode != 1:
		return
	cursor.set_focus_target(_bays[index].anchor())

func _on_bay_unfocused(index: int) -> void:
	# Only when focus really left the bay: moving between a bay's own nested
	# controls must not flicker its focus signal.
	if index < 0 or index >= _bays.size():
		return
	var bay = _bays[index]
	var focused := FrontendInput.focus_owner()
	if focused == bay:
		return
	for role in ["kind", "device", "difficulty", "team"]:
		if bay.state_control(role) == focused:
			return
	bay.set_focus_signal(false)

func _begin_carry(player: int) -> void:
	# CARRIED => carried_by == active player, always (ledger C-026).
	if player != _active:
		return
	if _carried_by == player:
		return
	if _carried_by >= 0:
		_return_carried()
	_carried_by = player
	# A token that is still easing home is RE-LIFTED: its motion tween is
	# cancelled so the carried placement is never dragged back by it.
	_kill_token_motion(player)
	_token_state[player] = TokenView.State.CARRIED
	_tokens[player].visible = true
	_tokens[player].set_state(TokenView.State.CARRIED)
	if cursor != null:
		cursor.set_carry(_tokens[player])
	FrontendEvents.emit_token_pickup(player)

func _return_carried() -> void:
	# Cancel/leave: the token RETURNS home through a real motion (ledger C-007):
	# to its committed tile when it has one, else home + hide.
	if _carried_by < 0:
		return
	var player := _carried_by
	_carried_by = -1
	if cursor != null:
		cursor.clear_carry()
	var slot: Dictionary = _state.slots[player]
	var fid := str(slot.get("character", ""))
	var tile_index := _tile_index_of(fid) if str(slot.get("kind", "human")) != "empty" else -1
	if tile_index >= 0:
		var tile = _tiles[tile_index]
		var token = _tokens[player]
		var start_global: Vector2 = token.global_position
		if token.get_parent() != tile.token_layer():
			token.reparent(tile.token_layer())
		var committed: Array = []
		for other in 4:
			if other == _carried_by:
				continue
			var other_slot: Dictionary = _state.slots[other]
			if str(other_slot.get("kind", "human")) != "empty" and str(other_slot.get("character", "")) == fid:
				committed.append(other)
		var ordinal: int = maxi(committed.find(player), 0)
		tile.place_token_view(token, ordinal, maxi(committed.size(), 1))
		var end: Vector2 = token.position
		token.global_position = start_global
		_animate_token(player, token, end, TokenView.State.RETURNING, TokenView.State.PLACED)
	else:
		_return_token_home(player)

func _kill_token_motion(player: int) -> void:
	# One authored motion per player at a time: a new transition supersedes the
	# one in flight instead of racing it.
	var tween = _token_tweens.get(player, null)
	if tween is Tween and tween.is_valid():
		tween.kill()
	_token_tweens.erase(player)
	_token_busy.erase(player)

func _return_token_home(player: int) -> void:
	# Unassigned: ease back to the player's station and hide at home (Doc 01 §5
	# "token returns home and hides").
	var token = _tokens[player]
	if token == null or not is_instance_valid(token):
		return
	var start_global: Vector2 = token.global_position
	if token.get_parent() != _token_layer:
		token.reparent(_token_layer)
	token.global_position = start_global
	_kill_token_motion(player)
	_token_busy.append(player)
	_token_state[player] = TokenView.State.RETURNING
	token.set_state(TokenView.State.RETURNING)
	var home_global: Vector2 = _bays[player].get_global_rect().position + Vector2(26.0, 26.0)
	var tween := create_tween()
	_token_tweens[player] = tween
	tween.tween_property(token, "global_position", home_global, RETURN_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_token_tweens.erase(player)
		_token_busy.erase(player)
		if not is_instance_valid(token):
			return
		if _carried_by == player or _token_state[player] != TokenView.State.RETURNING:
			return   # re-lifted or already resolved: never stomp the newer state
		_home_token(player))

func _clear_carry() -> void:
	if _carried_by >= 0:
		var player := _carried_by
		_carried_by = -1
		_token_state[player] = TokenView.State.UNASSIGNED
		_kill_token_motion(player)
		var token = _tokens[player]
		if token != null and is_instance_valid(token):
			if token.get_parent() != _token_layer:
				token.reparent(_token_layer)
			token.visible = false
	if cursor != null:
		cursor.clear_carry()

func _cancel_roster_interaction() -> void:
	# THE one shared cancellation transition (ledger C-005/C-006): candidate
	# clears, the carry returns home.
	_set_candidate(-1)
	_return_carried()

func _cancel_player_interaction(player: int) -> void:
	# A state change that invalidates a player's ownership (kind -> Empty,
	# active-player switch) resolves its candidate/carry FIRST (ledger C-039).
	if player == _active and _candidate >= 0:
		_set_candidate(-1)
	if _carried_by == player:
		_return_carried()

func _leave_field() -> void:
	# The visual field's own exit is the belt-and-braces path; the roster
	# interaction envelope (below) is the deterministic authority.
	_cancel_roster_interaction()

func roster_bounds() -> Rect2:
	# Populated roster cells + internal gutters (ledger C-004): the semantic
	# carry boundary, never a passive visual container.
	var out := Rect2()
	var first := true
	for tile in _tiles:
		if not is_instance_valid(tile):
			continue
		var r: Rect2 = tile.get_global_rect().grow(ROSTER_GUTTER)
		if first:
			out = r
			first = false
		else:
			out = out.merge(r)
	return out

func _enforce_roster_envelope() -> void:
	# While carrying with the MOUSE, "is the pointer still in the roster?" is
	# answered from the rendered hotspot every frame (ledger C-004/C-005): the
	# carry can never survive leaving the actual populated roster envelope.
	if _carried_by < 0 or cursor == null or cursor.mode == 1:
		return   # FOCUS mode: the semantic focus region owns cancellation
	if _tiles.is_empty():
		return
	if roster_bounds().has_point(cursor.hotspot):
		return
	_cancel_roster_interaction()

func _set_candidate(index: int) -> void:
	if index == _candidate:
		return
	_candidate = index
	_update_candidate_visuals()
	if cursor != null and cursor.mode == 1 and index >= 0:
		cursor.set_focus_target(_tiles[index].anchor())

func _update_candidate_visuals() -> void:
	for i in _tiles.size():
		_tiles[i].set_candidate(i == _candidate)
	_update_active_preview()

func _update_active_preview() -> void:
	# Doc 04 §12 / ledger C-047: the active bay large-previews the candidate
	# while browsing; when the candidate clears (cancel/leave/commit) the bay
	# returns to its committed fighter — or to blank.
	if _active < 0 or _active >= _bays.size() or _state == null:
		return
	if _candidate < 0 or _candidate >= _cards.size():
		_apply_bay_state(_active)
		return
	var entry: Dictionary = _cards[_candidate]
	_bays[_active].preview_fighter(str(entry["id"]), str(entry["name"]), _resolved_palette(_active))

# --- semantic actions ----------------------------------------------------
func _on_tile_pressed(id: String) -> void:
	if _phase != Phase.IDLE or _guard > 0.0 or _state == null:
		return
	var player := _active
	var slot: Dictionary = _state.slots[player]
	if str(slot.get("kind", "human")) == "empty":
		# Doc 04 §6: fighter selection NEVER silently changes EMPTY -> Human.
		# Kind is changed in the PlayerBay.
		return
	var tile_index := _tile_index_of(id)
	if tile_index < 0:
		return
	var was_placed: bool = _token_state[player] == TokenView.State.PLACED
	slot["character"] = id           # THE commit: candidate -> committed
	var from_carry: bool = _carried_by == player
	if from_carry:
		_carried_by = -1
		if cursor != null:
			cursor.clear_carry()
	FrontendEvents.emit_token_place(player)
	if from_carry or was_placed:
		# PLACING: the authored placement motion eases the token from where it
		# is (the carried spot, or the tile it was committed to) into the new
		# tile slot; the refresh must not snap it there first. Ledger C-007 A:
		# PLACING is a REAL presentation state, not bookkeeping.
		_token_busy.erase(player)
		_token_busy.append(player)
		_token_state[player] = TokenView.State.PLACING
		_tokens[player].set_state(TokenView.State.PLACING)
		_refresh()
		_token_busy.erase(player)
		_place_token(player, tile_index, true)
	else:
		_refresh()

func _on_bay_activated(index: int) -> void:
	if _phase == Phase.EXITING:
		return
	if index == _active:
		_refresh()
		return
	# Changing the active player is a semantic boundary: the PREVIOUS player's
	# carry is resolved before the active player changes (ledger C-026), so
	# CARRIED always means carried_by == active player.
	_cancel_player_interaction(_active)
	_active = index                  # explicit only (Doc 04 §10A)
	_refresh()

func _on_kind_clicked(index: int) -> void:
	if _state == null or _phase == Phase.EXITING:
		return
	var slot: Dictionary = _state.slots[index]
	var at: int = KINDS.find(str(slot.get("kind", "human")))
	_set_slot_kind(index, KINDS[(at + 1) % KINDS.size()])

func _set_slot_kind(player: int, kind: String) -> void:
	# ONE transition for every state change that invalidates fighter/device
	# ownership (ledger C-039).
	if _state == null:
		return
	var slot: Dictionary = _state.slots[player]
	if str(slot.get("kind", "human")) == kind:
		return
	_cancel_player_interaction(player)
	slot["kind"] = kind
	if kind == "empty":
		slot["character"] = ""      # EMPTY never owns a committed fighter
		slot["device"] = -1
	elif kind == "bot":
		slot["device"] = -1         # input assignment is hidden for a CPU
	else:
		slot["device"] = _default_device_for(player)
	_refresh()

func _default_device_for(player: int) -> int:
	# A Human slot always starts from a VALID assignment when one exists:
	# Keyboard N on P1/P2, the first unclaimed connected pad on P3/P4 (else the
	# slot reads CONNECT CONTROLLER and cannot ready — Doc 04 §7).
	if slot_allows_keyboard(player):
		return -1
	for pad in available_pads():
		if not (int(pad) in claimed_pads(player)):
			return int(pad)
	return -1

func _on_input_clicked(index: int) -> void:
	if _state == null or _phase == Phase.EXITING:
		return
	var slot: Dictionary = _state.slots[index]
	if str(slot.get("kind", "human")) != "human":
		return
	var choices := device_choices(index)
	if choices.is_empty():
		return
	var at: int = choices.find(int(slot.get("device", -1)))
	slot["device"] = int(choices[(at + 1) % choices.size()])
	_refresh()

func _on_difficulty_clicked(index: int) -> void:
	if _state == null:
		return
	var slot: Dictionary = _state.slots[index]
	var at: int = DIFFICULTIES.find(str(slot.get("difficulty", "normal")))
	slot["difficulty"] = DIFFICULTIES[(at + 1) % DIFFICULTIES.size()]
	_refresh()

func _on_team_clicked(index: int) -> void:
	if _state == null:
		return
	var slot: Dictionary = _state.slots[index]
	slot["team"] = 1 - int(slot.get("team", 0))
	_refresh()

func _set_mode(mode: int) -> void:
	if _state == null or _phase == Phase.EXITING:
		return
	_state.mode = 1 if int(mode) == 1 else 0
	if _state.mode == 1:
		_seed_teams_if_unset()
	_refresh()

func _seed_teams_if_unset() -> void:
	# Team mode: participating players without a side take the shipped default
	# distribution (match_config.default_slots parity: slot index decides). A
	# 1v1 Team A vs Team B is then valid without extra clicks (Doc 01 §3).
	for i in 4:
		var slot: Dictionary = _state.slots[i]
		if str(slot.get("kind", "human")) == "empty":
			continue
		if int(slot.get("team", -1)) < 0:
			slot["team"] = i % 2

func _on_ready_pressed() -> void:
	if ready_allowed():
		ready_requested.emit()

func _on_start_shortcut() -> void:
	# Doc 04 §9: the optional approved controller Start invokes the EXACT same
	# Ready semantic action, is ignored while a candidate/carry is unresolved,
	# and only ever fires when validation passes.
	if not is_visible_in_tree() or _phase == Phase.EXITING:
		return
	if _candidate >= 0 or _carried_by >= 0:
		return
	_on_ready_pressed()

func _on_back_pressed() -> void:
	_clear_carry()
	back_requested.emit()

func _process(delta: float) -> void:
	if _guard > 0.0:
		_guard = maxf(_guard - delta, 0.0)
	if _phase == Phase.ENTERING and _guard <= 0.0:
		_phase = Phase.IDLE
	_enforce_roster_envelope()

# --- keyboard / controller: the semantic path (Doc 03 §7/§11/§13) ---------
func _wire_focus_graph() -> void:
	var n := _tiles.size()
	if n == 0:
		return
	for i in n:
		var tile = _tiles[i]
		var col: int = i % COLS
		var row: int = i / COLS
		if col > 0:
			tile.focus_neighbor_left = tile.get_path_to(_tiles[i - 1])
		if col < COLS - 1 and i + 1 < n:
			tile.focus_neighbor_right = tile.get_path_to(_tiles[i + 1])
		if row > 0:
			tile.focus_neighbor_top = tile.get_path_to(_tiles[i - COLS])
		else:
			tile.focus_neighbor_top = tile.get_path_to(_back)
		var below: int = i + COLS
		if below < n:
			tile.focus_neighbor_bottom = tile.get_path_to(_tiles[below])
		else:
			tile.focus_neighbor_bottom = tile.get_path_to(_bays[col % 4])
	for i in _bays.size():
		var bay = _bays[i]
		bay.focus_neighbor_left = bay.get_path_to(_bays[(i - 1 + 4) % 4])
		bay.focus_neighbor_right = bay.get_path_to(_bays[(i + 1) % 4])
		bay.focus_neighbor_top = bay.get_path_to(_tiles[mini(i, n - 1)])
	_back.focus_neighbor_bottom = _back.get_path_to(_tiles[n - 1])
	_back.focus_neighbor_left = _back.get_path_to(_mode_teams)
	_back.focus_neighbor_right = NodePath()
	_mode_free.focus_neighbor_right = _mode_free.get_path_to(_mode_teams)
	_mode_free.focus_neighbor_left = NodePath()
	_mode_free.focus_neighbor_top = NodePath()
	_mode_teams.focus_neighbor_left = _mode_teams.get_path_to(_mode_free)
	_mode_teams.focus_neighbor_right = _mode_teams.get_path_to(_back)
	_mode_teams.focus_neighbor_top = NodePath()
	_mode_free.focus_neighbor_bottom = _mode_free.get_path_to(_tiles[n - 1])
	_mode_teams.focus_neighbor_bottom = _mode_teams.get_path_to(_tiles[n - 1])
	# §13: explicit Tab order too — the header destinations, then the roster,
	# then the stations. Never the engine's tree order.
	var chain: Array = [_mode_free, _mode_teams, _back]
	chain.append_array(_tiles)
	chain.append_array(_bays)
	FocusGraph.chain(chain, true)

func _wire_bay_state_graph() -> void:
	# §13 "child bay controls stay within that bay until a directional exit":
	# a bay's kind/device/difficulty/team controls cycle among themselves
	# (up/down), and every boundary direction exits into the bay control itself.
	# Which controls participate depends on the current configuration (Human
	# input readout, CPU difficulty row, teams), so the graph is re-authored on
	# every refresh.
	for i in _bays.size():
		var bay = _bays[i]
		var controls: Array = bay.state_controls()
		if controls.is_empty():
			FocusGraph.clear(bay, [&"bottom"])
			continue
		var count := controls.size()
		for j in count:
			var control: Control = controls[j]
			var up_target: Control = controls[j - 1] if j > 0 else bay
			var down_target: Control = controls[j + 1] if j + 1 < count else bay
			FocusGraph.wire(control, up_target, [&"top", &"previous"])
			FocusGraph.wire(control, down_target, [&"bottom", &"next"])
			FocusGraph.wire(control, bay, [&"left", &"right"])
		# Entry/exit through the bay control: down enters the bay's controls,
		# the first control's up (above) leaves them again.
		FocusGraph.wire(bay, controls[0], [&"bottom"])

func _on_bay_state_focused(index: int, role: String) -> void:
	# §6 atomic focus-enter for a nested state control: the logical focus is
	# the engine's (the control owns it), the emphasis is the control's own
	# focus style and the hand target is its authored CursorAnchor.
	if index < 0 or index >= _bays.size():
		return
	var bay = _bays[index]
	FocusGraph.track(self, bay.state_control(role))
	bay.set_focus_signal(true)
	if cursor != null and cursor.mode == 1:
		cursor.set_focus_target(bay.state_anchor(role))

func _build_header_focus_rules() -> void:
	# Structural focus signal for the header destinations (Doc 07 §8 / Doc 03
	# §6: never color alone). The BackAction is a Button and already carries its
	# own focus style.
	_focus_rules.clear()
	for control in [_mode_free, _mode_teams]:
		var rule := Panel.new()
		rule.name = "FocusRule"
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rule.position = Vector2(control.position.x, 42.0)
		rule.size = Vector2(maxf(control.size.x, 32.0), 2.0)
		rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
		rule.visible = false
		control.get_parent().add_child(rule)
		_focus_rules[control] = rule

func _on_header_focused(control: Control) -> void:
	FocusGraph.track(self, control)
	for key in _focus_rules.keys():
		(_focus_rules[key] as Panel).visible = key == control
	var anchor := FocusGraph.anchor_of(control)
	if anchor != null and cursor != null and cursor.mode == 1:
		cursor.set_focus_target(anchor)

func _on_header_unfocused(control: Control) -> void:
	var rule = _focus_rules.get(control, null)
	if rule != null and is_instance_valid(rule):
		(rule as Panel).visible = false

func _ensure_focus_alive() -> void:
	# §6: if the focused control disappears or gets disabled, focus moves to the
	# correct surviving semantic neighbour and the hand retargets immediately.
	if not is_inside_tree():
		return
	var before := FrontendInput.focus_owner()
	var owner := FocusGraph.recover(get_viewport(), self, func() -> Control:
		if ready_allowed() and _ready_band.is_shown():
			return _ready_band
		if not _tiles.is_empty():
			return _tiles[clampi(_active, 0, _tiles.size() - 1)]
		return _back)
	if owner != null and owner != before and cursor != null and cursor.mode == 1:
		var anchor := focus_anchor_for(owner)
		if anchor != null:
			cursor.set_focus_target(anchor)

func focus_anchor_for(control: Control) -> Control:
	# The authored hand target of a focusable control on this screen (Doc 03 §6).
	# Icons: the control's own CursorAnchor, with the bay state controls and the
	# bay/roster/band components resolved through their components.
	if control == null:
		return null
	for i in _bays.size():
		var bay = _bays[i]
		for role in ["kind", "device", "difficulty", "team"]:
			if bay.state_control(role) == control:
				return bay.state_anchor(role)
	if control == _ready_band:
		return _ready_band.anchor()
	var t: int = _tiles.find(control)
	if t >= 0:
		return _tiles[t].anchor()
	var b: int = _bays.find(control)
	if b >= 0:
		return _bays[b].anchor()
	return FocusGraph.anchor_of(control)

func _on_semantic_accept() -> void:
	# §7: the focused control is activated through the semantic action path.
	# A mouse confirm is skipped here — the control's own mouse path owns it,
	# and this handler only exists so keyboard/pad accepts reach the CUSTOM
	# controls (FighterTile / PlayerBay / ReadyBand / SegmentedChoice), which
	# the engine cannot activate by itself.
	if not is_visible_in_tree() or _state == null or _phase == Phase.EXITING:
		return
	if FrontendInput.confirm_source() == FrontendInput.SOURCE_MOUSE:
		return
	var focused := FrontendInput.focus_owner()
	if focused == null:
		if ready_allowed():
			ready_requested.emit()
		return
	var t: int = _tiles.find(focused)
	if t >= 0 and _phase == Phase.IDLE:
		_on_tile_pressed(str(_tiles[t].fighter_id))
		return
	var b: int = _bays.find(focused)
	if b >= 0 and _phase == Phase.IDLE:
		_on_bay_activated(b)
		return
	if focused == _ready_band and ready_allowed():
		_on_ready_pressed()
		return
	var segment: int = _mode_choice.segment_index_of(focused)
	if segment >= 0:
		_mode_choice.activate(segment)
		return
	# Native Buttons (BackAction, the bay state readouts) activate through the
	# engine's own ui_accept path for KEYBOARD. The project's InputMap carries no
	# pad binding for ui_accept, so a PAD accept activates the focused Button
	# here instead — the same semantic action, still one implementation, and
	# never a double fire (the engine ignores pad A for ui_accept).
	if focused is BaseButton and FrontendInput.confirm_source() == FrontendInput.SOURCE_PAD:
		var button := focused as BaseButton
		if not button.disabled:
			button.pressed.emit()
		return

func _on_semantic_cancel() -> void:
	# §11 Back matrix: CSS ui_cancel -> Main.
	if not is_visible_in_tree() or _phase == Phase.EXITING:
		return
	_on_back_pressed()

# --- test surface --------------------------------------------------------
func get_tiles() -> Array:
	return _tiles

func get_carried_by() -> int:
	return _carried_by

func get_bays() -> Array:
	return _bays

func get_active() -> int:
	return _active

func get_candidate() -> int:
	return _candidate

func get_phase() -> int:
	return _phase

func token_state(player: int) -> int:
	return int(_token_state[player]) if player >= 0 and player < _token_state.size() else -1

func token_view(player: int) -> Control:
	return _tokens[player] if player >= 0 and player < _tokens.size() else null

func token_home_layer() -> Control:
	return _token_layer

func get_mode_control() -> Control:
	return _mode_choice

func get_ready_band() -> Control:
	return _ready_band

func get_input_guard() -> float:
	return _guard
