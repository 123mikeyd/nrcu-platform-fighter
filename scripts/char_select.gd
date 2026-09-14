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
#   * THE ONE LIFT RULE (Doc 01 §5 / Doc 04 §12): a chip leaves its tile for the
#     hand ONLY through the owner's explicit actions, and every one of them ends
#     in ONE implementation and ONE end state —
#       (a) A / left-click on its own tile -> DE-SELECT: the pick is TAKEN BACK
#           into the hand through _take_back_committed (the staged cancel's
#           stage 2). Owner requirement; this deliberately supersedes the
#           former explicit no-op on this path;
#       (b) A / left-click on a DIFFERENT tile  -> the commit MOVES (re-pick);
#       (c) ui_cancel / Back (B)                -> the staged take-back.
#     Hover (the tile's own mouse entry), the candidate preview, focus browsing,
#     the modality switch and the roster envelope may only cancel an IN-FLIGHT
#     carry: they never lift a committed chip (owner report: hovering another
#     fighter after a commit put the committed chip back into the hand). It is
#     enforced in ONE place — _begin_carry, gated on _has_committed_pick, the
#     single source of the committed-pick question.
#   * ui_cancel (Esc / pad B / the Back control) is STAGED: it cancels a carried
#     chip, then takes the ACTIVE player's committed chip back into the hand
#     (the screen stays — the player can re-place or re-browse), then clears a
#     pending candidate, and only then follows the BACK route. Focus/pointer
#     movement may only cancel an IN-FLIGHT carry: it never takes a committed
#     chip back. The BACK route itself belongs to the flow, which resolves the
#     screen's ENTRY ORIGIN (Main, or Results when the CSS was PUSHed from it).
#   * fighter selection NEVER silently turns an EMPTY slot into a Human one
#     (Doc 04 §6): kind is changed in the PlayerBay.
#   * token state is screen-local and complete
#     (UNASSIGNED/CARRIED/RETURNING/PLACING/PLACED): the committed fighter
#     lives in the persistent state.
#   * the hand carries the active player's SEPARATE token while browsing a
#     fighter (Doc 01 §5); the carry pose is the clean grab/pinch hand and no
#     player identity is baked into hand art (ledger C-008).
#   * the drawn POSE is one rule, single-sourced in _cursor_pose_visual(): CARRY
#     while a chip is in the hand; HOVER (the empty pinch) only on the hold the
#     hand ADDRESSES — the tile that holds the active player's committed chip,
#     or any browsed hold while that player has no committed pick; the ordinary
#     pointer everywhere else. It is read from the screen's state (focus/pointer
#     + the committed picks), never from where the sprite happens to be flying.
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

# --- Doc 04 §10 adaptive composition (OCCUPIED rows only) -------------------
# Reference 1280x720: ~56 px safe left/right, tile 108x82, roster gap 8-10,
# first row top y 92-98, row pitch 90-92, Ready at occupied_bottom + 18,
# PlayerBays bottom y ~690, bay height ~420/330/245 for 1/2/3 occupied rows.
# Authored capacity stays 10x3 = 30 (Doc 10: "Capacity remains 10x3; invisible
# rows do not consume current geometry"). Beyond capacity the locked rule is
# "Do not shrink tiles to fit roster growth" (Doc 04 §10): growth past the
# reserved field is a paging/category design, exactly as Doc 01 §11 prescribes
# for >9 stages — never shrinking tiles and never reserved invisible rows.
const COLS := 10                 # 10 columns
const MAX_ROWS := 3              # authored capacity: 10x3 = 30 fighters
const TILE_W := 108.0            # reference tile (never shrinks)
const TILE_H := 82.0
const GAP := 8.0                 # roster gap 8-10
const ROW_PITCH := 90.0          # tile + gap (reference pitch 90-92)
const GRID_W := 1168.0
const ROSTER_TOP := 96.0         # first roster row top (reference 92-98)
const FIELD_BREATH := 8.0        # the roster field's own quiet lower margin
const FIELD_RULE_OFFSET := 4.0   # the separating rail under the occupied rows
const READY_GAP := 18.0          # Ready sits at occupied_bottom + 18
const BAYS_BOTTOM := 690.0       # the stations' stable lower line
# The locked bay heights (Doc 04 §10 / ledger C-019): occupied rows decide.
const BAY_HEIGHTS := {1: 420.0, 2: 330.0, 3: 245.0}
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
	# §10: the composition is applied once the stations exist, so the shipped
	# roster already renders with its occupied-row geometry (no review frame
	# with the dead reserved rows).
	apply_composition()
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
		# The fixed reference tile is also the FLOOR: roster growth never
		# shrinks a tile (Doc 01 §8 / Doc 04 §10).
		tile.set_tile_size(Vector2(TILE_W, TILE_H), Vector2(TILE_W, TILE_H))
		tile.setup(str(entry["id"]), str(entry["name"]), entry.get("texture"))
		# Keyboard/controller parity: the tile root is focusable and reports
		# focus so the focus hand settles on its authored anchor (Step 0 §12).
		tile.focus_mode = Control.FOCUS_ALL
		tile.focus_entered.connect(_on_tile_focused.bind(i))
		tile.focus_exited.connect(_on_tile_unfocused.bind(i))
		_tiles.append(tile)
		if cursor != null:
			cursor.add_target(tile)
	# Doc 04 §10: the composition follows the OCCUPIED row count, so the roster
	# field, the Ready slot and the four stations resolve BEFORE the topology is
	# re-derived from the resolved geometry (C-050/C-051).
	apply_composition()
	_rebuild_focus_topology()
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

