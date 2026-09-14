extends Control
# How to Play — the structured in-game manual (Doc 07 §3-§8, LOCKED).
#
# Composition is AUTHORED (scenes/how_to_play.tscn): header (title, warm
# leading rule, visible Back), the section tab band with its input-profile
# segments, and the two body zones. This script owns only content data, the
# BASICS/FIGHTERS section switch, the input-profile switch that swaps the
# DISPLAYED binding labels (never the instructional content), the roster strip
# (data-driven FighterTile instances, the same identity component as CSS) and
# the focus graph.
#
# Rules this screen keeps:
#   * instruction rows are typography, not controls: never focusable, never
#     boxed (Doc 07 §8 / §21);
#   * the binding source of truth is the legacy demo_style CONTROLS data
#     (P1 WASD/Space/F/G/E, P2 Arrows/Enter/K/L/O, pad stick/A/X/B/shoulders);
#   * focus order follows visual order — BASICS: sections -> input profile ->
#     Back; FIGHTERS: sections -> roster -> Back;
#   * every interactive control exposes an authored CursorAnchor and reports
#     focus to the persistent hand cursor (Doc 01 §12.1);
#   * no rounded-card dashboard treatment: hard edges, thin rules, one warm
#     structural signal.

signal closed

const Tokens = preload("res://scripts/ui_tokens.gd")
const Roster = preload("res://scripts/roster.gd")
const PortraitData = preload("res://scripts/frontend/portrait_data.gd")
const TileScene = preload("res://scenes/components/FighterTile.tscn")
const RenderViewScript = preload("res://scripts/frontend/fighter_render_view.gd")
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")

const SECTIONS: Array = ["BASICS", "FIGHTERS"]
const PROFILES: Array = ["P1_KEYBOARD", "P2_KEYBOARD", "CONTROLLER"]
const PROFILE_BUTTONS: Dictionary = {
    "P1_KEYBOARD": "ProfileP1", "P2_KEYBOARD": "ProfileP2", "CONTROLLER": "ProfileCtrl",
}
# The authored hand targets of the input-profile segments (Doc 03 §6): the
# scene owns the anchors, this screen owns pointing at them.
const PROFILE_ANCHORS: Dictionary = {
    "P1_KEYBOARD": "AnchorP1", "P2_KEYBOARD": "AnchorP2", "CONTROLLER": "AnchorCtrl",
}
const TAB_NODES: Dictionary = {"BASICS": "SectionBasics", "FIGHTERS": "SectionFighters"}

# Displayed bindings per input profile (Doc 07 §4). Source of truth: the
# legacy demo_style CONTROLS string. Only these labels swap.
const BINDINGS: Dictionary = {
    "P1_KEYBOARD": {"move": "WASD", "jump": "SPACE / W", "basic": "F", "special": "G", "shield": "E", "drop": "S", "none": "—"},
    "P2_KEYBOARD": {"move": "ARROWS", "jump": "ENTER / UP", "basic": "K", "special": "L", "shield": "O", "drop": "DOWN", "none": "—"},
    "CONTROLLER": {"move": "STICK / D-PAD", "jump": "A", "basic": "X", "special": "B", "shield": "SHOULDER", "drop": "DOWN", "none": "—"},
}

