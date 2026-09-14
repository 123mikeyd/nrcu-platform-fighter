extends Control
# Story Result — compact Story-only outcome surface (Doc 05 §136-159).
# It is not the multiplayer Results screen. Actions are explicit semantic
# requests: Replay/Retry, Change Fighter, and Main Menu. MatchFlow owns routing.

signal replay_requested(fighter_id: String)
signal change_fighter_requested
signal menu_requested
signal exit_finished

const Tokens = preload("res://scripts/ui_tokens.gd")
const Roster = preload("res://scripts/roster.gd")
const RenderViewScript = preload("res://scripts/frontend/fighter_render_view.gd")
const Factory = preload("res://scripts/frontend/fighter_presentation_factory.gd")
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")

const EXIT_SECONDS := 13.0 / 60.0
const ENTER_SECONDS := 10.0 / 60.0

var _fighter_id := ""
var _won := false
var _exiting := false
var _render_view: Control = null

@onready var _field: Panel = $Field
@onready var _frame: Control = $ReferenceFrame
@onready var _title: Label = $ReferenceFrame/Header/Title
@onready var _step: Label = $ReferenceFrame/Header/StepLabel
@onready var _back: Button = $ReferenceFrame/Header/BackAction
@onready var _back_rail: Panel = $ReferenceFrame/Header/BackRail
@onready var _verdict_rule: Panel = $ReferenceFrame/ResultBody/VerdictRule
@onready var _verdict: Label = $ReferenceFrame/ResultBody/Verdict
@onready var _detail: Label = $ReferenceFrame/ResultBody/Detail
@onready var _fighter_label: Label = $ReferenceFrame/ResultBody/FighterLabel
@onready var _render_holder: Control = $ReferenceFrame/ResultBody/RenderHolder
@onready var _replay: Button = $ReferenceFrame/ReplayButton
@onready var _change_fighter: Button = $ReferenceFrame/ChangeFighterButton
@onready var _menu: Button = $ReferenceFrame/MenuButton
@onready var _replay_rule: Panel = $ReferenceFrame/ReplayRule
@onready var _change_rule: Panel = $ReferenceFrame/ChangeRule
@onready var _menu_rule: Panel = $ReferenceFrame/MenuRule
@onready var _anchor_replay: Control = $ReferenceFrame/AnchorReplay
@onready var _anchor_change: Control = $ReferenceFrame/AnchorChangeFighter
@onready var _anchor_menu: Control = $ReferenceFrame/AnchorMenu

func _ready() -> void:
	theme = Tokens.make_theme()
	_style()
	_wire()
	_build_render_view()
	_refresh_focus_graph()

func _style() -> void:
	_field.add_theme_stylebox_override("panel", Tokens.flat(Tokens.BASE))
	for label in [_title, _verdict, _fighter_label]:
		label.add_theme_font_override("font", Tokens.font("semibold"))
		label.add_theme_color_override("font_color", Tokens.CREAM)
	_step.add_theme_font_override("font", Tokens.font("medium"))
	_step.add_theme_color_override("font_color", Tokens.CREAM_DIM)
	_detail.add_theme_font_override("font", Tokens.font("medium"))
	_detail.add_theme_color_override("font_color", Tokens.CREAM_DIM)
	_verdict_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE_WARM))
	for button in [_replay, _change_fighter, _menu]:
		Tokens.apply_styles(button, {
			"normal": Tokens.flat(Tokens.SURFACE_1),
			"hover": Tokens.flat(Tokens.SURFACE_2),
			"pressed": Tokens.flat(Tokens.SURFACE_2),
			"focus": Tokens.flat(Tokens.SURFACE_2),
		})
		button.add_theme_font_override("font", Tokens.font("semibold"))
		button.add_theme_color_override("font_color", Tokens.CREAM)
		button.add_theme_color_override("font_hover_color", Tokens.CREAM)
		button.add_theme_color_override("font_focus_color", Tokens.CREAM)
	for rule in [_replay_rule, _change_rule, _menu_rule]:
		rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
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

func _wire() -> void:
	_replay.pressed.connect(_on_replay_pressed)
	_change_fighter.pressed.connect(_on_change_fighter_pressed)
	_menu.pressed.connect(_on_menu_pressed)
	_back.pressed.connect(_on_menu_pressed)
	for button in [_replay, _change_fighter, _menu, _back]:
		button.focus_entered.connect(_on_focus_entered.bind(button))
		button.focus_exited.connect(_on_focus_exited.bind(button))
	if not FrontendInput.confirm_pressed.is_connected(_on_semantic_accept):
		FrontendInput.confirm_pressed.connect(_on_semantic_accept)
	if not FrontendInput.cancel_pressed.is_connected(_on_semantic_cancel):
		FrontendInput.cancel_pressed.connect(_on_semantic_cancel)