# --- adaptive composition (Doc 01 §8, Doc 04 §10, ledger C-019/C-051) ------
func occupied_rows(count := -1) -> int:
	# ONLY the rows the current roster actually occupies: ceil(n / 10), bounded
	# by the authored 10x3 capacity. Never a permanent 3-row envelope.
	var n: int = _cards.size() if count < 0 else count
	return clampi(int(ceil(float(n) / float(COLS))), 1, MAX_ROWS)

func roster_capacity() -> int:
	return COLS * MAX_ROWS

func occupied_bottom(rows: int) -> float:
	# The upper composition's occupied lower edge: first row top + the rows
	# that exist (row pitch = tile + gap).
	return ROSTER_TOP + float(maxi(rows, 1) - 1) * ROW_PITCH + TILE_H

func bay_height_for_rows(rows: int) -> float:
	# The locked Doc 04 §10 table: 1 row -> 420, 2 rows -> 330, 3 rows -> 245.
	return float(BAY_HEIGHTS[clampi(rows, 1, MAX_ROWS)])

func bay_top_for_rows(rows: int) -> float:
	# The stations keep a STABLE lower line (Doc 04 §10 "PlayerBays bottom y
	# ~690"); the occupied rows decide how tall they get.
	return BAYS_BOTTOM - bay_height_for_rows(rows)

func apply_composition() -> void:
	# THE adaptive composition (Doc 01 §8 / Doc 04 §10): the upper roster and
	# the lower stations are ONE composition — only the occupied roster rows
	# consume vertical height, tiles keep their fixed readable size, the Ready
	# band sits directly under the occupied roster in a RESERVED slot (so the
	# stations never jump when it appears) and the stations take the authored
	# height for the occupied row count.
	if not is_node_ready():
		return
	var rows := occupied_rows()
	var roster_h := float(rows - 1) * ROW_PITCH + TILE_H
	_field.size = Vector2(_field.size.x, roster_h + FIELD_BREATH)
	_grid.size = Vector2(GRID_W, roster_h)
	_field_rule.position = Vector2(0.0, roster_h + FIELD_RULE_OFFSET)
	_field_rule.size = Vector2(GRID_W, 1.0)
	var bottom := occupied_bottom(rows)
	var height := bay_height_for_rows(rows)
	var top := bay_top_for_rows(rows)
	_ready_band.apply_reference_width(Tokens.DESIGN.x)
	_ready_band.position = Vector2((Tokens.DESIGN.x - _ready_band.size.x) * 0.5, bottom + READY_GAP)
	_stations.position = Vector2(_stations.position.x, top)
	_stations.size = Vector2(_stations.size.x, height)
	for bay in _bays:
		bay.size = Vector2(bay.size.x, height)

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
	# The hand's POSE is part of the entry state: sync it now (never on the next
	# input event — the owner-reported stale ordinary pose on CSS entry).
	_sync_cursor_pose()

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
	_sync_cursor_pose()

