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
# selected fighter + the enemy are presented through FighterRenderView, which
# resolves every subject through FighterPresentationFactory. The encounter's
# Bobo is scripts/bobo_fighter.gd + scripts/bobo_visual.gd and the factory
# builds THAT rig for the "bobo" id, so the enemy hero renders in 3D (WP-3:
# Bobo actually renders; the nameplate below is a defensive fallback only,
# asserted not to trigger by tests/test_fighter_presentation.gd).

signal chosen(id: String)
signal start_requested(fighter_id: String)
signal back_requested
signal replay_requested(fighter_id: String)
signal change_fighter_requested
signal menu_requested
signal exit_finished

const Tokens = preload("res://scripts/ui_tokens.gd")
const Roster = preload("res://scripts/roster.gd")
const PortraitData = preload("res://scripts/frontend/portrait_data.gd")
const RenderViewScript = preload("res://scripts/frontend/fighter_render_view.gd")
const Factory = preload("res://scripts/frontend/fighter_presentation_factory.gd")
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")

const TILE_W := 90.0
const TILE_H := 72.0
const TILE_GAP := 8.0
const EXIT_SECONDS := 13.0 / 60.0
const ENTER_SECONDS := 10.0 / 60.0
const EXIT_LOCK := 0.5

var _ids: Array[String] = []
var _tiles: Array = []
var _compat_source: Control = null
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
    _action.pressed.connect(_on_action_pressed)
    _action.focus_entered.connect(_on_action_focused)
    _action.focus_exited.connect(_on_action_unfocused)
    # Doc 03 §7: activation and cancel reach this screen through the semantic
    # input service — never through ad-hoc key decoding.
    if not FrontendInput.confirm_pressed.is_connected(_on_semantic_accept):
        FrontendInput.confirm_pressed.connect(_on_semantic_accept)
    if not FrontendInput.cancel_pressed.is_connected(_on_semantic_cancel):
        FrontendInput.cancel_pressed.connect(_on_semantic_cancel)

func _on_semantic_accept() -> void:
    # §7: the roster tiles are CUSTOM Controls, so the semantic accept must
    # reach them here (the engine cannot activate a FighterTile by itself).
    # Enter / Space / controller A on a focused tile performs exactly the same
    # selection as a mouse click on it.
    if not is_visible_in_tree() or not _ready_state or _exiting:
        return
    if FrontendInput.confirm_source() == FrontendInput.SOURCE_MOUSE:
        return
    var focused := FrontendInput.focus_owner()
    var index: int = _tiles.find(focused)
    if index >= 0:
        _select_by_id(_ids[index])
        return
    # Back and START ENCOUNTER are native Buttons: their own semantic
    # ui_accept path owns them.

func _on_semantic_cancel() -> void:
    # §11 Back matrix: the briefing's ui_cancel takes the visible Back route.
    if not is_visible_in_tree() or _exiting:
        return
    _on_back_pressed()

func _on_back_pressed() -> void:
    FrontendEvents.emit_back("story")
    if _ready_state:
        back_requested.emit()
    else:
        menu_requested.emit()

func _on_back_focused() -> void:
    FocusGraph.track(self, _back)
    var hand = _hand()
    if hand != null and hand.mode == 1:
        hand.set_focus_target(FocusGraph.anchor_of(_back))

func _on_action_pressed() -> void:
    # START ENCOUNTER only acts with a valid fighter selected; the screen-level
    # state machine (main.gd) also coerces an invalid model back to a playable
    # id, so an invalid fighter can never launch.
    if _selected == "":
        return
    if _ready_state:
        FrontendEvents.emit_confirm("story_start")
        start_requested.emit(_selected)
    else:
        FrontendEvents.emit_confirm("story_replay")
        replay_requested.emit(_selected)

func _on_action_focused() -> void:
    # Structural focus signal (never color alone): a 2 px accent rule caps the
    # plate while the rail/action owns focus.
    FocusGraph.track(self, _action)
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
    _rule_behavior.text = "Bobo uses slow two-hit claws."
    _flavor.text = "A big goofball, and a very sturdy punching bag."
    var view = RenderViewScript.new()
    view.name = "EnemyRender"
    _presentation.add_child(view)
    view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    view.set_profile(RenderViewScript.PROFILE_PLAYER_BAY)
    # The encounter hero is a live showcase while the briefing is visible
    # (Doc 07 §3, ledger C-046); Bobo's GLB Idle clip is the approved UI idle
    # for an encounter subject. Hidden -> the view parks itself (frozen pose).
    view.set_presentation_mode(RenderViewScript.MODE_LIVE_IDLE)
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
    _refresh_focus_graph()
    _action.grab_focus()
    var hand = _hand()
    if hand != null and hand.mode == 1:
        hand.set_focus_target(_anchor_action)
    _ensure_focus_alive()

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
    if index < 0 or index >= _tiles.size():
        return
    FocusGraph.track(self, _tiles[index])
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
    # Doc 07 §3 / ledger C-046: the selected fighter is a live showcase while
    # the briefing is visible; the view parks itself when hidden.
    _render_view.set_presentation_mode(Factory.MODE_LIVE_IDLE)

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
    # §6 recovery: the body/result swap hides a whole zone; a hidden control
    # never keeps the focus and the hand retargets immediately.
    _ensure_focus_alive()

func _ensure_focus_alive() -> void:
    if not is_inside_tree():
        return
    var before := FrontendInput.focus_owner()
    var owner := FocusGraph.recover(get_viewport(), self, func() -> Control:
        return _action if not _ready_state else _back)
    if owner != null and owner != before:
        var hand = _hand()
        if hand != null and hand.mode == 1:
            var anchor := focus_anchor_for(owner)
            if anchor != null:
                hand.set_focus_target(anchor)

func focus_anchor_for(control: Control) -> Control:
    # The authored hand target of a focusable control on this screen (Doc 03 §6).
    if control == _action:
        return _anchor_action
    if control == _back:
        return FocusGraph.anchor_of(_back)
    var index: int = _tiles.find(control)
    if index >= 0:
        return _tiles[index].anchor()
    return FocusGraph.anchor_of(control)

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
    if _compat_source != null and is_instance_valid(_compat_source):
        return _compat_source.roster_tiles()
    return _tiles.duplicate()

func roster_ids() -> Array:
    if _compat_source != null and is_instance_valid(_compat_source):
        return _compat_source.roster_ids()
    return _ids.duplicate()

func set_compat_source(source: Control) -> void:
    # The Briefing no longer embeds the roster. This narrow read-only bridge keeps
    # the pre-WP-4 test surface able to inspect the shared Story Select tiles
    # without reintroducing a second selection owner or visible roster strip.
    _compat_source = source

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
