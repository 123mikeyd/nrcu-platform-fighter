extends Control
# Story Encounter Briefing — Doc 07 §11-§16 (LOCKED).
#
# The single playable encounter ("STORY 01 / BOBO") presented as an Encounter
# Briefing instead of a fake campaign browser: enemy presentation + objective +
# rules on the left, the player's fighter selection on the right, one
# screen-level START ENCOUNTER action (a rail/action, not a generic Button)
# and a visible Back that follows the player route Story -> Main.
#
# Ownership: this scene owns the visual layer ONLY. The Story state machine
# (ready / playing / complete / lost), the encounter launch and the routes stay
# in scripts/main.gd, exactly as before; the result state is a lightweight
# overlay here (the shipped Story result wording with replay/retry and a
# MAIN MENU route), never the multiplayer Results screen.
#
# Reuse: roster identity is FighterTile (same component as CSS) and the
# selected fighter + the enemy are presented through FighterRenderView. The
# encounter's Bobo is scripts/bobo_fighter.gd + scripts/bobo_visual.gd; the
# render view spawns the shared fighter script, so the enemy render attempt is
# VERIFIED at runtime (BoboVisual present) and falls back to a nameplate when
# the encounter identity cannot be resolved there.

signal chosen(id: String)
signal exit_finished

const Tokens = preload("res://scripts/ui_tokens.gd")
const Roster = preload("res://scripts/roster.gd")
const PortraitData = preload("res://scripts/frontend/portrait_data.gd")
const TileScene = preload("res://scenes/components/FighterTile.tscn")
const RenderViewScript = preload("res://scripts/frontend/fighter_render_view.gd")

const TILE_W := 90.0
const TILE_H := 72.0
const TILE_GAP := 8.0
const EXIT_SECONDS := 13.0 / 60.0
const ENTER_SECONDS := 10.0 / 60.0
const EXIT_LOCK := 0.5

var _ids: Array[String] = []
var _tiles: Array = []
var _selected := ""
var _render_view: Control = null
var _enemy_render_resolved := false
var _exiting := false
var _input_lock := 0.0
var _ready_state := true

@onready var _field: Panel = $Field
@onready var _frame: Control = $ReferenceFrame
@onready var _title: Label = $ReferenceFrame/Header/Title
@onready var _encounter: Label = $ReferenceFrame/Header/EncounterLabel
@onready var _title_rule: Panel = $ReferenceFrame/Header/TitleRule
@onready var _back: Button = $ReferenceFrame/Header/BackAction
@onready var _back_rail: Panel = $ReferenceFrame/Header/BackRail
@onready var _body: Control = $ReferenceFrame/BriefingBody
@onready var _enemy_label: Label = $ReferenceFrame/BriefingBody/EnemyZone/EnemyLabel
@onready var _presentation: Control = $ReferenceFrame/BriefingBody/EnemyZone/PresentationSlot
@onready var _enemy_name: Label = $ReferenceFrame/BriefingBody/EnemyZone/EnemyName
@onready var _enemy_health: Label = $ReferenceFrame/BriefingBody/EnemyZone/EnemyHealth
@onready var _flavor: Label = $ReferenceFrame/BriefingBody/EnemyZone/Flavor
@onready var _objective_heading: Label = $ReferenceFrame/BriefingBody/EnemyZone/ObjectiveHeading
@onready var _objective: Label = $ReferenceFrame/BriefingBody/EnemyZone/ObjectiveLabel
@onready var _rules_heading: Label = $ReferenceFrame/BriefingBody/EnemyZone/RulesHeading
@onready var _rule_stocks: Label = $ReferenceFrame/BriefingBody/EnemyZone/RuleStocks
@onready var _rule_behavior: Label = $ReferenceFrame/BriefingBody/EnemyZone/RuleBehavior
@onready var _split_rule: Panel = $ReferenceFrame/BriefingBody/SplitRule
@onready var _vs: Label = $ReferenceFrame/BriefingBody/VsLabel
@onready var _fighter_label: Label = $ReferenceFrame/BriefingBody/FighterZone/FighterLabel
@onready var _roster_strip: Control = $ReferenceFrame/BriefingBody/FighterZone/RosterStrip
@onready var _fighter_name: Label = $ReferenceFrame/BriefingBody/FighterZone/FighterName
@onready var _render_holder: Control = $ReferenceFrame/BriefingBody/FighterZone/RenderHolder
@onready var _action: Button = $ReferenceFrame/ActionButton
@onready var _action_rail: Panel = $ReferenceFrame/ActionRail
@onready var _action_top_rule: Panel = $ReferenceFrame/ActionTopRule
@onready var _anchor_action: Control = $ReferenceFrame/AnchorAction
@onready var _result_layer: Control = $ReferenceFrame/ResultLayer
@onready var _verdict_rule: Panel = $ReferenceFrame/ResultLayer/VerdictRule
@onready var _verdict: Label = $ReferenceFrame/ResultLayer/VerdictLabel
@onready var _verdict_detail: Label = $ReferenceFrame/ResultLayer/VerdictDetail