func reset() -> void:
	_phase = Phase.IDLE
	_guard = 0.0
	_candidate = -1
	_clear_carry()
	_sync_devices()
	_refresh()
	_sync_cursor_pose()

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
	else:
		_ready_band.hide_band()
	# C-050/C-051: the directional topology follows the RESOLVED geometry and
	# the current Ready visibility (the bottom roster row exits into the band
	# while it is shown, else into the nearest station).
	_rebuild_focus_topology()
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
	# The tile's own mouse entry — the pointer HOVER path the owner uses. Hover
	# only ever moves the CANDIDATE/preview; whether it also picks a chip up is
	# decided by the ONE lift rule inside _begin_carry, so a committed chip can
	# never be lifted just because the pointer crossed another fighter.
	if cursor != null and not cursor.is_mouse_active():
		return
	if _phase == Phase.EXITING:
		return
	_set_candidate(index)
	_begin_carry(_active)

func _on_tile_focused(index: int) -> void:
	# Keyboard/controller parity: focus on a tile means candidate + focus hand
	# at the authored anchor + the active player's token in carry presentation.
	# The same ONE lift rule applies here (focus browsing is not a lift).
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
	# THE ONE LIFT RULE (Doc 01 §5 / Doc 04 §12) — this is the ONLY place a chip
	# can leave a tile for the hand, so the gate lives here and every lift path
	# (tile mouse entry / focus browse / entry or modality seeding) inherits it:
	# a player who already owns a COMMITTED pick has no liftable chip. The
	# sanctioned lifts are (a) the own-tile DE-SELECT and (c) the staged
	# take-back — both take the commit back in _take_back_committed, which clears
	# the commit BEFORE asking here — and (b) A / left-click on another tile,
	# handled by _on_tile_pressed as a direct re-place. Hover / candidate preview
	# / focus browsing may only cancel an IN-FLIGHT carry of an UNCOMMITTED chip.
	if _has_committed_pick(player):
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
	_sync_cursor_pose()
	FrontendEvents.emit_token_pickup(player)

func _return_carried() -> void:
	# Cancel/leave: the token RETURNS home through a real motion (ledger C-007):
	# to its committed tile when it has one, else home + hide.
	# Under the ONE lift rule a carried chip is ALWAYS uncommitted (a committed
	# pick is lifted only by the staged take-back, which clears the commit first),
	# so the committed-tile branch below is a defensive fallback for a state
	# written from outside the screen — never the browsing path.
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
	_sync_cursor_pose()

func _cursor_in_roster() -> bool:
	# The hand's authoritative hotspot sits inside the populated roster envelope
	# (the same boundary the carry uses): the mouse arm of the pose rule below
	# asks this before it asks which tile the pointer is on, so a pointer in the
	# internal gutters keeps the roster interaction alive.
	if cursor == null or _tiles.is_empty():
		return false
	return roster_bounds().has_point(cursor.hotspot)

# --- THE POSE RULE (single source: nothing else writes cursor.set_visual_mode)
#
# Doc 03 §5/§6 + the carry-art contract: the hand's POSE is a function of THIS
# screen's state at the moment it is read — on entry, on every candidate/focus/
# target change and every frame while the screen owns the cursor — never of the
# sprite's own flight position and never of the next input event (owner report:
# the hand sat on the first roster tile drawing the ordinary pose until the
# first controller input, and — after a commit — the pinch followed the pointer
# across every tile).
#
#   CARRY   — a chip is IN the hand (carried_by >= 0): the approved grip.
#   HOVER   — the empty pinch: the hand addresses a hold it does not hold —
#             the tile that HOLDS the active player's committed chip (the one
#             tile the staged take-back returns the chip to), or any browsed
#             hold while the active player has NO committed pick (the entry
#             seed, focus browsing, a resting pointer).
#   REGULAR — the ordinary pointer: everywhere else. A committed chip makes its
#             OWN tile the only pinch target, so hovering any other fighter is
#             plain navigation.
func _sync_cursor_pose() -> void:
	if cursor == null or not cursor.has_method("set_visual_mode"):
		return
	cursor.set_visual_mode(_cursor_pose_visual())