# BASICS subsections (Doc 07 §4). Each row: action name + input key + one
# concise sentence. The input key indexes BINDINGS for the active profile.
const BASICS_GROUPS: Array = [
    {"title": "MOVEMENT", "column": 0, "rows": [
        {"id": "move", "name": "MOVE", "input": "move", "note": "Move and aim your fighter."},
        {"id": "jump", "name": "JUMP", "input": "jump", "note": "Jump. Some fighters can jump more than once."},
    ]},
    {"title": "ATTACK", "column": 0, "rows": [
        {"id": "basic", "name": "BASIC", "input": "basic", "note": "Your standard attack changes with direction."},
        {"id": "special", "name": "SPECIAL", "input": "special", "note": "Character-specific special move."},
    ]},
    {"title": "DEFENSE", "column": 1, "rows": [
        {"id": "shield", "name": "SHIELD", "input": "shield", "note": "Block incoming attacks."},
    ]},
    {"title": "PLATFORMS", "column": 1, "rows": [
        {"id": "upper_platforms", "name": "UPPER PLATFORMS", "input": "jump", "note": "Pass-through platforms catch you when you jump up through them."},
        {"id": "drop_through", "name": "DROP THROUGH", "input": "drop", "note": "Tap down on an upper platform to drop through it."},
        {"id": "edges", "name": "THE EDGES", "input": "none", "note": "Knockback off the stage costs a stock. Watch the edges."},
    ]},
]

# Fighter move lists (Doc 07 §5): move name + compact input notation, from the
# legacy demo_style MOVES data. Mephisto has no curated list in that source, so
# the two universal moves are shown instead of invented specifics.
const MOVE_LISTS: Dictionary = {
    "teknium": [
        {"name": "FORCE PUSH", "input": "LEFT / RIGHT + SPECIAL"},
        {"name": "ELECTRIC GRAB", "input": "SPECIAL (CLOSE)"},
    ],
    "doge_man": [
        {"name": "GROUND RUSH", "input": "HOLD DOWN + SPECIAL, RELEASE"},
        {"name": "FLYING TACKLE", "input": "LEFT / RIGHT + SPECIAL"},
        {"name": "SUPERMAN PUNCH", "input": "JUMP, THEN BASIC"},
    ],
    "ggb": [
        {"name": "STICKY GOO", "input": "LEFT / RIGHT + SPECIAL"},
        {"name": "LEAD PLUNGE", "input": "DOWN + SPECIAL"},
        {"name": "FIVE JUMPS", "input": "JUMP (HOLD TO FLOAT)"},
    ],
    "turbofit": [
        {"name": "BASIC STRIKES", "input": "BASIC", "note": "Changes with direction."},
        {"name": "SOUND ATTACKS", "input": "SPECIAL"},
    ],
    "ice_mage": [
        {"name": "PALM", "input": "BASIC"},
        {"name": "FROST BOLT", "input": "SPECIAL"},
        {"name": "FROST RISE", "input": "UP + SPECIAL"},
    ],
    "witcheer": [
        {"name": "KICK / PUNCH", "input": "BASIC"},
        {"name": "SWEEP", "input": "DOWN + BASIC"},
        {"name": "COIN TOSS", "input": "LEFT / RIGHT + SPECIAL"},
        {"name": "SWIM", "input": "UP + SPECIAL"},
        {"name": "ABSORB / HEAL", "input": "DOWN + SPECIAL"},
    ],
}
const GENERIC_MOVES: Array = [
    {"name": "BASIC STRIKE", "input": "BASIC", "note": "Standard attack. Changes with direction."},
    {"name": "SPECIAL", "input": "SPECIAL", "note": "Character-specific move."},
]

const COL_W := 552.0          # authored column width inside a body zone
const ROW_H := 62.0           # one instruction row block
const GROUP_GAP := 26.0       # subsection separation
const TILE_W := 96.0
const TILE_H := 78.0
const TILE_COLS := 2
const TILE_GAP := 8.0
const FADE_SECONDS := 10.0 / 60.0

var _section := "BASICS"
var _profile := "P1_KEYBOARD"
var _ids: Array[String] = []
var _row_inputs: Dictionary = {}          # row id -> displayed input Label
var _row_roots: Array = []                # instruction row roots (never focusable)
var _move_roots: Array = []
var _subsection_titles: Array = []
var _tiles: Array = []
var _selected := 0
var _markers: Dictionary = {}             # control -> focus marker Panel
var _labels: Dictionary = {}              # control -> label to brighten
var _render_view: Control = null

