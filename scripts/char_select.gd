extends Control
# Character Select — canonical Step 3 (Doc 04).
#
# This script is controller/state orchestration, NOT layout construction:
#   * fixed composition lives in scenes/character_select.tscn
#     (header · roster field · ready band · four player stations)
#   * roster tiles are data-driven instances of scenes/components/FighterTile.tscn
#   * player stations are PlayerBay component instances
#   * tokens are PlayerTokenView instances, one per player, with their own FSM
#
# Ownership rules:
#   * candidate fighter != committed fighter. Hover/focus only changes the
#     candidate; only a confirm (click / pad confirm) edits MatchSelectionState.
#   * token state is screen-local (UNASSIGNED/PLACED/CARRIED/RETURNING/PLACING);
#     the committed fighter lives in the persistent selection state.
#   * the hand is FREE outside the roster interaction field; it carries the
#     active player's token only while selecting a fighter (Doc 04 §14).
#   * the active player persists after committing (Doc 04 §10A) and only
#     changes through an explicit bay activation.

signal ready_requested
signal back_requested
signal exit_finished

const Tokens = preload("res://scripts/ui_tokens.gd")
const Roster = preload("res://scripts/roster.gd")
const PortraitData = preload("res://scripts/frontend/portrait_data.gd")
const TileScene = preload("res://scenes/components/FighterTile.tscn")
const TokenScene = preload("res://scenes/components/PlayerTokenView.tscn")
const TokenView = preload("res://scripts/frontend/player_token_view.gd")

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
const KINDS := ["human", "bot", "empty"]
const DIFFICULTIES := ["easy", "normal", "hard"]

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
var _carried_by := -1
var _seeding_focus := false
var _phase: Phase = Phase.ENTERING
var _guard := 0.0

@onready var _frame: Control = $ReferenceFrame
@onready var _field_panel: Panel = $Field
@onready var _header: Control = $ReferenceFrame/Header
@onready var _title: Label = $ReferenceFrame/Header/Title
@onready var _mode_free: Label = $ReferenceFrame/Header/ModeControl/ModeFree
@onready var _mode_teams: Label = $ReferenceFrame/Header/ModeControl/ModeTeams
@onready var _mode_rule: Panel = $ReferenceFrame/Header/ModeControl/ModeRule
@onready var _back: Button = $ReferenceFrame/Header/BackAction
@onready var _field: Control = $ReferenceFrame/RosterField
@onready var _field_rule: Panel = $ReferenceFrame/RosterField/FieldRule
@onready var _grid: Control = $ReferenceFrame/RosterField/FighterGrid
@onready var _stations: Control = $ReferenceFrame/PlayerStations
@onready var _ready_band = $ReferenceFrame/ReadyBand
var _token_layer: Control

func _ready() -> void:
    theme = Tokens.make_theme()
    var root = get_node_or_null("/root/Cursor")
    if root != null:
        cursor = root.hand
    _field_panel.add_theme_stylebox_override("panel", Tokens.flat(Tokens.BASE))
    _title.add_theme_color_override("font_color", Tokens.CREAM)
    _mode_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    _field_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE))
    Tokens.apply_styles(_back, Tokens.row_styles())
    _back.add_theme_color_override("font_color", Tokens.CREAM)
    _back.pressed.connect(_on_back_pressed)
    if cursor != null and not cursor.modality_changed.is_connected(_on_modality_changed):
        cursor.modality_changed.connect(_on_modality_changed)
    _mode_free.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _set_mode(0))
    _mode_teams.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _set_mode(1))
    _mode_free.focus_mode = Control.FOCUS_ALL
    _mode_teams.focus_mode = Control.FOCUS_ALL
    _field.mouse_entered.connect(func(): pass)
    _field.mouse_exited.connect(_leave_field)
    # Token layer: tokens live here while placed on tiles; the cursor layer
    # takes over while one is carried (data drives the presentation).
    _token_layer = Control.new()
    _token_layer.name = "TokenLayer"
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
        bay.bay_activated.connect(_on_bay_activated)
        bay.kind_clicked.connect(_on_kind_clicked)
        bay.difficulty_clicked.connect(_on_difficulty_clicked)
        bay.team_clicked.connect(_on_team_clicked)
        _bays.append(bay)
        if cursor != null:
            cursor.add_target(bay)
    _ready_band.ready_pressed.connect(_on_ready_pressed)
    _ready_band.focus_mode = Control.FOCUS_ALL
    _ready_band.focus_entered.connect(_on_ready_band_focused)
    _ready_band.apply_reference_width(Tokens.DESIGN.x)
    _ready_band.position.x = (Tokens.DESIGN.x - _ready_band.size.x) * 0.5
    _ready_band.hide_band()
    if cursor != null:
        cursor.add_target(_back)
        cursor.add_target(_ready_band)
        cursor.add_target(_mode_free)
        cursor.add_target(_mode_teams)

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
    _carried_by = -1
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
    _phase = Phase.ENTERING
    _guard = ENTER_GUARD
    Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
    if cursor != null:
        cursor.visible = true
        cursor.begin_screen("css")
    _refresh()
    _enter_choreography()
    _seed_focus()