func _on_semantic_accept() -> void:
	if not is_visible_in_tree() or _exiting:
		return
	# Native buttons own ui_accept; the service signal is only needed for the
	# hand feedback and for custom controls on other screens.

func _on_semantic_cancel() -> void:
	if is_visible_in_tree() and not _exiting:
		_on_menu_pressed()

func _on_replay_pressed() -> void:
	if not _exiting:
		replay_requested.emit(_fighter_id)

func _on_change_fighter_pressed() -> void:
	if not _exiting:
		change_fighter_requested.emit()

func _on_menu_pressed() -> void:
	if not _exiting:
		menu_requested.emit()

func _on_focus_entered(button: Button) -> void:
	FocusGraph.track(self, button)
	for rule in [_replay_rule, _change_rule, _menu_rule]:
		rule.hide()
	if button == _replay:
		_replay_rule.show()
	elif button == _change_fighter:
		_change_rule.show()
	elif button == _menu:
		_menu_rule.show()
	elif button == _back:
		_back_rail.show()
	var hand = _hand()
	if hand != null and hand.mode == 1:
		var anchor := focus_anchor_for(button)
		if anchor != null:
			hand.set_focus_target(anchor)

func _on_focus_exited(button: Button) -> void:
	if button == _back:
		_back_rail.hide()
	else:
		if button == _replay:
			_replay_rule.hide()
		elif button == _change_fighter:
			_change_rule.hide()
		elif button == _menu:
			_menu_rule.hide()

func present(won: bool, fighter_id: String) -> void:
	_won = won
	_fighter_id = fighter_id
	_exiting = false
	visible = true
	_verdict.text = "YOU'RE PRETTY COOL" if won else "TRY AGAIN"
	_detail.text = "BOBO DEFEATED" if won else "Out of stocks. Bobo is still standing."
	_fighter_label.text = Roster.display_name(fighter_id).to_upper() if fighter_id != "" else "YOUR FIGHTER"
	_replay.text = "REPLAY" if won else "RETRY"
	_back.text = "BACK TO MAIN"
	_refresh_render()
	_refresh_focus_graph()
	_replay.grab_focus()
	var hand = _hand()
	if hand != null and hand.mode == 1:
		hand.begin_screen("story_result")
		hand.set_focus_target(_anchor_replay)
	_entry()

func reset() -> void:
	_exiting = false
	modulate.a = 1.0
	_replay_rule.hide()
	_change_rule.hide()
	_menu_rule.hide()

func play_exit() -> void:
	if _exiting:
		return
	_exiting = true
	var tween := create_tween()
	tween.tween_property(_frame, "modulate:a", 0.0, EXIT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: exit_finished.emit())

func is_exiting() -> bool:
	return _exiting

func replay_button() -> Button:
	return _replay

func change_fighter_button() -> Button:
	return _change_fighter

func menu_button() -> Button:
	return _menu

func action_button() -> Button:
	return _replay

func back_button() -> Button:
	return _back

func title_label() -> Label:
	return _verdict

func detail_label() -> Label:
	return _detail

func selected_fighter_id() -> String:
	return _fighter_id

func action_chain() -> Array:
	return [_replay, _change_fighter, _menu]

func render_view() -> Control:
	return _render_view

func focus_anchor_for(control: Control) -> Control:
	if control == _replay:
		return _anchor_replay
	if control == _change_fighter:
		return _anchor_change
	if control == _menu:
		return _anchor_menu
	if control == _back:
		return $ReferenceFrame/Header/AnchorBack
	return FocusGraph.anchor_of(control)

func _refresh_focus_graph() -> void:
	var chain: Array = [_replay, _change_fighter, _menu, _back]
	for i in chain.size():
		var control: Control = chain[i]
		control.focus_next = control.get_path_to(chain[(i + 1) % chain.size()])
		control.focus_previous = control.get_path_to(chain[(i - 1 + chain.size()) % chain.size()])
		control.focus_neighbor_left = control.get_path_to(chain[(i - 1 + chain.size()) % chain.size()])
		control.focus_neighbor_right = control.get_path_to(chain[(i + 1) % chain.size()])

func _build_render_view() -> void:
	_render_view = RenderViewScript.new()
	_render_view.name = "FighterRender"
	_render_holder.add_child(_render_view)
	_render_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_render_view.set_profile(RenderViewScript.PROFILE_RESULTS_HERO)
	_render_view.set_presentation_mode(Factory.MODE_LIVE_IDLE)

func _refresh_render() -> void:
	if _render_view == null or not is_instance_valid(_render_view):
		return
	if _fighter_id != "":
		_render_view.set_subjects([_fighter_id])
		_render_view.request_render()
	else:
		_render_view.clear_subjects()

func _entry() -> void:
	_frame.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_frame, "modulate:a", 1.0, ENTER_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _hand():
	var cursor = get_node_or_null("/root/Cursor")
	if cursor == null or cursor.hand == null:
		return null
	return cursor.hand