@onready var _field: Panel = $Field
@onready var _frame: Control = $ReferenceFrame
@onready var _title: Label = $ReferenceFrame/Header/Title
@onready var _title_rule: Panel = $ReferenceFrame/Header/TitleRule
@onready var _back: Button = $ReferenceFrame/Header/HelpBack
@onready var _back_rail: Panel = $ReferenceFrame/Header/BackRail
@onready var _tab_band: Control = $ReferenceFrame/TabBand
@onready var _profile_control: Control = $ReferenceFrame/TabBand/ProfileControl
@onready var _profile_label: Label = $ReferenceFrame/TabBand/ProfileControl/ProfileLabel
@onready var _basics_body: Control = $ReferenceFrame/BasicsBody
@onready var _basics_left: Control = $ReferenceFrame/BasicsBody/BasicsLeft
@onready var _basics_right: Control = $ReferenceFrame/BasicsBody/BasicsRight
@onready var _fighters_body: Control = $ReferenceFrame/FightersBody
@onready var _roster_strip: Control = $ReferenceFrame/FightersBody/RosterStrip
@onready var _fighter_name: Label = $ReferenceFrame/FightersBody/FighterName
@onready var _render_holder: Control = $ReferenceFrame/FightersBody/RenderHolder
@onready var _moves_heading: Label = $ReferenceFrame/FightersBody/MovesHeading
@onready var _moves_list: Control = $ReferenceFrame/FightersBody/MovesList
@onready var _footer: Control = $ReferenceFrame/Footer
@onready var _footer_rule: Panel = $ReferenceFrame/Footer/FooterRule
@onready var _footer_help: Label = $ReferenceFrame/Footer/FooterHelp

func _ready() -> void:

    if not FrontendInput.cancel_pressed.is_connected(_on_semantic_cancel):
        FrontendInput.cancel_pressed.connect(_on_semantic_cancel)
    theme = Tokens.make_theme()
    name = "HowToPlay"
    _style()
    _build_basics()
    _build_profile_controls()
    _build_fighters()
    _wire_back()
    _select_fighter(0, true)
    show_section("BASICS")
    _refresh_bindings()
    _entry()
    var hand = _hand()
    if hand != null:
        hand.begin_screen("help")

# --- styling (colors resolved from the shared tokens) ----------------------
func _style() -> void:
    _field.add_theme_stylebox_override("panel", Tokens.flat(Tokens.BASE))
    _title.add_theme_font_override("font", Tokens.font("semibold"))
    _title.add_theme_color_override("font_color", Tokens.CREAM)
    _title_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE_WARM))
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
    _back.add_theme_color_override("font_pressed_color", Tokens.CREAM)
    _back_rail.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    _back_rail.hide()
    _profile_label.add_theme_font_override("font", Tokens.font("medium"))
    _profile_label.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    _moves_heading.add_theme_font_override("font", Tokens.font("medium"))
    _moves_heading.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    _footer_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE))
    _footer_help.add_theme_font_override("font", Tokens.font("regular"))
    _footer_help.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    _footer_help.text = "Connect a pad before launching. Down drops through an upper platform. Esc returns to the main menu."
    for section in SECTIONS:
        var root: Control = _tab_band.get_node(str(TAB_NODES[section]))
        var hit: Button = root.get_node("HitArea")
        Tokens.apply_styles(hit, {
            "normal": Tokens.flat(Color(0, 0, 0, 0)),
            "hover": Tokens.flat(Color(0, 0, 0, 0)),
            "pressed": Tokens.flat(Color(0, 0, 0, 0)),
            "focus": Tokens.flat(Color(0, 0, 0, 0)),
        })
        hit.pressed.connect(_on_tab_pressed.bind(section))
        hit.focus_entered.connect(_on_tab_focused.bind(section))
        (root.get_node("Rail") as Panel).add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
        (root.get_node("Quiet") as Panel).add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE_WARM))
        var label: Label = root.get_node("Label")
        _labels[hit] = label
        _add_focus_marker(hit, root, label, Vector2(label.position.x, label.position.y + label.size.y + 2.0))