func _ready() -> void:
    theme = Tokens.make_theme()
    _style()
    # At-rest vocabulary: before the briefing is opened, the Back action
    # samples the player route Story -> Main (open() sets the in-flow label).
    _back.text = "BACK TO MAIN"
    _build_enemy()
    _build_render_view_if_needed()
    _wire()
    _refresh_selection()
    _refresh_result_state()

# --- styling ----------------------------------------------------------------
func _style() -> void:
    _field.add_theme_stylebox_override("panel", Tokens.flat(Tokens.BASE))
    for label in [_title, _fighter_name, _enemy_name]:
        label.add_theme_font_override("font", Tokens.font("semibold"))
        label.add_theme_color_override("font_color", Tokens.CREAM)
    _encounter.add_theme_font_override("font", Tokens.font("semibold"))
    _encounter.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    _title_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE_WARM))
    _enemy_health.add_theme_font_override("font", Tokens.font("medium"))
    _enemy_health.add_theme_color_override("font_color", Tokens.ACCENT)
    _objective.add_theme_font_override("font", Tokens.font("medium"))
    _objective.add_theme_color_override("font_color", Tokens.CREAM)
    for meta in [_enemy_label, _fighter_label]:
        meta.add_theme_font_override("font", Tokens.font("medium"))
        meta.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    for heading in [_objective_heading, _rules_heading]:
        heading.add_theme_font_override("font", Tokens.font("semibold"))
        heading.add_theme_color_override("font_color", Tokens.ACCENT)
    for rule in [_rule_stocks, _rule_behavior, _flavor]:
        rule.add_theme_font_override("font", Tokens.font("regular"))
        rule.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    _flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _split_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE))
    _vs.add_theme_font_override("font", Tokens.font("semibold"))
    _vs.add_theme_color_override("font_color", Tokens.ACCENT)
    _verdict_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE_WARM))
    _verdict.add_theme_font_override("font", Tokens.font("bold"))
    _verdict.add_theme_color_override("font_color", Tokens.CREAM)
    _verdict_detail.add_theme_font_override("font", Tokens.font("medium"))
    _verdict_detail.add_theme_color_override("font_color", Tokens.CREAM_DIM)
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
    # START ENCOUNTER: a rail/action, never a generic Button (Doc 07 §15).
    Tokens.apply_styles(_action, {
        "normal": Tokens.flat(Tokens.SURFACE_1),
        "hover": Tokens.flat(Tokens.SURFACE_2),
        "pressed": Tokens.flat(Tokens.SURFACE_2),
        "focus": Tokens.flat(Tokens.SURFACE_2),
        "disabled": Tokens.flat(Tokens.SURFACE_1),
    })
    _action.add_theme_font_override("font", Tokens.font("semibold"))
    _action.add_theme_color_override("font_color", Tokens.CREAM)
    _action.add_theme_color_override("font_hover_color", Tokens.CREAM)
    _action.add_theme_color_override("font_focus_color", Tokens.CREAM)
    _action.add_theme_color_override("font_disabled_color", Tokens.DISABLED)
    _action_rail.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    _action_top_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    _action_top_rule.hide()

func _wire() -> void:
    _back.pressed.connect(_on_back_pressed)
    _back.focus_entered.connect(_on_back_focused)
    _back.focus_exited.connect(_on_back_unfocused)
    _action.pressed.connect(_on_action_pressed)
    _action.focus_entered.connect(_on_action_focused)
    _action.focus_exited.connect(_on_action_unfocused)

func _on_back_pressed() -> void:
    FrontendEvents.emit_back("story")

func _on_back_focused() -> void:
    _back_rail.show()
    _back.add_theme_color_override("font_color", Tokens.CREAM)
    var hand = _hand()
    if hand != null and hand.mode == 1:
        hand.set_focus_target($ReferenceFrame/Header/AnchorBack)

func _on_back_unfocused() -> void:
    _back_rail.hide()
    _back.add_theme_color_override("font_color", Tokens.CREAM_DIM)