func _cursor_pose_visual() -> int:
	if _carried_by >= 0:
		return 1
	var hold := _cursor_hold_tile()
	if hold < 0:
		return 0
	if _has_committed_pick(_active) and not _tile_holds_active_pick(hold):
		return 0
	return 2

func _cursor_hold_tile() -> int:
	# WHICH hold is the hand addressing? -1 = none (the hand is off the roster).
	#   FOCUS — the tile the engine's focus owns: the hand is authored onto that
	#           tile's anchor (the entry seed, then every navigation step). The
	#           answer is the screen's STATE, never the sprite's flight position,
	#           so the pose is right the moment the screen is visible.
	#   MOUSE — the pointer IS the hand: the tile under the authoritative
	#           hotspot, else the tile the pointer last entered (its gutters).
	if cursor == null or _tiles.is_empty():
		return -1
	if cursor.mode == 1:
		var owner := FrontendInput.focus_owner()
		if owner != null:
			var focused: int = _tiles.find(owner)
			if focused >= 0:
				return focused
		return _candidate
	if not _cursor_in_roster():
		return -1
	return _tile_under_hotspot()

func _tile_under_hotspot() -> int:
	if cursor == null:
		return -1
	for i in _tiles.size():
		if is_instance_valid(_tiles[i]) and _tiles[i].get_global_rect().has_point(cursor.hotspot):
			return i
	return _candidate

func _tile_holds_active_pick(index: int) -> bool:
	# Does the ACTIVE player's committed chip rest on this tile? (The tile the
	# staged take-back returns the chip to — the pinch's own target.)
	if _state == null or index < 0 or index >= _cards.size():
		return false
	var slot: Dictionary = _state.slots[_active]
	if str(slot.get("kind", "empty")) == "empty":
		return false
	return str(slot.get("character", "")) == str(_cards[index]["id"])

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
	# The hand's pose follows the candidate/token state at the moment it changes
	# (never at the next input event).
	_sync_cursor_pose()

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
	# (a) A / LEFT-CLICK on the tile that already owns this player's committed
	# chip: DE-SELECT. The pick is TAKEN BACK into the hand through the SAME
	# implementation as the staged cancel's stage 2 (_take_back_committed), so
	# A on the own tile, the left-click on the own tile and B end in exactly ONE
	# end state: the commit is undone, the chip rides the carry layer, the tile
	# stays the candidate and the screen stays put (owner requirement — it
	# deliberately supersedes the former explicit no-op on this path).
	if _has_committed_pick(player) and str(slot.get("character", "")) == id and _carried_by != player:
		_take_back_committed(player)
		return
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
	# The visible Back control and the semantic ui_cancel are the SAME staged
	# cancellation (Doc 04 staged cancel): the control must not bypass stages
	# 1-3 and jump straight to the route.
	_cancel_or_back()

func _cancel_or_back() -> void:
	# ONE press peels exactly ONE layer (Doc 04 Character Select grammar):
	#   1. a CARRIED (uncommitted) chip -> the token FSM's return path;
	#   2. else the ACTIVE player's COMMITTED pick -> back into the hand;
	#   3. else the pending candidate/preview -> cleared (back to the roster);
	#   4. only then the BACK route (whose origin the flow owns).
	# A screen that is still entering/exiting keeps the pre-existing FLAT
	# behaviour: no stage is peeled while its own transition is in flight.
	if _phase == Phase.ENTERING or _phase == Phase.EXITING:
		_flat_back()
		return
	if _carried_by >= 0:
		_return_carried()
		return
	if _has_committed_pick(_active):
		_take_back_committed(_active)
		return
	if _candidate >= 0:
		_set_candidate(-1)
		return
	_flat_back()

func _flat_back() -> void:
	# The pre-existing flat behaviour: drop the transient carry and request the
	# BACK route. The FLOW resolves the screen's entry origin, never this screen.
	_clear_carry()
	back_requested.emit()

func _has_committed_pick(player: int) -> bool:
	# THE single source of the COMMITTED-pick question, and therefore of the ONE
	# lift rule: a non-EMPTY player with a fighter in the persistent state owns a
	# committed chip, and no hover / candidate preview / focus browse / modality
	# switch / roster envelope may take it off its tile. Every explicit de-select
	# path — the staged cancel (stage 2, _take_back_committed) and the own-tile
	# A / left-click (a, _on_tile_pressed) — and the carry gate in _begin_carry
	# read THIS, so "is this chip liftable?" can never be answered two different
	# ways. A candidate is only a preview and never counts (Doc 04 §12).
	if _state == null or player < 0 or player >= _state.slots.size():
		return false
	var slot: Dictionary = _state.slots[player]
	if str(slot.get("kind", "empty")) == "empty":
		return false
	return str(slot.get("character", "")) != ""