# --- BASICS content ---------------------------------------------------------
func _build_basics() -> void:
    var column_y := [0.0, 0.0]
    var columns: Array = [_basics_left, _basics_right]
    for group in BASICS_GROUPS:
        var column: Control = columns[int(group["column"])]
        column_y[int(group["column"])] = _add_group(column, str(group["title"]), group["rows"], column_y[int(group["column"])])

func _add_group(column: Control, title: String, rows: Array, y: float) -> float:
    var heading := Label.new()
    heading.name = "Subsection" + title
    heading.text = title
    heading.position = Vector2(0.0, y)
    heading.size = Vector2(COL_W, 26.0)
    heading.add_theme_font_override("font", Tokens.font("semibold"))
    heading.add_theme_font_size_override("font_size", 18)
    heading.add_theme_color_override("font_color", Tokens.CREAM)
    column.add_child(heading)
    _subsection_titles.append(title)
    var rule := Panel.new()
    rule.name = "Rule"
    rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
    rule.position = Vector2(0.0, y + 30.0)
    rule.size = Vector2(COL_W, 1.0)
    rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE))
    column.add_child(rule)
    var cursor_y := y + 40.0
    for row in rows:
        var row_root := Control.new()
        row_root.name = "Row" + str(row["id"]).to_pascal_case()
        row_root.position = Vector2(0.0, cursor_y)
        row_root.size = Vector2(COL_W, ROW_H)
        row_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row_root.focus_mode = Control.FOCUS_NONE
        column.add_child(row_root)
        var action := Label.new()
        action.name = "ActionName"
        action.text = str(row["name"])
        action.position = Vector2.ZERO
        action.size = Vector2(COL_W, 28.0)
        action.add_theme_font_override("font", Tokens.font("medium"))
        action.add_theme_font_size_override("font_size", 20)
        action.add_theme_color_override("font_color", Tokens.CREAM)
        row_root.add_child(action)
        var input := Label.new()
        input.name = "Input"
        input.position = Vector2(0.0, 26.0)
        input.size = Vector2(240.0, 20.0)
        input.add_theme_font_override("font", Tokens.font("semibold"))
        input.add_theme_font_size_override("font_size", 14)
        input.add_theme_color_override("font_color", Tokens.ACCENT)
        row_root.add_child(input)
        var note := Label.new()
        note.name = "Note"
        note.text = str(row["note"])
        note.position = Vector2(212.0, 24.0)
        note.size = Vector2(COL_W - 212.0, 38.0)
        note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        note.add_theme_font_override("font", Tokens.font("regular"))
        note.add_theme_font_size_override("font_size", 13)
        note.add_theme_color_override("font_color", Tokens.CREAM_DIM)
        row_root.add_child(note)
        _row_inputs[str(row["id"])] = input
        _row_roots.append(row_root)
        cursor_y += ROW_H
    return cursor_y + GROUP_GAP

# --- input-profile selector -------------------------------------------------
func _build_profile_controls() -> void:
    for profile in PROFILES:
        var button: Button = _profile_control.get_node(str(PROFILE_BUTTONS[profile]))
        Tokens.apply_styles(button, {
            "normal": Tokens.flat(Color(0, 0, 0, 0)),
            "hover": Tokens.flat(Color(1, 1, 1, 0.05)),
            "pressed": Tokens.flat(Color(1, 1, 1, 0.09)),
            "focus": Tokens.flat(Color(0, 0, 0, 0)),
        })
        button.add_theme_font_override("font", Tokens.font("medium"))
        button.add_theme_font_size_override("font_size", 15)
        button.pressed.connect(set_profile.bind(profile))
        button.focus_entered.connect(_on_profile_focused.bind(profile))
        _labels[button] = button
        _add_focus_marker(button, _profile_control, button, Vector2(button.position.x, button.position.y - 4.0))
    _apply_profile_state()
    _refresh_bindings()