func reopen() -> void:
    # Back from the stage page: every commit survives; transient carry does not.
    _phase = Phase.IDLE
    _guard = 0.25
    _candidate = -1
    _clear_carry()
    Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
    if cursor != null:
        cursor.visible = true
        cursor.begin_screen("css")
    _refresh()
    _seed_focus()

func reset() -> void:
    _phase = Phase.IDLE
    _guard = 0.0
    _candidate = -1
    _clear_carry()
    _refresh()

func play_exit() -> void:
    if _phase == Phase.EXITING:
        return
    _phase = Phase.EXITING
    _clear_carry()
    _ready_band.hide_band()
    var tween := create_tween()
    tween.tween_property(_frame, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    tween.tween_callback(func() -> void: exit_finished.emit())

func is_exiting() -> bool:
    return _phase == Phase.EXITING

func ready_allowed() -> bool:
    return _state != null and _state.can_ready()

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

# --- state refresh -------------------------------------------------------
func _refresh() -> void:
    if _state == null:
        return
    for i in _bays.size():
        var slot: Dictionary = _state.slots[i]
        var kind := str(slot.get("kind", "human"))
        var fid := str(slot.get("character", ""))
        var display := Roster.display_name(fid).to_upper() if fid != "" else ""
        _bays[i].set_slot_state(kind, fid if kind != "empty" else "", display,
            str(slot.get("difficulty", "normal")), int(slot.get("team", 0)), _state.mode)
        _bays[i].set_active(i == _active)
    if _state.mode == 0:
        _mode_free.modulate = Color(1, 1, 1, 1)
        _mode_teams.modulate = Color(1, 1, 1, 0.45)
        _mode_rule.position.x = 0.0
        _mode_rule.size.x = 212.0
    else:
        _mode_free.modulate = Color(1, 1, 1, 0.45)
        _mode_teams.modulate = Color(1, 1, 1, 1)
        _mode_rule.position.x = 250.0
        _mode_rule.size.x = 130.0
    _recompute_tokens()
    if ready_allowed():
        _ready_band.show_band()
        _wire_ready_neighbors(true)
    else:
        _ready_band.hide_band()
        _wire_ready_neighbors(false)

func _recompute_tokens() -> void:
    # UNASSIGNED players hide their token; committed players rest on their tile.
    for player in 4:
        if player == _carried_by:
            continue
        if not is_instance_valid(_tokens[player]):
            continue
        var slot: Dictionary = _state.slots[player]
        var fid := str(slot.get("character", ""))
        if str(slot.get("kind", "human")) == "empty" or fid == "":
            _token_state[player] = TokenView.State.UNASSIGNED
            _tokens[player].visible = false
            continue
        var tile_index := _tile_index_of(fid)
        if tile_index < 0:
            _token_state[player] = TokenView.State.UNASSIGNED
            _tokens[player].visible = false
            continue
        _place_token(player, tile_index)
    _update_candidate_visuals()

func _place_token(player: int, tile_index: int) -> void:
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
    if _tokens[player].get_parent() != tile.token_layer():
        _tokens[player].reparent(tile.token_layer())
    _tokens[player].visible = true
    _token_state[player] = TokenView.State.PLACED
    _tokens[player].set_state(TokenView.State.PLACED)
    tile.place_token_view(_tokens[player], ordinal, committed.size())

func _tile_index_of(id: String) -> int:
    for i in _cards.size():
        if str(_cards[i]["id"]) == id:
            return i
    return -1

# --- token carry (mouse) -------------------------------------------------
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
    if cursor == null or cursor.mode != 1:
        return
    cursor.set_focus_target(_ready_band.anchor())

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
    if cursor == null or cursor.mode != 1:
        return
    if index < _bays.size():
        cursor.set_focus_target(_bays[index].anchor())

func _begin_carry(player: int) -> void:
    if _carried_by == player:
        return
    if _carried_by >= 0:
        _return_carried()
    _carried_by = player
    _token_state[player] = TokenView.State.CARRIED
    _tokens[player].visible = true
    _tokens[player].set_state(TokenView.State.CARRIED)
    if cursor != null:
        cursor.set_carry(_tokens[player])
    FrontendEvents.emit_token_pickup(player)

func _return_carried() -> void:
    if _carried_by < 0:
        return
    var player := _carried_by
    _carried_by = -1
    _token_state[player] = TokenView.State.RETURNING
    if cursor != null:
        cursor.clear_carry()
    _recompute_tokens()

func _clear_carry() -> void:
    if _carried_by >= 0:
        var player := _carried_by
        _carried_by = -1
        _token_state[player] = TokenView.State.RETURNING
    if cursor != null:
        cursor.clear_carry()

func _leave_field() -> void:
    _set_candidate(-1)
    if _carried_by >= 0:
        _return_carried()

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

# --- semantic actions ----------------------------------------------------
func _on_tile_pressed(id: String) -> void:
    if _phase != Phase.IDLE or _guard > 0.0 or _state == null:
        return
    var player := _active
    var slot: Dictionary = _state.slots[player]
    if str(slot.get("kind", "human")) == "empty":
        slot["kind"] = "human"       # explicit convenience rule (Doc 04 §23)
    slot["character"] = id           # THE commit: candidate -> committed
    _phase = Phase.IDLE
    var tile_index := _tile_index_of(id)
    if _carried_by >= 0:
        _token_state[_carried_by] = TokenView.State.PLACING
        _carried_by = -1
        if cursor != null:
            cursor.clear_carry()
    elif tile_index >= 0:
        _token_state[player] = TokenView.State.PLACING
    FrontendEvents.emit_token_place(player)
    _refresh()

func _on_bay_activated(index: int) -> void:
    if _phase == Phase.EXITING:
        return
    _active = index                  # explicit only (Doc 04 §10A)
    _refresh()

func _on_kind_clicked(index: int) -> void:
    if _state == null:
        return
    var slot: Dictionary = _state.slots[index]
    var at: int = KINDS.find(str(slot.get("kind", "human")))
    slot["kind"] = KINDS[(at + 1) % KINDS.size()]
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
    _state.mode = mode
    _refresh()

func _on_ready_pressed() -> void:
    if ready_allowed():
        ready_requested.emit()

func _on_back_pressed() -> void:
    _clear_carry()
    back_requested.emit()

func _process(delta: float) -> void:
    if _guard > 0.0:
        _guard = maxf(_guard - delta, 0.0)
    if _phase == Phase.ENTERING and _guard <= 0.0:
        _phase = Phase.IDLE

# --- keyboard / controller ----------------------------------------------
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
    _mode_free.focus_neighbor_right = _mode_free.get_path_to(_mode_teams)
    _mode_teams.focus_neighbor_left = _mode_teams.get_path_to(_mode_free)
    _mode_teams.focus_neighbor_right = _mode_teams.get_path_to(_back)
    _mode_free.focus_neighbor_bottom = _mode_free.get_path_to(_tiles[n - 1])
    _mode_teams.focus_neighbor_bottom = _mode_teams.get_path_to(_tiles[n - 1])

func _unhandled_key_input(event: InputEvent) -> void:
    if not is_visible_in_tree():
        return
    var confirm := false
    if event is InputEventKey and event.pressed and not event.echo:
        confirm = event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE
    elif event is InputEventJoypadButton and event.pressed:
        confirm = event.button_index == JOY_BUTTON_A
    if not confirm:
        return
    # Focused control wins over the screen-level READY (Doc 04 §19/§20A).
    var focused := get_viewport().gui_get_focus_owner()
    if focused != null:
        var t: int = _tiles.find(focused)
        if t >= 0 and _phase == Phase.IDLE:
            _on_tile_pressed(str(_tiles[t].fighter_id))
            get_viewport().set_input_as_handled()
            return
        var b: int = _bays.find(focused)
        if b >= 0 and _phase == Phase.IDLE:
            _on_bay_activated(b)
            get_viewport().set_input_as_handled()
            return
        if focused == _ready_band and ready_allowed():
            _on_ready_pressed()
            get_viewport().set_input_as_handled()
            return
        if focused == _mode_free or focused == _mode_teams:
            _set_mode(1 if focused == _mode_teams else 0)
            get_viewport().set_input_as_handled()
            return
    if ready_allowed() and _phase != Phase.EXITING:
        ready_requested.emit()
        get_viewport().set_input_as_handled()

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

func get_mode_control() -> Control:
    return _mode_free.get_parent()

func get_ready_band() -> Control:
    return _ready_band

func get_input_guard() -> float:
    return _guard