func _on_action_pressed() -> void:
    # START ENCOUNTER only acts with a valid fighter selected; the screen-level
    # state machine (main.gd) also coerces an invalid model back to a playable
    # id, so an invalid fighter can never launch.
    if _selected == "":
        return
    FrontendEvents.emit_confirm("story_start")

func _on_action_focused() -> void:
    # Structural focus signal (never color alone): a 2 px accent rule caps the
    # plate while the rail/action owns focus.
    _action_top_rule.show()
    var hand = _hand()
    if hand != null and hand.mode == 1:
        hand.set_focus_target(_anchor_action)

func _on_action_unfocused() -> void:
    _action_top_rule.hide()

# --- enemy presentation (Doc 07 §13) ----------------------------------------
func _build_enemy() -> void:
    _enemy_name.text = "BOBO"
    _enemy_health.text = "400 HP"
    _objective.text = "Defeat Bobo."
    _rule_stocks.text = "You have 3 stocks."
    _rule_behavior.text = "Bobo does not attack."
    _flavor.text = "A big goofball, and a very sturdy punching bag."
    var view = RenderViewScript.new()
    view.name = "EnemyRender"
    _presentation.add_child(view)
    view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    view.set_profile(RenderViewScript.PROFILE_PLAYER_BAY)
    view.set_subjects(["bobo"])
    view.request_render()
    var resolved := false
    for subject in view.subject_nodes():
        if is_instance_valid(subject) and subject.find_child("BoboVisual", true, false) != null:
            resolved = true
    _enemy_render_resolved = resolved
    if resolved:
        return
    view.queue_free()
    _build_enemy_nameplate()

func _build_enemy_nameplate() -> void:
    # Verified fallback: hard-edged typographic plate carrying the encounter
    # identity when the shared render view cannot resolve Bobo's encounter rig.
    var plate := Panel.new()
    plate.name = "BoboNameplate"
    plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
    plate.position = Vector2.ZERO
    plate.size = _presentation.size
    plate.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_FLAT))
    _presentation.add_child(plate)
    var rail := Panel.new()
    rail.name = "EnemyRail"
    rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
    rail.position = Vector2.ZERO
    rail.size = Vector2(3.0, plate.size.y)
    rail.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    plate.add_child(rail)
    var name_label := Label.new()
    name_label.name = "BoboName"
    name_label.text = "BOBO"
    name_label.position = Vector2(24.0, 88.0)
    name_label.size = Vector2(plate.size.x - 48.0, 60.0)
    name_label.add_theme_font_override("font", Tokens.font("bold"))
    name_label.add_theme_font_size_override("font_size", 48)
    name_label.add_theme_color_override("font_color", Tokens.CREAM)
    plate.add_child(name_label)
    var health := Label.new()
    health.name = "BoboHealth"
    health.text = "400 HP"
    health.position = Vector2(24.0, 152.0)
    health.size = Vector2(plate.size.x - 48.0, 30.0)
    health.add_theme_font_override("font", Tokens.font("medium"))
    health.add_theme_font_size_override("font_size", 20)
    health.add_theme_color_override("font_color", Tokens.ACCENT)
    plate.add_child(health)

# --- fighter selection (Doc 07 §14) -----------------------------------------
func build(playable_ids: Array = []) -> void:
    # Stable fighter ids only; the story entry owns which ids are playable.
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
    for i in _ids.size():
        var id := _ids[i]
        var tile = TileScene.instantiate()
        tile.name = "FighterTile%d" % i
        tile.position = Vector2(i * (TILE_W + TILE_GAP), 0.0)
        _roster_strip.add_child(tile)
        tile.set_tile_size(Vector2(TILE_W, TILE_H))
        tile.setup(id, Roster.display_name(id).to_upper(), PortraitData.portrait_texture(id))
        tile.focus_mode = Control.FOCUS_ALL
        tile.tile_pressed.connect(_select_by_id)
        tile.focus_entered.connect(_on_tile_focused.bind(i))
        tile.mouse_entered.connect(_select_by_id.bind(id))
        _tiles.append(tile)
    if _selected == "" or not _ids.has(_selected):
        set_selected_id("turbofit" if _ids.has("turbofit") else (_ids[0] if not _ids.is_empty() else ""))
    _refresh_selection()

func open(selected_id: String = "") -> void:
    _exiting = false
    _input_lock = 0.0
    _ready_state = true
    _body.show()
    _result_layer.hide()
    _action.text = "START ENCOUNTER"
    _back.text = "BACK"
    visible = true
    if selected_id != "":
        set_selected_id(selected_id)
    _refresh_selection()
    _refresh_focus_graph()
    var hand = _hand()
    if hand != null:
        hand.begin_screen("story")
        if hand.mode == 1 and not _tiles.is_empty():
            _tiles[_selected_index()].grab_focus()
            hand.set_focus_target(_tiles[_selected_index()].anchor())
    _entry()