func set_profile(id: String) -> void:
    if id not in PROFILES or id == _profile:
        return
    _profile = id
    _apply_profile_state()
    _refresh_bindings()

func _apply_profile_state() -> void:
    for profile in PROFILES:
        var button: Button = _profile_control.get_node(str(PROFILE_BUTTONS[profile]))
        var active: bool = profile == _profile
        button.add_theme_color_override("font_color", Tokens.CREAM if active else Tokens.CREAM_DIM)
        button.add_theme_color_override("font_hover_color", Tokens.CREAM)
        button.add_theme_color_override("font_focus_color", Tokens.CREAM)
        button.add_theme_font_override("font", Tokens.font("semibold") if active else Tokens.font("medium"))
        var rail: Panel = _profile_control.get_node("Rail" + str(PROFILE_BUTTONS[profile]).trim_prefix("Profile"))
        rail.visible = active

func _refresh_bindings() -> void:
    var table: Dictionary = BINDINGS[_profile]
    for row_id in _row_inputs.keys():
        var input: Label = _row_inputs[row_id]
        input.text = str(table.get(str(row_id), ""))

func profile() -> String:
    return _profile

func profile_ids() -> Array:
    return PROFILES.duplicate()

func binding_for(row_id: String) -> String:
    # Reads the DISPLAYED label, so tests see what the player sees.
    var input = _row_inputs.get(row_id, null)
    return str(input.text) if input != null else ""

# --- FIGHTERS content ------------------------------------------------------
func _build_fighters() -> void:
    _ids = Roster.ids()
    var n := _ids.size()
    for i in n:
        var id := _ids[i]
        var row: int = i / TILE_COLS
        var col: int = i % TILE_COLS
        var tile = TileScene.instantiate()
        tile.name = "FighterTile%d" % i
        tile.position = Vector2(col * (TILE_W + TILE_GAP), row * (TILE_H + TILE_GAP + 6.0))
        _roster_strip.add_child(tile)
        # Components resolve their children on tree entry: configure after.
        tile.set_tile_size(Vector2(TILE_W, TILE_H))
        tile.setup(id, Roster.display_name(id).to_upper(), PortraitData.portrait_texture(id))
        tile.focus_mode = Control.FOCUS_ALL
        tile.tile_pressed.connect(_select_fighter_by_id)
        tile.focus_entered.connect(_on_tile_focused.bind(i))
        tile.mouse_entered.connect(_on_tile_hovered.bind(i))
        _tiles.append(tile)
        _add_focus_marker(tile, _roster_strip, null, Vector2(tile.position.x, tile.position.y + tile.size.y + 4.0))

func _on_tile_focused(index: int) -> void:
    if index < 0 or index >= _tiles.size():
        return
    FocusGraph.track(self, _tiles[index])
    _select_fighter(index)
    var hand = _hand()
    if hand != null and hand.mode == 1:
        hand.set_focus_target(_tiles[index].anchor())

func _on_tile_hovered(index: int) -> void:
    _select_fighter(index)

func _select_fighter_by_id(id: String) -> void:
    var index := _ids.find(id)
    if index >= 0:
        _select_fighter(index)

func _select_fighter(index: int, force := false) -> void:
    if index < 0 or index >= _ids.size():
        return
    if index == _selected and not force:
        return
    _selected = index
    for i in _tiles.size():
        _tiles[i].set_candidate(i == index)
    _fighter_name.text = Roster.display_name(_ids[index]).to_upper()
    _refresh_moves(_ids[index])
    _refresh_render(_ids[index])