func _take_back_committed(player: int) -> void:
	# THE one de-select — the staged cancel's stage 2 AND the own-tile DE-SELECT
	# (a: A / left-click on the tile that owns this player's committed chip) both
	# route here, so every way to unselect ends in exactly one implementation and
	# one end state: UNDO the commit and put the chip back in the hand — the
	# token FSM's carry presentation over the taken-back fighter, with that tile
	# left as the candidate so the player can re-place it or keep browsing. The
	# screen NEVER leaves on this stage (the stage-4 route owns that).
	if _state == null or player < 0 or player != _active:
		return
	var slot: Dictionary = _state.slots[player]
	var tile_index := _tile_index_of(str(slot.get("character", "")))
	slot["character"] = ""
	_begin_carry(player)          # lifts the token out of its placed slot
	_set_candidate(tile_index)    # the taken-back fighter stays the candidate
	_refresh()

func _process(delta: float) -> void:
	if _guard > 0.0:
		_guard = maxf(_guard - delta, 0.0)
	if _phase == Phase.ENTERING and _guard <= 0.0:
		_phase = Phase.IDLE
	_enforce_roster_envelope()
	if is_visible_in_tree():
		# The hand's pose tracks THIS screen's state every frame while the screen
		# owns the cursor: a pointer coming to rest on a roster tile or a focus
		# target change is reflected immediately, never at the next input event.
		# A hidden screen never writes to the shared cursor.
		_sync_cursor_pose()

# --- keyboard / controller: the semantic path (Doc 03 §7/§11/§13) ---------
# C-050/C-051: the directional topology is RE-DERIVED from the resolved
# geometry (Control rect centers) after the adaptive layout settles.
#
#   within a row        left/right = the adjacent tile in the same row (no wrap)
#   between rows        up/down    = the nearest x-center in the adjacent
#                                    OCCUPIED row
#   top roster row      up         = the nearest header destination by x
#                                    (mode choice / Back only where spatially
#                                    sensible)
#   bottom roster row   down       = Ready while it is shown, else the nearest
#                                    station by x
#   station             up         = the nearest bottom-row tile by x
#   Ready               up / down  = the nearest bottom-row tile / station
#
# No index arithmetic and no modulo mapping decide a neighbour.
func _row_controls(row: Array) -> Array:
	var out: Array = []
	for i in row:
		if is_instance_valid(_tiles[i]):
			out.append(_tiles[i])
	return out

func _nearest_by_x(controls: Array, x: float) -> Control:
	var best: Control = null
	var best_d := INF
	for control in controls:
		if control == null or not is_instance_valid(control):
			continue
		var d: float = absf(control.get_global_rect().get_center().x - x)
		if d < best_d:
			best_d = d
			best = control
	return best

func _roster_rows() -> Array:
	# The OCCUPIED rows, read off the resolved tile rectangles: rows are groups
	# of tiles whose vertical centers agree (two rows are a full pitch apart).
	var ordered: Array = []
	for i in _tiles.size():
		if is_instance_valid(_tiles[i]):
			ordered.append(i)
	ordered.sort_custom(func(a, b):
		var ca: Vector2 = _tiles[a].get_global_rect().get_center()
		var cb: Vector2 = _tiles[b].get_global_rect().get_center()
		if absf(ca.y - cb.y) > 1.0:
			return ca.y < cb.y
		return ca.x < cb.x)
	var rows: Array = []
	var current: Array = []
	for i in ordered:
		if current.is_empty():
			current.append(i)
			continue
		var row_y: float = _tiles[current[0]].get_global_rect().get_center().y
		var y: float = _tiles[i].get_global_rect().get_center().y
		if absf(y - row_y) > TILE_H * 0.5:
			rows.append(current)
			current = []
		current.append(i)
	if not current.is_empty():
		rows.append(current)
	return rows