func reset() -> void:
    # Called when the host screen leaves Story entirely: no lingering exit.
    _exiting = false
    _input_lock = 0.0
    _ready_state = true
    _body.show()
    _result_layer.hide()
    _action.text = "START ENCOUNTER"
    _back.text = "BACK"
    _action.disabled = false
    _refresh_selection()

func show_result(won: bool) -> void:
    # Lightweight Story result state (Doc 07 §16): distinct from Results.
    _ready_state = false
    _body.hide()
    _result_layer.show()
    # Wording contract: the result title keeps the shipped Story strings —
    # the literal lowercase win line and the loss retry wording.
    _verdict.text = "your pretty cool" if won else "TRY AGAIN"
    _verdict_detail.text = "BOBO DEFEATED" if won else "Out of stocks. Bobo is still standing."
    _action.text = "REPLAY" if won else "RETRY"
    _action.disabled = false
    _back.text = "MAIN MENU"
    _refresh_focus_graph()
    _action.grab_focus()
    var hand = _hand()
    if hand != null and hand.mode == 1:
        hand.set_focus_target(_anchor_action)

func set_selected_id(id: String) -> void:
    if id != "" and not _ids.has(id):
        # Unknown ids resolve to "nothing selected" — START stays inert.
        _selected = ""
    else:
        _selected = id
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
    if not _ready_state:
        return
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
    _action.disabled = not valid
    if _render_view != null and is_instance_valid(_render_view):
        if valid:
            _render_view.set_subjects([_selected])
            _render_view.request_render()
        else:
            _render_view.clear_subjects()
    _refresh_result_state()

func _refresh_result_state() -> void:
    # The result overlay is the only state that owns the body visibility; the
    # ready state keeps it closed (the host decides when the panel is shown).
    _result_layer.visible = not _ready_state

func _build_render_view_if_needed() -> void:
    if _render_view != null and is_instance_valid(_render_view):
        return
    _render_view = RenderViewScript.new()
    _render_view.name = "FighterRender"
    _render_holder.add_child(_render_view)
    _render_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _render_view.set_profile(RenderViewScript.PROFILE_PLAYER_BAY)

# --- focus graph (roster -> action -> Back, Doc 07 §8 / §20A) ---------------
func _refresh_focus_graph() -> void:
    var chain: Array = []
    if _ready_state:
        for tile in _tiles:
            chain.append(tile)
    chain.append(_action)
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
        tile.focus_neighbor_bottom = tile.get_path_to(_action)
    if not _tiles.is_empty():
        _back.focus_neighbor_left = _back.get_path_to(_tiles[_tiles.size() - 1])
        _action.focus_neighbor_top = _action.get_path_to(_tiles[0])
    _back.focus_neighbor_bottom = _back.get_path_to(_action)

# --- exit choreography -------------------------------------------------------
func play_exit() -> void:
    if _exiting:
        return
    _exiting = true
    _input_lock = EXIT_LOCK
    var tween := create_tween()
    tween.tween_property(_frame, "modulate:a", 0.0, EXIT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    tween.tween_callback(func() -> void: exit_finished.emit())

func is_exiting() -> bool:
    return _exiting

func get_input_lock() -> float:
    return _input_lock

func _process(delta: float) -> void:
    if _input_lock > 0.0:
        _input_lock = maxf(_input_lock - delta, 0.0)

func _entry() -> void:
    _frame.modulate.a = 0.0
    var tween := create_tween()
    tween.tween_property(_frame, "modulate:a", 1.0, ENTER_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# --- test surface (Doc 07 §20) ----------------------------------------------
func title_label() -> Label:
    # story_title follows the result wording, not the static header.
    return _verdict

func objective_label() -> Label:
    return _objective

func action_button() -> Button:
    return _action

func back_button() -> Button:
    return _back

func roster_tiles() -> Array:
    return _tiles.duplicate()

func roster_ids() -> Array:
    return _ids.duplicate()

func selected_fighter_id() -> String:
    return _selected

func render_view() -> Control:
    return _render_view

func enemy_render_resolved() -> bool:
    return _enemy_render_resolved

func enemy_nameplate() -> Control:
    return _presentation.find_child("BoboNameplate", true, false)

func _hand():
    var cursor = get_node_or_null("/root/Cursor")
    if cursor == null or cursor.hand == null:
        return null
    return cursor.hand