func _refresh_moves(id: String) -> void:
    for node in _moves_list.get_children():
        node.queue_free()
    _move_roots.clear()
    var moves: Array = MOVE_LISTS.get(id, GENERIC_MOVES)
    var y := 0.0
    for move in moves:
        var row := Control.new()
        row.name = "MoveRow"
        row.position = Vector2(0.0, y)
        row.size = Vector2(488.0, 66.0)
        row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.focus_mode = Control.FOCUS_NONE
        _moves_list.add_child(row)
        var name_label := Label.new()
        name_label.name = "MoveName"
        name_label.text = str(move["name"])
        name_label.size = Vector2(250.0, 26.0)
        name_label.add_theme_font_override("font", Tokens.font("medium"))
        name_label.add_theme_font_size_override("font_size", 20)
        name_label.add_theme_color_override("font_color", Tokens.CREAM)
        row.add_child(name_label)
        var input_label := Label.new()
        input_label.name = "MoveInput"
        input_label.text = str(move["input"])
        input_label.position = Vector2(250.0, 4.0)
        input_label.size = Vector2(238.0, 22.0)
        input_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        input_label.add_theme_font_override("font", Tokens.font("semibold"))
        input_label.add_theme_font_size_override("font_size", 14)
        input_label.add_theme_color_override("font_color", Tokens.ACCENT)
        row.add_child(input_label)
        var note: String = str(move.get("note", ""))
        if note != "":
            var note_label := Label.new()
            note_label.name = "MoveNote"
            note_label.text = note
            note_label.position = Vector2(0.0, 26.0)
            note_label.size = Vector2(488.0, 34.0)
            note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            note_label.add_theme_font_override("font", Tokens.font("regular"))
            note_label.add_theme_font_size_override("font_size", 13)
            note_label.add_theme_color_override("font_color", Tokens.CREAM_DIM)
            row.add_child(note_label)
        _move_roots.append(row)
        y += 66.0 if note != "" else 52.0

func _refresh_render(id: String) -> void:
    if _render_view == null or not is_instance_valid(_render_view):
        _render_view = RenderViewScript.new()
        _render_view.name = "FighterRender"
        _render_holder.add_child(_render_view)
        _render_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        _render_view.set_profile(RenderViewScript.PROFILE_PLAYER_BAY)
    _render_view.set_subjects([id])
    _render_view.request_render()

# --- sections / tabs --------------------------------------------------------
func _wire_back() -> void:
    _back.pressed.connect(_on_back_pressed)
    _back.focus_entered.connect(_on_back_focused)
    _back.focus_exited.connect(_on_back_unfocused)

func _on_semantic_cancel() -> void:
    if is_visible_in_tree():
        _on_back_pressed()

func _on_back_pressed() -> void:
    FrontendEvents.emit_back("help")
    closed.emit()

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

func section_ids() -> Array:
    return SECTIONS.duplicate()

func section() -> String:
    return _section

func show_section(id: String) -> void:
    if id not in SECTIONS:
        return
    _section = id
    var basics := id == "BASICS"
    _basics_body.visible = basics
    _fighters_body.visible = not basics
    _profile_control.visible = basics
    for section in SECTIONS:
        var root: Control = _tab_band.get_node(str(TAB_NODES[section]))
        var active: bool = section == id
        (root.get_node("Rail") as Panel).visible = active
        (root.get_node("Quiet") as Panel).visible = not active
        var label: Label = root.get_node("Label")
        label.add_theme_color_override("font_color", Tokens.CREAM if active else Tokens.CREAM_DIM)
        label.add_theme_font_override("font", Tokens.font("semibold") if active else Tokens.font("regular"))
    _refresh_focus_graph()
    var hand = _hand()
    if hand != null and hand.mode == 1:
        var tab: Control = _tab_band.get_node(str(TAB_NODES[id]))
        hand.set_focus_target(tab.get_node("Anchor"))

func _on_tab_pressed(id: String) -> void:
    show_section(id)

# --- content surface --------------------------------------------------------
func basics_rows() -> Array:
    return _row_roots.duplicate()

func instruction_rows() -> Array:
    # Non-interactive content: BASICS rows + FIGHTERS move rows.
    var out: Array = _row_roots.duplicate()
    out.append_array(_move_roots)
    return out

func subsection_titles() -> Array:
    return _subsection_titles.duplicate()