func _wire_to(control: Control, neighbour: Control, direction: StringName) -> void:
	if control == null or not is_instance_valid(control):
		return
	if neighbour == null or not is_instance_valid(neighbour):
		FocusGraph.clear(control, [direction])
		return
	FocusGraph.wire(control, neighbour, [direction])

func _rebuild_focus_topology() -> void:
	var n := _tiles.size()
	if n == 0 or _bays.is_empty():
		return
	var rows := _roster_rows()
	if rows.is_empty():
		return
	var top_row: Array = rows[0]
	var bottom_row: Array = rows[rows.size() - 1]
	var band_shown: bool = _ready_band.is_shown()
	# The roster: in-row runs, then the adjacent occupied rows by x-center.
	for r in rows.size():
		var row: Array = rows[r]
		for j in row.size():
			var tile: Control = _tiles[row[j]]
			if j > 0:
				_wire_to(tile, _tiles[row[j - 1]], &"left")
			else:
				FocusGraph.clear(tile, [&"left"])
			if j + 1 < row.size():
				_wire_to(tile, _tiles[row[j + 1]], &"right")
			else:
				FocusGraph.clear(tile, [&"right"])
			var cx: float = tile.get_global_rect().get_center().x
			if r > 0:
				_wire_to(tile, _nearest_by_x(_row_controls(rows[r - 1]), cx), &"top")
			else:
				_wire_to(tile, _nearest_by_x([_mode_free, _mode_teams, _back], cx), &"top")
			if r + 1 < rows.size():
				_wire_to(tile, _nearest_by_x(_row_controls(rows[r + 1]), cx), &"bottom")
			elif band_shown:
				_wire_to(tile, _ready_band, &"bottom")
			else:
				_wire_to(tile, _nearest_by_x(_bays, cx), &"bottom")
	# The four stations: adjacent in x (the authored station row closes), up
	# into the nearest tile of the ACTUAL bottom row.
	for i in _bays.size():
		var bay = _bays[i]
		var count := _bays.size()
		bay.focus_neighbor_left = bay.get_path_to(_bays[(i - 1 + count) % count])
		bay.focus_neighbor_right = bay.get_path_to(_bays[(i + 1) % count])
		_wire_to(bay, _nearest_by_x(_row_controls(bottom_row), bay.get_global_rect().get_center().x), &"top")
	# Ready: directly above the stations, directly below the occupied roster.
	var band_x: float = _ready_band.get_global_rect().get_center().x
	_wire_to(_ready_band, _nearest_by_x(_row_controls(bottom_row), band_x), &"top")
	_wire_to(_ready_band, _nearest_by_x(_bays, band_x), &"bottom")
	# The header destinations: authored chain by x, each owning the roster tile
	# under it (never every tile routing up to Back — C-050).
	var header: Array = [_mode_free, _mode_teams, _back]
	header.sort_custom(func(a, b):
		return (a as Control).get_global_rect().get_center().x < (b as Control).get_global_rect().get_center().x)
	for i in header.size():
		var control: Control = header[i]
		if i > 0:
			_wire_to(control, header[i - 1], &"left")
		else:
			FocusGraph.clear(control, [&"left"])
		if i + 1 < header.size():
			_wire_to(control, header[i + 1], &"right")
		else:
			FocusGraph.clear(control, [&"right"])
		FocusGraph.clear(control, [&"top"])
		_wire_to(control, _nearest_by_x(_row_controls(top_row), control.get_global_rect().get_center().x), &"bottom")
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
	# §11 Back matrix + Doc 04 staged cancel: keyboard Esc and pad B reach this
	# through FrontendInput.cancel_pressed (one signal per physical press), and
	# it runs the SAME staged handler as the visible Back control.
	if not is_visible_in_tree() or _phase == Phase.EXITING:
		return
	_cancel_or_back()

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

# --- composition test surface (Doc 04 §10 / Doc 08 §1 GEOMETRY_FIXTURE) -----
func roster_rows() -> int:
	# The occupied roster rows the current composition was resolved from.
	return occupied_rows()

func roster_bounds_geometry() -> Rect2:
	# The occupied roster envelope (the same bounds the carry boundary uses),
	# exposed so a geometry fixture can assert containment without touching
	# the interaction state.
	return roster_bounds()