func roster_ids() -> Array:
    return _ids.duplicate()

func roster_tiles() -> Array:
    return _tiles.duplicate()

func selected_fighter_id() -> String:
    return _ids[_selected] if _selected >= 0 and _selected < _ids.size() else ""

func select_fighter(id: String) -> void:
    _select_fighter_by_id(id)

func render_view() -> Control:
    return _render_view

func back_button() -> Button:
    return _back

func focus_chain() -> Array:
    # Visible interactive controls in visual order (the cycle Tab traverses).
    var out: Array = []
    for section in SECTIONS:
        out.append(_tab_band.get_node(str(TAB_NODES[section])).get_node("HitArea"))
    if _section == "BASICS":
        for profile in PROFILES:
            out.append(_profile_control.get_node(str(PROFILE_BUTTONS[profile])))
    else:
        for tile in _tiles:
            out.append(tile)
    out.append(_back)
    return out.filter(func(control): return (control as Control).visible and (control as Control).focus_mode != Control.FOCUS_NONE)

func _refresh_focus_graph() -> void:
    # Tab order = visual order; directional neighbours follow the composition.
    var chain := focus_chain()
    for i in chain.size():
        var control: Control = chain[i]
        control.focus_next = control.get_path_to(chain[(i + 1) % chain.size()])
        control.focus_previous = control.get_path_to(chain[(i - 1 + chain.size()) % chain.size()])
        control.focus_neighbor_left = control.get_path_to(chain[(i - 1 + chain.size()) % chain.size()])
        control.focus_neighbor_right = control.get_path_to(chain[(i + 1) % chain.size()])
    if _section == "FIGHTERS" and not _tiles.is_empty():
        for i in _tiles.size():
            var tile: Control = _tiles[i]
            # Two-column grid: stay in the row, columns reach upward to Back.
            if i % TILE_COLS > 0:
                tile.focus_neighbor_left = tile.get_path_to(_tiles[i - 1])
            if i % TILE_COLS < TILE_COLS - 1 and i + 1 < _tiles.size():
                tile.focus_neighbor_right = tile.get_path_to(_tiles[i + 1])
            if i < TILE_COLS:
                tile.focus_neighbor_top = tile.get_path_to(_back)
            elif i - TILE_COLS >= 0:
                tile.focus_neighbor_top = tile.get_path_to(_tiles[i - TILE_COLS])
            if i + TILE_COLS < _tiles.size():
                tile.focus_neighbor_bottom = tile.get_path_to(_tiles[i + TILE_COLS])
    if _section == "BASICS":
        for profile in PROFILES:
            var button: Control = _profile_control.get_node(str(PROFILE_BUTTONS[profile]))
            button.focus_neighbor_top = button.get_path_to(_tab_band.get_node("SectionBasics/HitArea"))
    _back.focus_neighbor_left = _back.get_path_to(_tab_band.get_node(str(TAB_NODES["FIGHTERS"]) + "/HitArea"))
    if chain.size() > 3:
        _back.focus_neighbor_bottom = _back.get_path_to(chain[2])
    # §6: a section switch hides a whole zone (profile segments / roster), so
    # the recovery runs with the new topology in place.
    _ensure_focus_alive()

# --- focus hand targets + recovery (Doc 03 §6) ------------------------------
func profile_anchor(profile: String) -> Control:
    return _profile_control.get_node_or_null(str(PROFILE_ANCHORS.get(profile, "")))

func tab_anchor(section: String) -> Control:
    var root: Control = _tab_band.get_node_or_null(str(TAB_NODES.get(section, "")))
    return root.get_node_or_null("Anchor") if root != null else null

func _on_tab_focused(section: String) -> void:
    var root: Control = _tab_band.get_node_or_null(str(TAB_NODES.get(section, "")))
    if root != null:
        FocusGraph.track(self, root.get_node_or_null("HitArea"))
    var hand = _hand()
    if hand != null and hand.mode == 1:
        var anchor := tab_anchor(section)
        if anchor != null:
            hand.set_focus_target(anchor)

func _on_profile_focused(profile: String) -> void:
    var button: Control = _profile_control.get_node_or_null(str(PROFILE_BUTTONS.get(profile, "")))
    if button != null:
        FocusGraph.track(self, button)
    var hand = _hand()
    if hand != null and hand.mode == 1:
        var anchor := profile_anchor(profile)
        if anchor != null:
            hand.set_focus_target(anchor)

func focus_anchor_for(control: Control) -> Control:
    # The authored hand target of a focusable control on this screen (Doc 03 §6).
    if control == null:
        return null
    for profile in PROFILES:
        if _profile_control.get_node_or_null(str(PROFILE_BUTTONS[profile])) == control:
            return profile_anchor(profile)
    for section in SECTIONS:
        var root: Control = _tab_band.get_node_or_null(str(TAB_NODES[section]))
        if root != null and root.get_node_or_null("HitArea") == control:
            return tab_anchor(section)
    if control == _back:
        return $ReferenceFrame/Header/AnchorBack
    var index: int = _tiles.find(control)
    if index >= 0:
        return _tiles[index].anchor()
    return FocusGraph.anchor_of(control)

func _ensure_focus_alive() -> void:
    if not is_inside_tree():
        return
    var before := FrontendInput.focus_owner()
    var owner := FocusGraph.recover(get_viewport(), self, func() -> Control:
        var chain := focus_chain()
        return chain[0] if not chain.is_empty() else _back)
    if owner != null and owner != before:
        var hand = _hand()
        if hand != null and hand.mode == 1:
            var anchor := focus_anchor_for(owner)
            if anchor != null:
                hand.set_focus_target(anchor)

# --- focus markers (structural focus signal, never color alone) --------------
func _add_focus_marker(control: Control, parent: Control, label, at: Vector2) -> void:
    var marker := Panel.new()
    marker.name = "FocusMarker"
    marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
    marker.position = at
    marker.size = Vector2(64.0, 2.0)
    marker.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    marker.visible = false
    parent.add_child(marker)
    _markers[control] = marker
    control.focus_entered.connect(_on_control_focused.bind(control))
    control.focus_exited.connect(_on_control_unfocused.bind(control))

func _on_control_focused(control: Control) -> void:
    var marker: Panel = _markers.get(control, null)
    if marker != null:
        var label = _labels.get(control, null)
        if label is Label:
            marker.size.x = label.get_theme_font("font").get_string_size(
                str(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size("font_size")).x + 6.0
        elif label is Button:
            marker.position.x = (label as Button).position.x
            marker.size.x = (label as Button).size.x
        marker.show()
    var text_label = _labels.get(control, null)
    if text_label is Label:
        (text_label as Label).add_theme_color_override("font_color", Tokens.CREAM)

func _on_control_unfocused(control: Control) -> void:
    # A control only loses focus if the screen (or its section) still owns it.
    var marker: Panel = _markers.get(control, null)
    if marker != null and is_instance_valid(marker):
        marker.hide()
    var text_label = _labels.get(control, null)
    if text_label is Label and is_instance_valid(text_label):
        var still_active := _active_label_for(text_label)
        (text_label as Label).add_theme_color_override("font_color", Tokens.CREAM if still_active else Tokens.CREAM_DIM)

func _active_label_for(label: Label) -> bool:
    for section in SECTIONS:
        var root: Control = _tab_band.get_node(str(TAB_NODES[section]))
        if root.get_node("Label") == label:
            return section == _section
    return false

# --- entry -----------------------------------------------------------------
func _entry() -> void:
    _frame.modulate.a = 0.0
    var tween := create_tween()
    tween.tween_property(_frame, "modulate:a", 1.0, FADE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _hand():
    var cursor = get_node_or_null("/root/Cursor")
    if cursor == null or cursor.hand == null:
        return null
    return cursor.hand
