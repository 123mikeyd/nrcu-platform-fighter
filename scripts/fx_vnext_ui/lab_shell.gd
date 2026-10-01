extends Control
# NRCU FX Lab vNext — workspace shell (specs/01).
#
# Browser / Preview / Right Dock (Target Status + Layers + Inspector) /
# Timeline with splitters, panel collapse, workspace persistence and a
# responsive toolbar. This is the Phase-1 workspace; authoring systems
# (layers, drafts, resolver) land in later phases and plug into the same shell.

const UiTokens := preload("res://scripts/ui_tokens.gd")
const WorkspaceStateScript := preload("res://scripts/fx_vnext_ui/workspace_state.gd")
const TargetBrowserScript := preload("res://scripts/fx_vnext_ui/target_browser.gd")
const ScreenRuntimeScript := preload("res://scripts/fx_vnext/fx_screen_runtime.gd")
const FxTargetsScript := preload("res://scripts/fx_vnext/fx_targets.gd")
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxProductionScript := preload("res://scripts/fx_vnext/fx_production.gd")
const FxDraftsScript := preload("res://scripts/fx_vnext/fx_drafts.gd")
const FxSessionScript := preload("res://scripts/fx_vnext/fx_session.gd")
const FxLayerRendererScript := preload("res://scripts/fx_vnext/fx_layer_renderer.gd")
const FxAssetsScript := preload("res://scripts/fx_vnext/fx_assets.gd")
const FxCostScript := preload("res://scripts/fx_vnext/fx_cost.gd")
const FxTemplatesScript := preload("res://scripts/fx_vnext/fx_templates.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")
const FxLayerRowScript := preload("res://scripts/fx_vnext_ui/fx_layer_row.gd")
const FxPlaneSectionScript := preload("res://scripts/fx_vnext_ui/fx_plane_section.gd")
const FxLabUiTokensScript := preload("res://scripts/fx_vnext_ui/fx_lab_ui_tokens.gd")

const TIMELINE_LEN := 2.4
const FRAME_STEP := 1.0 / 30.0
const AUTO_RAIL_WIDTH := 1440.0
const AUTO_TIMELINE_COLLAPSE_HEIGHT := 800.0
const ADD_LAYER_TEMPLATES := ["Source Copy", "Custom FX Layer"]
const ADD_EFFECT_TEMPLATES := ["Outer Halo", "Edge Treatment", "RGB Tear", "Dither Treatment"]

var ws
var runtime
var selected_key := ""
var event_marks: Dictionary = {}
var time_syncing := false
var _authoring_playhead := 0.0
var _dragging := ""
var _selecting := false
var _focus_originals: Dictionary = {}
var _ui_transactions: Dictionary = {}

# authoring session (stream A/E integration)
var production
var drafts
var session
var preview_mode := "WORKING"
var preview_toggle: Button
var review_button: Button
var _plan_status: Dictionary = {}
var delete_panel: PanelContainer
var delete_look_id := ""
var review_panel: PanelContainer
var review_look_id := ""
var review_ack_field: LineEdit
var delete_overlay: Control
var review_overlay: Control
var modal_cancel_button: Button
var layer_clipboard: Dictionary = {}
var debug_view := "COMPOSITE"
var debug_badge: Label
var _timeline_label_rects: Array = []

const TOKEN_DISPLAY := {
	"ORIGINAL_SOURCE": "Original Source",
	"TRANSFORMED_SOURCE": "Transformed Source",
	"LAYER_BELOW": "Layer Below (offscreen input)",
	"COMPOSITE_BELOW": "Composite Below (offscreen input)",
	"TARGET_UNDERLAY": "Behind Target",
	"TARGET_SOURCE": "On Target",
	"TARGET_OVERLAY": "In Front of Target",
	"COMPOSITION_BACKGROUND": "Behind Everything",
	"COMPOSITION_FOREGROUND": "In Front of Everything",
	"NORMAL": "Normal",
	"ADD": "Add",
	"MULTIPLY": "Multiply",
	"SCREEN": "Screen",
	"OVERLAY": "Overlay",
	"SOFT_LIGHT": "Soft Light",
	"ORIGINAL_SOURCE_ALPHA": "Original Source Alpha",
	"POST_DISPLACEMENT_ALPHA": "Post-Displacement Alpha",
	"CUSTOM_MASK": "Custom Mask",
	"NONE": "None",
	"FULL": "Full",
	"EDGE_BAND": "Edge Band",
	"INNER_BAND": "Inner Band",
	"OUTER_BAND": "Outer Band",
	"SOURCE_SPACE": "Source Space",
	"LAYER_SPACE": "Layer Space",
	"PRESENTATION_SPACE": "Presentation Space",
	"NOISE": "Noise",
	"WAVE": "Wave",
	"FLOW": "Flow",
	"TRANSPARENT": "Transparent",
	"WRAP": "Wrap",
	"CLAMP": "Clamp",
	"COMPOSITE": "Composite",
	"BASE": "Base",
	"EFFECT": "Effect",
	"EDGE": "Edge",
	"COVERAGE": "Coverage",
	"MASK": "Mask",
	"DRIVER": "Driver",
}

static func display_token(token: String) -> String:
	if TOKEN_DISPLAY.has(token):
		return str(TOKEN_DISPLAY[token])
	return token.to_lower().capitalize()

func _tab_page(tab_pages_ref: Dictionary, tab_name: String) -> VBoxContainer:
	if tab_pages_ref.has(tab_name):
		var page: Variant = tab_pages_ref[tab_name]
		if page is VBoxContainer:
			return page as VBoxContainer
	return null

func _tab_page_add(tab_pages_ref: Dictionary, tab_name: String, child: Node) -> void:
	var page: VBoxContainer = _tab_page(tab_pages_ref, tab_name)
	if page == null or child == null:
		return
	page.add_child(child)
var _native_pointer_acquired := false
var renderer
var lab_theme: Theme
var _popup_contracts: Array[PopupMenu] = []
var _rendered_key := ""
var _stash_at := 0.0
var _stash_pending := false
var _badge_cache: Dictionary = {}
var _badge_cache_at := -100.0

# toolbar
var toolbar: HBoxContainer
var brand_label: Label
var play_button: Button
var time_spin: SpinBox
var overflow_button: MenuButton
var remount_button: Button
var browser_toggle: Button
var inspector_toggle: Button
var timeline_toggle: Button
var reset_workspace_button: Button

# body
var body: HBoxContainer
var browser_panel: PanelContainer
var browser: Node
var browser_rail: Button
var left_handle: ColorRect
var preview_area: VBoxContainer
var breadcrumb_label: Label
var open_browser_button: Button
var focus_buttons: Dictionary = {}
var viewport_host: Control
var disp: SubViewportContainer
var selection_outline: ReferenceRect
var right_handle: ColorRect
var dock: Control
var dock_panel: PanelContainer
var dock_host: Control
var dock_box: VBoxContainer
var status_title: Label
var status_badge: Label
var status_detail: Label
var protected_banner: Label
var protected_banner_host: Control
var assignment_scope_option: OptionButton
var assignment_scope_count: Label
var assignment_scope_status: Label
var assignment_scope_advanced: VBoxContainer
var assignment_scope_fields: Dictionary = {}
var layers_box: VBoxContainer
var inspector_box: VBoxContainer
var authoring_tabs: TabContainer
var recipes_tab: ScrollContainer
var production_tab: ScrollContainer
var layers_split_handle: ColorRect
var layers_rows: VBoxContainer
var layers_empty: Label
var add_menu: MenuButton
var add_layer_menu: MenuButton
var add_effect_menu: MenuButton
var recipe_add_buttons: Array = []
var recipe_filter: OptionButton
var recipe_selector: OptionButton
var recipe_group_labels: Dictionary = {}
var recipe_cards: Dictionary = {}
var recipe_ids_by_group: Dictionary = {}
var recipe_names: Dictionary = {}
var inspector_content: VBoxContainer
var inspector_scroll: ScrollContainer
var _inspector_tab_name := ""
var _inspector_scroll_value := 0.0
var inspector_empty: Label
var selected_layer_id := ""
var action_save: Button
var action_apply: Button
var action_styling: Button
var action_unassign: Button
var action_unique: Button
var action_edit_shared: Button
var action_why: Button
var action_more_menu: MenuButton
var target_action_row: HBoxContainer
var target_action_row2: HBoxContainer
var protected_actions_host: Control
var protected_actions_spacer: Control
var target_action_row3: HBoxContainer
var action_status: Label
var why_label: Label
var why_actions: VBoxContainer
var why_open := false
var library_rows: VBoxContainer
var recipe_rows: VBoxContainer
var inspector_cost_badge: Label
var layers_cost_label: Label
var study_mode := "OFF"
var preset_authoring: Button
var preset_preview: Button
var study_buttons: Dictionary = {}
var undo_button: Button
var redo_button: Button

# timeline
var timeline_panel: PanelContainer
var timeline_toggle_button: Button
var timeline_time_label: Label
var timeline_ruler: TimelineRuler
var timeline_resize_handle: ColorRect

var _timing_retired := true # P0: timing tables live in FxScreenRuntime now

func _native_pointer_service() -> Node:
	if not is_inside_tree() or get_tree() == null:
		return null
	return get_tree().root.get_node_or_null("Cursor")

func _acquire_native_pointer() -> void:
	if _native_pointer_acquired:
		return
	var cursor := _native_pointer_service()
	if cursor == null or not cursor.has_method("acquire_native_pointer"):
		return
	# Cursor owns the claim by object identity. Keep this shell as the stable
	# owner across runtime.mount() calls; never release from a remount path.
	_native_pointer_acquired = bool(cursor.call("acquire_native_pointer", self))

func _release_native_pointer() -> void:
	if not _native_pointer_acquired:
		return
	var cursor := _native_pointer_service()
	_native_pointer_acquired = false
	if cursor != null and cursor.has_method("release_native_pointer"):
		cursor.call("release_native_pointer", self)

func _exit_tree() -> void:
	# queue_free, scene replacement, and explicit teardown all converge here.
	# The local flag makes repeated lifecycle notifications harmless.
	_release_native_pointer()

func _ready() -> void:
	_acquire_native_pointer()
	# R3 §17: the workspace layout guarantees every primary control is inside the
	# window at >= 1280x720 (progressive collapse below 1440; at 1280 every
	# primary control fits with the brand hidden). Enforce that floor at the OS
	# level so a window can never be sized into an overflowing state.
	var win := get_window()
	if win != null:
		win.min_size = Vector2i(1280, 720)
	ws = WorkspaceStateScript.new()
	ws.load_state()
	pass # P0: timing loads retired (FxScreenRuntime.event_marks owns them)
	runtime = ScreenRuntimeScript.new()
	production = FxProductionScript.new()
	var data_override := OS.get_environment("NRCU_FX_DATA_DIR")
	if data_override != "":
		production.data_dir = data_override
	production.recover_if_needed()  # R3 §8: strict last-known-good crash recovery at boot
	drafts = FxDraftsScript.new()
	var draft_override := OS.get_environment("NRCU_FX_DRAFT_DIR")
	if draft_override != "":
		drafts.base_dir = draft_override
	session = FxSessionScript.new(production, drafts)
	lab_theme = FxLabUiTokensScript.make_theme()
	theme = lab_theme
	_build()
	call_deferred("_apply_lab_ui_contract")
	_update_pixel_space()
	disp.add_child(runtime.subvp)
	runtime.mount("1v1", "debug", "ice_mage", "doge_man")
	event_marks = _compute_event_marks()
	browser.setup(runtime, Callable(self, "_status_badge_for"))
	browser.target_selected.connect(_on_target_selected)
	browser.remount_requested.connect(_on_remount_requested)
	browser.refresh_context()
	resized.connect(_on_resized)
	get_window().size_changed.connect(_on_window_size_changed)
	_apply_state()
	_on_resized()
	_apply_preview_focus()
	_refresh_selection_ui()

func _on_window_size_changed() -> void:
	_update_pixel_space()
	if body != null:
		_on_resized()

func _update_pixel_space() -> void:
	# The project uses canvas_items stretch, so the engine scales the whole
	# UI whenever the window differs from the stretch base. The lab is a
	# desktop authoring tool: it lays out in native window pixels instead
	# (specs/01 responsive acceptance), by counter-scaling itself against
	# the REAL canvas transform — never a hardcoded base resolution (a stale
	# 1600x900 assumption once zoomed the whole shell to 125% at 1280x720).
	# Net rendering scale is 1:1; input coordinates stay pixel-true.
	if not is_inside_tree():
		return
	# Window.size is the logical client canvas used by Control layout. The
	# DisplayServer value is physical/DPI-scaled on Windows and made the shell
	# wider than its actual viewport (the right dock and primary actions fell
	# outside a nominal 1280px window).
	var win := Vector2(get_window().size) if get_window() != null else get_viewport().get_visible_rect().size
	if win.x < 10.0 or win.y < 10.0:
		return
	var engine_scale := get_tree().root.get_final_transform().get_scale()
	var s := minf(engine_scale.x, engine_scale.y)
	if s <= 0.0 or not is_finite(s):
		return
	var counter := 1.0 / s
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = win
	scale = Vector2(counter, counter)

# ================================================================ UI build

func _build() -> void:
	var background := ColorRect.new()
	background.color = UiTokens.BG_DEEP
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	add_child(col)

	_build_toolbar(col)

	body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	col.add_child(body)

	_build_browser()
	left_handle = _make_handle(Control.CURSOR_HSIZE)
	left_handle.gui_input.connect(func(event: InputEvent) -> void: _handle_drag(event, "browser"))
	body.add_child(left_handle)

	_build_preview()

	right_handle = _make_handle(Control.CURSOR_HSIZE)
	right_handle.gui_input.connect(func(event: InputEvent) -> void: _handle_drag(event, "dock"))
	body.add_child(right_handle)

	_build_dock()
	_build_timeline(col)

func _build_toolbar(parent: Node) -> void:
	toolbar = HBoxContainer.new()
	toolbar.custom_minimum_size.y = 44
	toolbar.add_theme_constant_override("separation", 6)
	parent.add_child(toolbar)

	brand_label = Label.new()
	brand_label.text = "NRCU FX LAB · vNEXT"
	brand_label.add_theme_font_size_override("font_size", UiTokens.T_META)
	brand_label.add_theme_color_override("font_color", UiTokens.ACCENT)
	brand_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toolbar.add_child(brand_label)

	_toolbar_group_label("TRANSPORT")
	_toolbar_button("⏮ START", _transport_to_start)
	play_button = _toolbar_button("⏸ PAUSE", _toggle_transport)
	_toolbar_button("◀ 1F", _transport_step_back)
	_toolbar_button("1F ▶", _transport_step_forward)
	_toolbar_button("FX PEAK", _transport_to_fx_peak)

	var time_tag := Label.new()
	time_tag.text = "T"
	time_tag.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	time_tag.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	time_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toolbar.add_child(time_tag)
	time_spin = SpinBox.new()
	time_spin.min_value = 0.0
	time_spin.max_value = TIMELINE_LEN
	time_spin.step = 0.001
	time_spin.custom_minimum_size.x = 96
	time_spin.value_changed.connect(_on_time_entered)
	toolbar.add_child(time_spin)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_toolbar_group_label("VIEW")
	browser_toggle = _toolbar_button("◧ BROWSER", _toggle_browser)
	inspector_toggle = _toolbar_button("◨ INSPECTOR", _toggle_dock)
	timeline_toggle = _toolbar_button("▤ TIMELINE", _toggle_timeline_expanded)
	reset_workspace_button = _toolbar_button("RESET WORKSPACE", _reset_workspace)
	reset_workspace_button.visible = false
	preset_authoring = _toolbar_button("LAYOUT: AUTHORING", func() -> void: _apply_workspace_preset("AUTHORING"))
	preset_preview = _toolbar_button("LAYOUT: FOCUS", func() -> void: _apply_workspace_preset("FOCUS"))

	remount_button = _toolbar_button("⟲ REMOUNT", _remount_current)
	review_button = _toolbar_button("⚠ REVIEW", _open_migration_review_queue)
	_toolbar_group_label("STATE")
	preview_toggle = _toolbar_button("STATE: WORKING", _toggle_preview_mode)
	overflow_button = MenuButton.new()
	overflow_button.text = "⋯"
	overflow_button.custom_minimum_size.x = 40
	overflow_button.add_theme_font_size_override("font_size", UiTokens.T_META)
	# Items are rebuilt by _toolbar_overflow() (dynamic overflow set);
	# dispatch lives in _on_toolbar_overflow_chosen (single connection).
	toolbar.add_child(overflow_button)

func _toolbar_group_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", FxLabUiTokensScript.TEXT_MUTED)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.tooltip_text = text.capitalize() + " controls"
	toolbar.add_child(label)

func _toolbar_button(text: String, callback: Callable) -> Button:
	var button := _styled_button(text, callback)
	toolbar.add_child(button)
	return button

func _styled_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	FxLabUiTokensScript.apply_hit_target(button)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(callback)
	return button

func _build_browser() -> void:
	browser_panel = PanelContainer.new()
	browser_panel.custom_minimum_size.x = 240
	browser_panel.add_theme_stylebox_override("panel", UiTokens.flat(UiTokens.BASE, UiTokens.RULE, UiTokens.STROKE, 0))
	body.add_child(browser_panel)

	var browser_margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		browser_margin.add_theme_constant_override(side, 8)
	browser_panel.add_child(browser_margin)

	browser = TargetBrowserScript.new()
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser_margin.add_child(browser)

	browser_rail = Button.new()
	browser_rail.text = "▸"
	browser_rail.tooltip_text = "Show target browser"
	browser_rail.visible = false
	browser_rail.custom_minimum_size.x = 28
	browser_rail.pressed.connect(_toggle_browser)
	browser_panel.add_child(browser_rail)

func _build_preview() -> void:
	preview_area = VBoxContainer.new()
	preview_area.custom_minimum_size.x = 0.0
	preview_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_area.add_theme_constant_override("separation", 4)
	body.add_child(preview_area)

	var crumb_row := HBoxContainer.new()
	crumb_row.add_theme_constant_override("separation", 6)
	preview_area.add_child(crumb_row)
	breadcrumb_label = Label.new()
	breadcrumb_label.text = "NO TARGET SELECTED"
	breadcrumb_label.add_theme_font_size_override("font_size", UiTokens.T_META)
	breadcrumb_label.add_theme_color_override("font_color", UiTokens.CREAM)
	breadcrumb_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	breadcrumb_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crumb_row.add_child(breadcrumb_label)
	open_browser_button = Button.new()
	open_browser_button.name = "OpenBrowserButton"
	open_browser_button.text = "OPEN BROWSER"
	open_browser_button.tooltip_text = "Select a target to start designing FX"
	FxLabUiTokensScript.apply_hit_target(open_browser_button)
	open_browser_button.pressed.connect(_open_browser_from_empty)
	crumb_row.add_child(open_browser_button)
	for mode in ["NORMAL", "DIM OTHERS", "SOLO"]:
		var button := Button.new()
		button.text = mode
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		button.pressed.connect(func() -> void: _set_preview_focus(mode))
		crumb_row.add_child(button)
		focus_buttons[mode] = button
	for zoom in ["100%", "200%", "400%"]:
		var sbutton := Button.new()
		sbutton.text = "⌕ " + zoom
		sbutton.toggle_mode = true
		sbutton.tooltip_text = "Study zoom (authoring-neutral)"
		sbutton.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		sbutton.pressed.connect(func() -> void: _set_study(zoom))
		crumb_row.add_child(sbutton)
		study_buttons[zoom] = sbutton

	viewport_host = Control.new()
	viewport_host.custom_minimum_size.x = 0.0
	viewport_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_host.clip_contents = true
	preview_area.add_child(viewport_host)
	var viewport_bg := Panel.new()
	viewport_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_bg.add_theme_stylebox_override("panel", UiTokens.flat(UiTokens.BG_DEEP, UiTokens.RULE, UiTokens.STROKE, UiTokens.RADIUS_FRAME))
	viewport_host.add_child(viewport_bg)

	disp = SubViewportContainer.new()
	disp.size = Vector2(1280, 720)
	disp.stretch = false
	disp.mouse_filter = Control.MOUSE_FILTER_STOP
	disp.gui_input.connect(_on_preview_input)
	viewport_host.add_child(disp)

	selection_outline = ReferenceRect.new()
	selection_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_outline.border_color = Color(0.90, 0.68, 0.41, 0.95)
	selection_outline.border_width = 2.0
	selection_outline.editor_only = false
	selection_outline.visible = false
	viewport_host.add_child(selection_outline)
	# UI-04: persistent debug-view badge so a debug visualization can never be
	# mistaken for the production composition.
	debug_badge = Label.new()
	debug_badge.text = ""
	debug_badge.add_theme_font_size_override("font_size", UiTokens.T_META)
	debug_badge.add_theme_color_override("font_color", Color(1.0, 0.45, 0.2))
	debug_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	debug_badge.position = Vector2(10, 8)
	debug_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_badge.visible = false
	viewport_host.add_child(debug_badge)

func _build_dock() -> void:
	dock_host = Control.new()
	dock_host.custom_minimum_size.x = 320
	dock_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(dock_host)
	dock = Control.new()
	dock.custom_minimum_size.x = 0
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.clip_contents = true
	dock_host.add_child(dock)
	dock_panel = PanelContainer.new()
	dock_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock_panel.add_theme_stylebox_override("panel", UiTokens.flat(UiTokens.BASE, UiTokens.RULE, UiTokens.STROKE, 0))
	dock.add_child(dock_panel)

	var dock_margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		dock_margin.add_theme_constant_override(side, 8)
	dock_panel.add_child(dock_margin)

	dock_box = VBoxContainer.new()
	dock_box.add_theme_constant_override("separation", 6)
	dock_margin.add_child(dock_box)

	# ---- Target Status card ----
	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", UiTokens.flat(UiTokens.SURFACE_1, UiTokens.RULE, UiTokens.STROKE, UiTokens.RADIUS_PLATE))
	dock_box.add_child(status_panel)
	var status_margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		status_margin.add_theme_constant_override(side, 8)
	status_panel.add_child(status_margin)
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 2)
	status_margin.add_child(status_box)
	var status_header := Label.new()
	status_header.text = "TARGET"
	status_header.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	status_header.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	status_box.add_child(status_header)
	status_title = Label.new()
	status_title.text = "NO TARGET SELECTED"
	status_title.add_theme_font_size_override("font_size", UiTokens.T_META)
	status_title.add_theme_color_override("font_color", UiTokens.CREAM)
	status_box.add_child(status_title)
	status_badge = Label.new()
	status_badge.text = "○ UNASSIGNED"
	status_badge.add_theme_font_size_override("font_size", UiTokens.T_META)
	status_badge.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	status_badge.clip_text = true
	status_badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_badge.custom_minimum_size.x = 80.0
	status_box.add_child(status_badge)
	status_detail = Label.new()
	status_detail.text = "-"
	status_detail.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	status_detail.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	status_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_detail.clip_text = true
	status_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_detail.custom_minimum_size.x = 0.0
	status_box.add_child(status_detail)
	protected_banner = Label.new()
	protected_banner.text = ""
	protected_banner.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	protected_banner.add_theme_color_override("font_color", UiTokens.ACCENT)
	protected_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	protected_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	protected_banner.clip_text = true
	protected_banner.visible = true
	protected_banner_host = Control.new()
	protected_banner_host.custom_minimum_size = Vector2(0, 28)
	protected_banner_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	protected_banner_host.visible = false
	protected_banner_host.add_child(protected_banner)
	status_box.add_child(protected_banner_host)
	_build_assignment_scope_controls(status_box)

	# ---- authoring actions (specs/06) ----
	target_action_row = HBoxContainer.new()
	target_action_row.add_theme_constant_override("separation", 4)
	status_box.add_child(target_action_row)
	action_save = _styled_button("SAVE", Callable(self, "_action_save_draft"))
	action_apply = _styled_button("APPLY", Callable(self, "_action_apply"))
	action_styling = _styled_button("STYLING ON", Callable(self, "_action_toggle_styling"))
	action_unique = _styled_button("UNIQUE", Callable(self, "_action_make_unique"))
	action_edit_shared = _styled_button("EDIT SHARED", Callable(self, "_action_edit_shared"))
	action_why = _styled_button("WHY?", Callable(self, "_action_why"))
	for button in [action_save, action_apply]:
		target_action_row.add_child(button)
	action_more_menu = MenuButton.new()
	action_more_menu.name = "TargetActionsMenu"
	action_more_menu.text = "MORE"
	action_more_menu.tooltip_text = "Secondary target actions: styling, explanation, history and assignment"
	FxLabUiTokensScript.apply_hit_target(action_more_menu)
	var more_popup := action_more_menu.get_popup()
	more_popup.add_item("STYLING", 1)
	more_popup.add_item("WHY THIS TARGET", 2)
	more_popup.add_separator()
	more_popup.add_item("UNDO", 3)
	more_popup.add_item("REDO", 4)
	more_popup.add_item("REVERT", 5)
	more_popup.add_separator()
	more_popup.add_item("UNASSIGN", 6)
	more_popup.add_item("MAKE UNIQUE", 7)
	more_popup.add_item("EDIT SHARED", 8)
	more_popup.id_pressed.connect(_on_target_actions_menu)
	target_action_row.add_child(action_more_menu)
	target_action_row2 = HBoxContainer.new()
	target_action_row2.add_theme_constant_override("separation", 4)
	protected_actions_host = Control.new()
	protected_actions_host.custom_minimum_size = Vector2.ZERO
	protected_actions_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	protected_actions_host.visible = false
	target_action_row2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	protected_actions_host.add_child(target_action_row2)
	# Keep protected-scope actions reachable without competing with the primary
	# Save/Apply/More row. This host stays hidden for normal editable targets.
	status_box.add_child(protected_actions_host)
	protected_actions_spacer = Control.new()
	protected_actions_spacer.custom_minimum_size = Vector2.ZERO
	target_action_row2.add_child(protected_actions_spacer)
	for button in [action_unique, action_edit_shared]:
		target_action_row2.add_child(button)
	target_action_row3 = HBoxContainer.new()
	target_action_row3.add_theme_constant_override("separation", 4)
	undo_button = _styled_button("↶ UNDO", func() -> void: _action_undo())
	redo_button = _styled_button("↷ REDO", func() -> void: _action_redo())
	var revert_button := _styled_button("Revert Changes", func() -> void: _action_revert())
	var action_unassign_button := _styled_button("UNASSIGN", func() -> void: _action_unassign())
	revert_button.visible = false
	action_unassign_button.visible = false
	action_unassign = action_unassign_button
	for button in [undo_button, redo_button, revert_button, action_unassign]:
		target_action_row3.add_child(button)
	# Undo/redo remain visible editor actions, while Styling/Revert/assignment
	# discovery is consolidated behind MORE. Keep the row mounted in the compact
	# target card rather than leaving its controls orphaned off-tree.
	status_box.add_child(target_action_row3)
	action_status = Label.new()
	action_status.text = ""
	action_status.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	action_status.add_theme_color_override("font_color", UiTokens.ACCENT)
	action_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_box.add_child(action_status)
	why_label = Label.new()
	why_label.text = ""
	why_label.visible = false
	why_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	why_label.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	why_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_box.add_child(why_label)
	why_actions = VBoxContainer.new()
	why_actions.add_theme_constant_override("separation", 2)
	status_box.add_child(why_actions)

	# ---- Layers ----
	layers_box = VBoxContainer.new()
	layers_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layers_box.size_flags_stretch_ratio = 0.42
	dock_box.add_child(layers_box)
	var layers_header := HBoxContainer.new()
	layers_header.add_theme_constant_override("separation", 4)
	layers_box.add_child(layers_header)
	var layers_title := Label.new()
	layers_title.text = "LAYERS"
	layers_title.clip_text = true
	layers_title.custom_minimum_size.x = 0.0
	layers_title.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	layers_title.add_theme_color_override("font_color", UiTokens.ACCENT)
	layers_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layers_header.add_child(layers_title)
	layers_cost_label = Label.new()
	layers_cost_label.text = ""
	layers_cost_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	layers_cost_label.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	layers_header.add_child(layers_cost_label)
	add_menu = MenuButton.new()
	add_menu.name = "AddMenu"
	add_menu.text = "+ ADD"
	add_menu.tooltip_text = "Add a layer or effect to the current draft"
	FxLabUiTokensScript.apply_hit_target(add_menu)
	add_menu.custom_minimum_size.x = 84
	var add_popup: PopupMenu = add_menu.get_popup()
	add_popup.add_item("LAYERS", 1)
	add_popup.set_item_disabled(0, true)
	for index in ADD_LAYER_TEMPLATES.size():
		add_popup.add_item(str(ADD_LAYER_TEMPLATES[index]), 100 + index)
	add_popup.add_separator()
	add_popup.add_item("EFFECTS", 2)
	add_popup.set_item_disabled(add_popup.item_count - 1, true)
	for index in ADD_EFFECT_TEMPLATES.size():
		add_popup.add_item(str(ADD_EFFECT_TEMPLATES[index]), 200 + index)
	add_popup.id_pressed.connect(_on_add_menu_pressed)
	layers_header.add_child(add_menu)
	# Kept as null compatibility aliases: there is intentionally one visible
	# categorized add action, never two competing buttons.
	add_layer_menu = null
	add_effect_menu = null
	layers_empty = _section_empty(layers_box, "No design yet.\nSelect a target — the layer stack opens here.")
	layers_rows = VBoxContainer.new()
	layers_rows.add_theme_constant_override("separation", 2)
	var layers_scroll := ScrollContainer.new()
	layers_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layers_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layers_box.add_child(layers_scroll)
	layers_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layers_scroll.add_child(layers_rows)

	# ---- vertical splitter ----------------------------------------------------
	layers_split_handle = _make_handle(Control.CURSOR_VSIZE)
	layers_split_handle.gui_input.connect(func(event: InputEvent) -> void: _handle_drag(event, "layers"))
	dock_box.add_child(layers_split_handle)

	# ---- Properties / Recipes / Production -----------------------------------
	# Properties is the primary authoring surface. Recipes and Production are
	# real secondary tabs so their inventories never consume inspector height.
	authoring_tabs = TabContainer.new()
	authoring_tabs.name = "AuthoringDockTabs"
	authoring_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	authoring_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	authoring_tabs.size_flags_stretch_ratio = 0.62
	dock_box.add_child(authoring_tabs)

	inspector_box = VBoxContainer.new()
	inspector_box.name = "PROPERTIES"
	inspector_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_box.add_theme_constant_override("separation", 4)
	authoring_tabs.add_child(inspector_box)
	_section_header(inspector_box, "PROPERTIES")
	inspector_empty = _section_empty(inspector_box, "Select a target to start designing FX.\nThen select a layer to edit its properties.")
	inspector_content = VBoxContainer.new()
	inspector_content.add_theme_constant_override("separation", 4)
	inspector_scroll = ScrollContainer.new()
	inspector_scroll.name = "PropertiesScroll"
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector_box.add_child(inspector_scroll)
	var inspector_inner := VBoxContainer.new()
	inspector_inner.name = "PropertiesContent"
	inspector_inner.add_theme_constant_override("separation", 4)
	inspector_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(inspector_inner)

	# Recipes are curated authoring templates, not a capability registry.
	recipes_tab = ScrollContainer.new()
	recipes_tab.name = "RECIPES"
	recipes_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipes_tab.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	authoring_tabs.add_child(recipes_tab)
	var recipes_inner := VBoxContainer.new()
	recipes_inner.name = "RecipeLibraryContent"
	recipes_inner.add_theme_constant_override("separation", 6)
	# Give the scroll child a real authoring width. Without an explicit width a
	# wrapped Label reports a one-pixel minimum, stacking every recipe character
	# vertically and pushing the second curated preset below the viewport.
	recipes_inner.custom_minimum_size.x = 340.0
	recipes_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipes_tab.add_child(recipes_inner)
	_section_header(recipes_inner, "RECIPES · CURATED STARTING POINTS")
	var recipe_intro := Label.new()
	recipe_intro.text = "Authoring templates with real defaults. Add one, then refine it in Properties."
	recipe_intro.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	recipe_intro.add_theme_color_override("font_color", FxLabUiTokensScript.TEXT_DIM)
	recipe_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recipes_inner.add_child(recipe_intro)
	recipe_filter = OptionButton.new()
	recipe_filter.name = "RecipeCategoryFilter"
	recipe_filter.tooltip_text = "Filter the Recipe Library by creative role."
	recipe_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_filter.add_item("ALL RECIPES")
	for group in ["CHARACTER", "MOTION / IMPACT", "GRAPHIC TRANSITION", "SIGNATURE", "BASIC PRESETS"]:
		recipe_filter.add_item(group)
	recipe_filter.item_selected.connect(_on_recipe_filter_selected)
	recipes_inner.add_child(recipe_filter)
	recipe_selector = OptionButton.new()
	recipe_selector.name = "RecipeSelector"
	recipe_selector.tooltip_text = "Choose a recipe to inspect before adding it to the draft."
	recipe_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_selector.item_selected.connect(_on_recipe_selected)
	recipes_inner.add_child(recipe_selector)
	recipe_rows = VBoxContainer.new()
	recipe_rows.name = "RecipeRows"
	recipe_rows.add_theme_constant_override("separation", 6)
	recipes_inner.add_child(recipe_rows)
	var last_library_group := ""
	for recipe in FxRecipesScript.list():
		var recipe_data: Dictionary = recipe
		var library_group := str(recipe_data.get("library_group", recipe_data.get("category", "RECIPES")))
		if library_group != last_library_group:
			var group_label := Label.new()
			group_label.name = "RecipeGroup_%s" % library_group.replace(" ", "_").replace("/", "_")
			group_label.text = library_group
			group_label.add_theme_font_size_override("font_size", UiTokens.T_META)
			group_label.add_theme_color_override("font_color", FxLabUiTokensScript.TEXT_MUTED)
			group_label.custom_minimum_size.y = 22.0
			recipe_rows.add_child(group_label)
			recipe_group_labels[library_group] = group_label
			last_library_group = library_group
		var recipe_id := str(recipe_data.get("stable_id", ""))
		recipe_names[recipe_id] = str(recipe_data.get("name", recipe_id))
		if not recipe_ids_by_group.has(library_group):
			recipe_ids_by_group[library_group] = []
		recipe_ids_by_group[library_group].append(recipe_id)
		var recipe_card := PanelContainer.new()
		recipe_card.name = "RecipeCard_%s" % recipe_id
		recipe_card.set_meta("recipe_library_group", library_group)
		recipe_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		recipe_card.custom_minimum_size.x = 0.0
		FxLabUiTokensScript.apply_tool_style(recipe_card)
		recipe_rows.add_child(recipe_card)
		var recipe_box := VBoxContainer.new()
		recipe_box.add_theme_constant_override("separation", 2)
		recipe_card.add_child(recipe_box)
		var recipe_head := HBoxContainer.new()
		recipe_head.name = "RecipeHeader"
		recipe_head.clip_contents = true
		recipe_head.custom_minimum_size.x = 0.0
		recipe_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		recipe_box.add_child(recipe_head)
		var recipe_label := Label.new()
		recipe_label.name = "RecipeName"
		recipe_label.text = str(recipe_data.get("name", recipe_id))
		recipe_label.tooltip_text = str(recipe_data.get("description", ""))
		recipe_label.clip_text = true
		recipe_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		recipe_label.custom_minimum_size.x = 0.0
		recipe_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		recipe_label.add_theme_font_size_override("font_size", UiTokens.T_META)
		recipe_label.add_theme_color_override("font_color", FxLabUiTokensScript.TEXT)
		recipe_head.add_child(recipe_label)
		var recipe_add := _styled_button("ADD", func() -> void: _action_add_recipe(recipe_id))
		recipe_add.name = "RecipeAdd"
		recipe_add.custom_minimum_size = Vector2(64, FxLabUiTokensScript.HIT_HEIGHT)
		recipe_add.tooltip_text = "Add %s to the current draft. Defaults are canonical and editable." % recipe_id
		recipe_add_buttons.append(recipe_add)
		recipe_cards[recipe_id] = recipe_card
		recipe_head.add_child(recipe_add)
		var intent_label := Label.new()
		intent_label.name = "RecipeIntent"
		intent_label.text = "Intent: " + str(recipe_data.get("intent", ""))
		intent_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		intent_label.add_theme_color_override("font_color", FxLabUiTokensScript.ACCENT)
		intent_label.clip_text = true
		intent_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		intent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		intent_label.custom_minimum_size.x = 0.0
		recipe_box.add_child(intent_label)
		var description := Label.new()
		description.name = "RecipeDescription"
		description.text = str(recipe_data.get("description", ""))
		description.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		description.add_theme_color_override("font_color", FxLabUiTokensScript.TEXT_DIM)
		# Keep the curated card scannable; the full intent remains available in
		# the tooltip and the compatibility line stays visible below it.
		description.clip_text = true
		description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		description.tooltip_text = str(recipe_data.get("description", ""))
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.custom_minimum_size.x = 0.0
		recipe_box.add_child(description)
		var compatibility: Dictionary = recipe_data.get("target_compatibility", {})
		var roles: Array = compatibility.get("target_roles", [])
		var planes: Array = compatibility.get("allowed_planes", [])
		var compatible := Label.new()
		compatible.name = "RecipeCompatibility"
		compatible.text = "Compatible: %s · planes %s" % [", ".join(roles), ", ".join(planes)]
		compatible.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		compatible.add_theme_color_override("font_color", FxLabUiTokensScript.TEXT_MUTED)
		compatible.tooltip_text = "Target roles: %s\nAllowed planes: %s" % [", ".join(roles), ", ".join(planes)]
		compatible.clip_text = true
		compatible.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		compatible.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		compatible.custom_minimum_size.x = 0.0
		recipe_box.add_child(compatible)
	_refresh_recipe_discovery()

	production_tab = ScrollContainer.new()
	production_tab.name = "PRODUCTION"
	production_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	production_tab.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	authoring_tabs.add_child(production_tab)
	var production_inner := VBoxContainer.new()
	production_inner.name = "ProductionLibraryContent"
	production_inner.add_theme_constant_override("separation", 6)
	production_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	production_tab.add_child(production_inner)
	_section_header(production_inner, "PRODUCTION LOOKS")
	var production_intro := Label.new()
	production_intro.text = "Saved looks used by assignments. Editing stays in the current target session."
	production_intro.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	production_intro.add_theme_color_override("font_color", FxLabUiTokensScript.TEXT_DIM)
	production_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	production_inner.add_child(production_intro)
	library_rows = VBoxContainer.new()
	library_rows.name = "ProductionRows"
	library_rows.add_theme_constant_override("separation", 4)
	production_inner.add_child(library_rows)

	inspector_empty.reparent(inspector_inner)
	inspector_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_inner.add_child(inspector_content)

func _build_assignment_scope_controls(parent: Node) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = "SCOPE"
	title.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	title.add_theme_color_override("font_color", UiTokens.ACCENT)
	title.visible = false
	box.add_child(title)
	var row := HBoxContainer.new()
	assignment_scope_option = OptionButton.new()
	var labels := ["Exact target", "Fighter + role + side", "Fighter + role", "Role + visual side", "Role", "Static element", "Advanced selector"]
	for label in labels:
		assignment_scope_option.add_item(label)
	assignment_scope_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assignment_scope_option.item_selected.connect(func(index: int) -> void:
		if session == null:
			return
		var modes: Array = FxSessionScript.ASSIGNMENT_SCOPE_MODES
		var chosen_mode := str(modes[index])
		var custom: Dictionary = {}
		if chosen_mode == "ADVANCED":
			for field in assignment_scope_fields.keys():
				var edit: LineEdit = assignment_scope_fields[field]
				if edit.text.strip_edges() != "":
					custom[str(field)] = edit.text.strip_edges()
		session.set_assignment_scope(chosen_mode, custom)
		_refresh_scope_ui()
		_sync_actions()
	)
	row.add_child(assignment_scope_option)
	assignment_scope_count = Label.new()
	assignment_scope_count.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	assignment_scope_count.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	row.add_child(assignment_scope_count)
	box.add_child(row)
	# The compact row carries both the selector and affected-target count;
	# assignment_scope_status remains a tooltip-only technical explanation.
	assignment_scope_count.size_flags_horizontal = Control.SIZE_SHRINK_END
	assignment_scope_count.custom_minimum_size.x = 0.0
	assignment_scope_count.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	assignment_scope_status = Label.new()
	assignment_scope_status.text = "Scope: current target"
	assignment_scope_status.add_theme_font_size_override("font_size", 12)
	assignment_scope_status.add_theme_color_override("font_color", FxLabUiTokensScript.TEXT_DIM)
	assignment_scope_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	assignment_scope_status.clip_text = true
	assignment_scope_status.visible = true
	assignment_scope_status.tooltip_text = "The visible scope is the exact assignment selector used by APPLY/UPDATE."
	assignment_scope_option.tooltip_text = "Scope selector — choose the assignment reach used by APPLY/UPDATE"
	box.add_child(assignment_scope_status)
	assignment_scope_advanced = VBoxContainer.new()
	assignment_scope_advanced.add_theme_constant_override("separation", 1)
	assignment_scope_advanced.visible = false
	for field in FxResolverScript.SELECTOR_FIELDS:
		var field_row := HBoxContainer.new()
		var field_label := Label.new()
		field_label.text = str(field)
		field_label.custom_minimum_size.x = 120
		field_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		field_row.add_child(field_label)
		var edit := LineEdit.new()
		edit.placeholder_text = "optional"
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		edit.text_changed.connect(func(_value: String) -> void: _update_advanced_scope_field(str(field)))
		field_row.add_child(edit)
		assignment_scope_fields[str(field)] = edit
		assignment_scope_advanced.add_child(field_row)
	box.add_child(assignment_scope_advanced)
	parent.add_child(box)

func _update_advanced_scope_field(_field: String) -> void:
	if session == null or str(session.assignment_scope_mode) != "ADVANCED":
		return
	var custom: Dictionary = {}
	for field in assignment_scope_fields.keys():
		var edit: LineEdit = assignment_scope_fields[field]
		if edit.text.strip_edges() != "":
			custom[str(field)] = edit.text.strip_edges()
	session.set_assignment_scope("ADVANCED", custom)
	_refresh_scope_ui()
	_sync_actions()

func _refresh_scope_ui() -> void:
	if assignment_scope_option == null or session == null:
		return
	if str(session.current_key) == "composition":
		assignment_scope_option.visible = false
		assignment_scope_count.visible = false
		assignment_scope_advanced.visible = false
		if assignment_scope_status != null:
			assignment_scope_status.visible = true
			assignment_scope_status.text = "Composition authority · Production revision %d" % int(session.base.get("revision", 0))
			assignment_scope_status.tooltip_text = "Scene FX composition is not an assignment scope."
		return
	assignment_scope_option.visible = true
	assignment_scope_count.visible = true
	var modes: Array = FxSessionScript.ASSIGNMENT_SCOPE_MODES
	var index := modes.find(str(session.assignment_scope_mode))
	assignment_scope_option.select(maxi(0, index))
	assignment_scope_advanced.visible = str(session.assignment_scope_mode) == "ADVANCED"
	var selector: Dictionary = session.assignment_selector()
	for field in assignment_scope_fields.keys():
		var edit: LineEdit = assignment_scope_fields[field]
		var expected := str(selector.get(str(field), ""))
		if edit.text != expected and str(session.assignment_scope_mode) != "ADVANCED":
			edit.text = expected
	var affected := 0
	if runtime != null and runtime.registry != null and not selector.is_empty():
		for key in runtime.registry.keys():
			if FxResolverScript.selector_matches(selector, runtime.registry.context_for_target(str(key))):
				affected += 1
	assignment_scope_count.text = "affects %d target%s" % [affected, "" if affected == 1 else "s"]
	if assignment_scope_status != null:
		var scope_name: String = str(session.assignment_scope_text())
		assignment_scope_status.text = "Scope: %s · %d target%s" % [scope_name, affected, "" if affected == 1 else "s"]
		assignment_scope_status.tooltip_text = "APPLY/UPDATE commits this exact scope: " + scope_name

func _section_header(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	label.add_theme_color_override("font_color", UiTokens.ACCENT)
	parent.add_child(label)

func _section_empty(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	label.add_theme_color_override("font_color", UiTokens.DISABLED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _build_timeline(parent: Node) -> void:
	timeline_resize_handle = _make_handle(Control.CURSOR_VSIZE)
	timeline_resize_handle.visible = false
	timeline_resize_handle.gui_input.connect(func(event: InputEvent) -> void: _handle_drag(event, "timeline"))
	parent.add_child(timeline_resize_handle)

	timeline_panel = PanelContainer.new()
	timeline_panel.custom_minimum_size.y = 38
	timeline_panel.add_theme_stylebox_override("panel", UiTokens.flat(UiTokens.BASE, UiTokens.RULE, UiTokens.STROKE, 0))
	parent.add_child(timeline_panel)

	var timeline_margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		timeline_margin.add_theme_constant_override(side, 6)
	timeline_panel.add_child(timeline_margin)

	var timeline_box := VBoxContainer.new()
	timeline_box.add_theme_constant_override("separation", 4)
	timeline_margin.add_child(timeline_box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	timeline_box.add_child(top)
	timeline_toggle_button = Button.new()
	timeline_toggle_button.text = "▴ TIMELINE"
	timeline_toggle_button.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	timeline_toggle_button.pressed.connect(_toggle_timeline_expanded)
	top.add_child(timeline_toggle_button)
	timeline_time_label = Label.new()
	timeline_time_label.text = "T 0.000"
	timeline_time_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	timeline_time_label.add_theme_color_override("font_color", UiTokens.CREAM)
	timeline_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(timeline_time_label)
	var hint := Label.new()
	hint.text = "scrub: click / drag the ruler"
	hint.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	hint.add_theme_color_override("font_color", UiTokens.DISABLED)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(hint)

	timeline_ruler = TimelineRuler.new(self)
	timeline_ruler.visible = false
	timeline_ruler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline_box.add_child(timeline_ruler)

func _make_handle(cursor: int) -> ColorRect:
	var handle := ColorRect.new()
	handle.color = UiTokens.RULE
	handle.mouse_default_cursor_shape = cursor
	handle.custom_minimum_size = Vector2(6, 6) if cursor == Control.CURSOR_HSIZE else Vector2(6, 6)
	if cursor == Control.CURSOR_HSIZE:
		handle.custom_minimum_size = Vector2(6, 0)
	else:
		handle.custom_minimum_size = Vector2(0, 6)
	return handle

# ================================================================ inner ruler

class TimelineRuler extends Control:
	var shell: Node
	func _init(shell_ref: Node) -> void:
		shell = shell_ref
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
	func _gui_input(event: InputEvent) -> void:
		shell._ruler_input(event, self)
	func _draw() -> void:
		shell._draw_timeline(self)

const RULER_PAD := 14.0

func _time_at_x(x: float, width: float) -> float:
	var usable := maxf(width - RULER_PAD * 2.0, 1.0)
	return clampf((x - RULER_PAD) / usable * TIMELINE_LEN, 0.0, TIMELINE_LEN)

func _x_at_time(t: float, width: float) -> float:
	var usable := maxf(width - RULER_PAD * 2.0, 1.0)
	return RULER_PAD + (clampf(t, 0.0, TIMELINE_LEN) / TIMELINE_LEN) * usable

func _ruler_input(event: InputEvent, ruler: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := event as InputEventMouseButton
		if mouse.pressed:
			_dragging = "ruler"
			_seek(ruler, mouse.position.x)
		else:
			if _dragging == "ruler":
				_dragging = ""
				ws.save_state()
		accept_event()
	elif event is InputEventMouseMotion and _dragging == "ruler":
		_seek(ruler, (event as InputEventMouseMotion).position.x)
		accept_event()

func _seek(ruler: Control, x: float) -> void:
	var t := _time_at_x(x, ruler.size.x)
	_seek_authoring(t)

func _seek_authoring(t: float) -> void:
	# Explicit authoring transport owns both the authoring playhead and the
	# presentation reconstruction. Ordinary look rebuilds never call this path.
	# Any direct user seek is a transport pause, including toolbar/frame steps;
	# ruler drags pause on press before their first seek.
	if runtime != null and runtime.screen != null and runtime.screen.has_method("lab_preview_pause"):
		runtime.screen.lab_preview_pause()
		_update_play_button()
	var authoring_t: float = clampf(t, 0.0, TIMELINE_LEN)
	_authoring_playhead = authoring_t
	runtime.seek(authoring_t)
	if renderer != null:
		renderer.set_time(authoring_t)
	_sync_time(authoring_t)

func _draw_timeline(ruler: Control) -> void:
	var w := ruler.size.x
	var h := ruler.size.y
	if w < 40.0 or h < 40.0:
		return
	ruler.draw_rect(Rect2(0, 0, w, h), UiTokens.SURFACE_1)
	ruler.draw_rect(Rect2(0, h - 26.0, w, 26.0), UiTokens.BASE)
	var font := ruler.get_theme_default_font()
	var font_size := UiTokens.T_HELP
	# time grid every 0.2s
	var steps := int(TIMELINE_LEN / 0.2)
	for i in range(steps + 1):
		var t := float(i) * 0.2
		var x := _x_at_time(t, w)
		ruler.draw_line(Vector2(x, h - 26.0), Vector2(x, h - 6.0), UiTokens.RULE_WARM, 1.0)
		if i % 2 == 0 and font != null:
			ruler.draw_string(font, Vector2(x + 2.0, h - 10.0), "%.1f" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTokens.CREAM_DIM)
	# event marks — labels are staggered across rows so they never overlap
	var marks: Dictionary = event_marks
	var mark_names: Array = marks.keys()
	mark_names.sort_custom(func(a, b): return float(marks[a]) < float(marks[b]))
	_timeline_label_rects = []
	var row_ends := [-10000.0, -10000.0, -10000.0]
	for name in mark_names:
		var t := float(marks[name])
		var x := _x_at_time(t, w)
		ruler.draw_line(Vector2(x, 20.0), Vector2(x, h - 26.0), UiTokens.ACCENT, 1.0)
		var est := 10.0 + str(name).length() * 7.5
		var row := 0
		for r in range(3):
			row = r
			if x >= row_ends[r] + 6.0:
				break
		row_ends[row] = x + est
		var label_y := 16.0 + float(row) * 14.0
		if font != null:
			ruler.draw_string(font, Vector2(x + 3.0, label_y), str(name), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTokens.ACCENT)
		_timeline_label_rects.append({"name": str(name), "x": x + 3.0, "y": label_y - 11.0, "w": est, "h": 12.0})
	# playhead
	var t_now: float = _authoring_playhead
	var x_now := _x_at_time(t_now, w)
	ruler.draw_line(Vector2(x_now, 6.0), Vector2(x_now, h - 6.0), UiTokens.CREAM, 2.0)

# ================================================================ layout / resizing

func _on_resized() -> void:
	if body == null:
		return
	# Study zoom is useful during review but is secondary to target discovery,
	# preview, and the authoring dock. Remove its minimum width at the 1280px
	# floor instead of allowing it to push the DCC shell outside the window.
	var available_width := float(get_window().size.x) if get_window() != null else size.x
	for zoom_button in study_buttons.values():
		if zoom_button is Control:
			(zoom_button as Control).visible = available_width >= 1400.0
	_apply_browser_mode()
	_apply_timeline()
	_toolbar_overflow()
	_apply_layers_split()
	_layout_modal_panel(delete_panel)
	_layout_modal_panel(review_panel)

func _on_target_actions_menu(id: int) -> void:
	# Keep the target card compact: Save/Apply stay visible, while secondary
	# mutation/review actions remain reachable through one explicit menu.
	match id:
		1:
			_action_toggle_styling()
		2:
			_action_why()
		3:
			_action_undo()
		4:
			_action_redo()
		5:
			_action_revert()
		6:
			_action_unassign()
		7:
			_action_make_unique()
		8:
			_action_edit_shared()

func _apply_state() -> void:
	var dock_hidden := _is_dock_hidden()
	dock_host.visible = not dock_hidden
	dock.visible = not dock_hidden
	# R3 §17 finding: dock_w is persisted on drag but was never re-applied on
	# boot, so the inspector always reopened at the build-time width.
	if ws != null and ws.data.has("dock_w"):
		var dock_limit := minf(900.0, maxf(320.0, size.x - 800.0))
		dock_host.custom_minimum_size.x = minf(maxf(clampf(float(ws.data.get("dock_w", 390.0)), 320.0, 900.0), 320.0), dock_limit)
	_apply_browser_mode()
	_apply_timeline()
	_apply_layers_split()
	_toolbar_overflow()
	_apply_focus_buttons()

func _apply_browser_mode() -> void:
	if browser_panel == null:
		return
	var auto_narrow := size.x < AUTO_RAIL_WIDTH
	var intent := _browser_intent()
	# AUTO is the only mode allowed to follow the width heuristic. A direct
	# user open is authoritative even below the narrow breakpoint; a direct
	# user close remains closed after widening.
	var collapsed := intent == WorkspaceStateScript.INTENT_USER_CLOSED or (intent == WorkspaceStateScript.INTENT_AUTO and auto_narrow)
	browser.visible = not collapsed
	browser_rail.visible = collapsed
	browser_panel.custom_minimum_size.x = 34.0 if collapsed else float(ws.data.get("browser_w", 280.0))

func _browser_intent() -> String:
	var intent := str(ws.data.get("browser_intent", ""))
	if intent == WorkspaceStateScript.INTENT_AUTO and bool(ws.data.get("browser_collapsed", false)):
		# Compatibility for old tests/workspace writers that still set the
		# legacy boolean directly.
		return WorkspaceStateScript.INTENT_USER_CLOSED
	if intent in [WorkspaceStateScript.INTENT_AUTO, WorkspaceStateScript.INTENT_USER_OPEN, WorkspaceStateScript.INTENT_USER_CLOSED]:
		return intent
	return WorkspaceStateScript.INTENT_USER_CLOSED if bool(ws.data.get("browser_collapsed", false)) else WorkspaceStateScript.INTENT_AUTO

func _timeline_effective_collapsed() -> bool:
	var intent := _timeline_intent()
	var auto_collapsed := size.y < AUTO_TIMELINE_COLLAPSE_HEIGHT
	return intent != WorkspaceStateScript.INTENT_USER_OPEN and (intent == WorkspaceStateScript.INTENT_USER_CLOSED or auto_collapsed or intent == WorkspaceStateScript.INTENT_AUTO)

func _timeline_intent() -> String:
	var intent := str(ws.data.get("timeline_intent", ""))
	if intent == WorkspaceStateScript.INTENT_AUTO and bool(ws.data.get("timeline_expanded", false)):
		# Compatibility for old tests/workspace writers that still set the
		# legacy expanded boolean directly.
		return WorkspaceStateScript.INTENT_USER_OPEN
	if intent in [WorkspaceStateScript.INTENT_AUTO, WorkspaceStateScript.INTENT_USER_OPEN, WorkspaceStateScript.INTENT_USER_CLOSED]:
		return intent
	return WorkspaceStateScript.INTENT_USER_OPEN if bool(ws.data.get("timeline_expanded", false)) else WorkspaceStateScript.INTENT_AUTO

func _apply_timeline() -> void:
	if timeline_panel == null:
		return
	var collapsed := _timeline_effective_collapsed()
	timeline_ruler.visible = not collapsed
	timeline_resize_handle.visible = not collapsed
	timeline_panel.custom_minimum_size.y = 38.0 if collapsed else float(ws.data.get("timeline_h", 200.0))
	timeline_toggle_button.text = "▴ TIMELINE" if collapsed else "▾ TIMELINE"

func _apply_layers_split() -> void:
	if layers_box == null:
		return
	var ratio := clampf(float(ws.data.get("layers_split", 0.38)), 0.24, 0.58)
	layers_box.size_flags_stretch_ratio = ratio
	if authoring_tabs != null:
		authoring_tabs.size_flags_stretch_ratio = 1.0 - ratio

func _toolbar_overflow() -> void:
	if toolbar == null:
		return
	# Keep brand context on a wide desktop; at the 1280 floor it yields to
	# transport and state controls.
	brand_label.visible = size.x >= 1440.0
	# Dynamic overflow: collapse least-critical buttons into the "⋯" menu
	# until the toolbar fits the real window width. Static width tiers are
	# whack-a-mole across DPIs and fonts; measuring is the only honest gate
	# (the 1280 minimum window once clipped 34px off the toolbar).
	var pool: Array = [
		[remount_button, "⟲ REMOUNT", _remount_current],
		[review_button, "⚠ REVIEW", _open_migration_review_queue],
		[preset_authoring, "LAYOUT: AUTHORING", func() -> void: _apply_workspace_preset("AUTHORING")],
		[preset_preview, "LAYOUT: FOCUS", func() -> void: _apply_workspace_preset("PREVIEW")],
	]
	var popup := overflow_button.get_popup()
	popup.clear()
	# Reset is rare maintenance and is always available only through overflow.
	popup.add_item("RESET WORKSPACE", 1)
	popup.add_separator()
	var hidden: Array = []
	for entry in pool:
		var btn: Button = entry[0]
		if btn == null:
			continue
		btn.visible = true
	for entry in pool:
		var btn: Button = entry[0]
		if btn == null:
			continue
		if toolbar.get_combined_minimum_size().x <= size.x:
			break
		btn.visible = false
		hidden.append(entry)
	for i in range(hidden.size()):
		popup.add_item(str((hidden[i] as Array)[1]), 100 + i)
	overflow_button.visible = true
	if not popup.id_pressed.is_connected(_on_toolbar_overflow_chosen):
		popup.id_pressed.connect(_on_toolbar_overflow_chosen)

func _on_toolbar_overflow_chosen(id: int) -> void:
	if id == 1:
		_reset_workspace()
		return
	# Rebuild the current hidden set (same priority order as overflow).
	var pool: Array = [
		[remount_button, "⟲ REMOUNT", _remount_current],
		[review_button, "⚠ REVIEW", _open_migration_review_queue],
		[preset_authoring, "LAYOUT: AUTHORING", func() -> void: _apply_workspace_preset("AUTHORING")],
		[preset_preview, "LAYOUT: FOCUS", func() -> void: _apply_workspace_preset("PREVIEW")],
	]
	var hidden: Array = []
	for entry in pool:
		var btn: Button = entry[0]
		if btn != null and not (btn as Button).visible:
			hidden.append(entry)
	var hidden_index := id - 100
	if hidden_index >= 0 and hidden_index < hidden.size():
		((hidden[hidden_index] as Array)[2] as Callable).call()

func _is_dock_hidden() -> bool:
	return bool(ws.data.get("dock_hidden", false))

func _handle_drag(event: InputEvent, kind: String) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_dragging = kind
			elif _dragging == kind:
				_dragging = ""
				ws.save_state()
		return
	if event is InputEventMouseMotion and _dragging == kind:
		var pos: Vector2 = (event as InputEventMouseMotion).global_position
		match kind:
			"browser":
				var new_w := clampf(pos.x - browser_panel.global_position.x, 220.0, 360.0)
				ws.data["browser_w"] = new_w
				_apply_browser_mode()
			"dock":
				var dock_right := dock.global_position.x + dock.size.x
				ws.data["dock_w"] = clampf(dock_right - pos.x, 320.0, 900.0)
				dock_host.custom_minimum_size.x = maxf(float(ws.data["dock_w"]), 390.0)
			"layers":
				var total := maxf(dock.size.y - 40.0, 1.0)
				var y_local := pos.y - dock.global_position.y
				ws.data["layers_split"] = clampf(y_local / total, 0.15, 0.85)
				_apply_layers_split()
			"timeline":
				var panel_bottom := timeline_panel.global_position.y + timeline_panel.size.y
				ws.data["timeline_h"] = clampf(panel_bottom - pos.y, 120.0, 240.0)
				_apply_timeline()

# ================================================================ toolbar actions

func _transport_to_start() -> void:
	_seek_authoring(0.0)

func _toggle_transport() -> void:
	var screen = runtime.screen
	if screen == null:
		return
	if screen.has_method("lab_preview_is_paused") and bool(screen.lab_preview_is_paused()):
		screen.lab_preview_resume()
	else:
		screen.lab_preview_pause()
	_update_play_button()

func _transport_step_back() -> void:
	_seek_authoring(_authoring_playhead - FRAME_STEP)

func _transport_step_forward() -> void:
	_seek_authoring(_authoring_playhead + FRAME_STEP)

func _transport_to_fx_peak() -> void:
	var t := float(event_marks.get("clash_impact", 0.615))
	_seek_authoring(t)

func _on_time_entered(value: float) -> void:
	if time_syncing:
		return
	# Numeric entry is explicit authoring transport: it is the only path that
	# intentionally reconstructs the presentation lifecycle as well.
	_seek_authoring(value)

func _sync_time(t: float) -> void:
	time_syncing = true
	time_spin.set_value_no_signal(t)
	time_syncing = false

func _update_play_button() -> void:
	var screen = runtime.screen
	if screen == null:
		return
	var paused := true
	if screen.has_method("lab_preview_is_paused"):
		paused = bool(screen.lab_preview_is_paused())
	play_button.text = "▶ PLAY" if paused else "⏸ PAUSE"

func _toggle_browser() -> void:
	var open_now := bool(browser.visible)
	ws.data["browser_intent"] = WorkspaceStateScript.INTENT_USER_CLOSED if open_now else WorkspaceStateScript.INTENT_USER_OPEN
	ws.data["browser_collapsed"] = open_now
	_apply_browser_mode()
	ws.save_state()

func _open_browser_from_empty() -> void:
	# The no-target state has one obvious route into discovery. Keep this a real
	# workspace toggle so the same action works when the browser is auto-collapsed
	# at the 1280px floor.
	if browser == null:
		return
	if not browser.visible:
		ws.data["browser_intent"] = WorkspaceStateScript.INTENT_USER_OPEN
		ws.data["browser_collapsed"] = false
		_apply_browser_mode()
	ws.save_state()

func _toggle_dock() -> void:
	ws.data["dock_hidden"] = not _is_dock_hidden()
	var hidden := _is_dock_hidden()
	dock_host.visible = not hidden
	dock.visible = not hidden
	ws.save_state()

func _toggle_timeline_expanded() -> void:
	var expanded_now := not _timeline_effective_collapsed()
	ws.data["timeline_intent"] = WorkspaceStateScript.INTENT_USER_CLOSED if expanded_now else WorkspaceStateScript.INTENT_USER_OPEN
	ws.data["timeline_expanded"] = not expanded_now
	_apply_timeline()
	ws.save_state()

func _reset_workspace() -> void:
	ws.reset()
	_apply_state()
	ws.save_state()

func _prepare_for_remount() -> bool:
	if session != null:
		var result: Dictionary = session.prepare_for_remount()
		if not bool(result.get("ok", false)):
			action_status.text = "✗ Remount refused — draft stash failed: " + str(result.get("errors", []))
			return false
		session.close_target()
	_stash_pending = false
	_ui_transactions.clear()
	_focus_originals.clear()
	selected_key = ""
	selected_layer_id = ""
	return true

func _remount_current() -> void:
	if not _prepare_for_remount():
		return
	runtime.mount()
	renderer = null
	_rendered_key = ""
	event_marks = _compute_event_marks()
	browser.rebuild()
	browser.refresh_context()
	_apply_preview_focus()
	_refresh_selection_ui()
	_authoring_playhead = 0.0
	_sync_time(0.0)

func _on_remount_requested(format: String, stage: String, left: String, right: String) -> void:
	if not _prepare_for_remount():
		return
	runtime.mount(format, stage, left, right)
	renderer = null
	_rendered_key = ""
	event_marks = _compute_event_marks()
	browser.rebuild()
	browser.refresh_context()
	_apply_preview_focus()
	_refresh_selection_ui()
	_authoring_playhead = 0.0
	_sync_time(0.0)

# ================================================================ preview

func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var key := _pick_texture_at((event as InputEventMouseButton).position)
		if key != "":
			_select_key(key, true)
			accept_event()

func _pick_texture_at(point: Vector2) -> String:
	var hits: Array = []
	var nodes: Dictionary = runtime.registry.slot_nodes
	for key in nodes.keys():
		var node = nodes[key]
		if not (node is TextureRect) or not node.visible:
			continue
		var inv: Transform2D = node.get_global_transform().affine_inverse()
		var local: Vector2 = inv * point
		if Rect2(Vector2.ZERO, node.size).has_point(local) and _texture_hit_alpha(node, local):
			# SP-03: proxy nodes are full-canvas surfaces; rank by logical
			# element bounds so tiny elements stay selectable.
			var rect: Rect2 = FxTargetsScript.logical_bounds(node)
			hits.append({"key": String(key), "area": rect.size.x * rect.size.y, "z": node.z_index})
	if hits.is_empty():
		return ""
	hits.sort_custom(func(a, b):
		if int(a["z"]) != int(b["z"]):
			return int(a["z"]) > int(b["z"])
		return float(a["area"]) < float(b["area"])
	)
	return String(hits[0]["key"])

func _texture_hit_alpha(node: TextureRect, local: Vector2) -> bool:
	if node.texture == null or node.size.x <= 0.0 or node.size.y <= 0.0:
		return false
	var uv := Vector2(local.x / node.size.x, local.y / node.size.y)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return false
	if node.flip_h:
		uv.x = 1.0 - uv.x
	var image := node.texture.get_image()
	if image == null or image.is_empty():
		return true
	var px := clampi(int(round(uv.x * float(image.get_width() - 1))), 0, image.get_width() - 1)
	var py := clampi(int(round(uv.y * float(image.get_height() - 1))), 0, image.get_height() - 1)
	return image.get_pixel(px, py).a > 0.03

func _update_selection_outline() -> void:
	if selection_outline == null or runtime == null:
		return
	var nodes: Dictionary = runtime.registry.slot_nodes
	if selected_key == "" or not nodes.has(selected_key):
		selection_outline.visible = false
		return
	var node = nodes[selected_key]
	if not (node is TextureRect) or disp == null:
		selection_outline.visible = false
		return
	# SP-03: outline the logical element, never a full-canvas proxy surface.
	var rect: Rect2 = FxTargetsScript.logical_bounds(node)
	selection_outline.position = disp.position + rect.position * disp.scale
	selection_outline.size = rect.size * disp.scale
	selection_outline.visible = true

func _set_preview_focus(mode: String) -> void:
	if mode not in ["NORMAL", "DIM OTHERS", "SOLO"]:
		mode = "NORMAL"
	ws.data["preview_focus"] = mode
	_apply_focus_buttons()
	_apply_preview_focus()
	ws.save_state()

func _apply_focus_buttons() -> void:
	var current := str(ws.data.get("preview_focus", "NORMAL"))
	var key_map := {"NORMAL": "NORMAL", "DIM OTHERS": "DIM OTHERS", "SOLO": "SOLO"}
	for label in focus_buttons.keys():
		var expected: String = "SOLO" if str(label) == "SOLO" else str(label)
		(focus_buttons[label] as Button).button_pressed = (current == expected)

func _apply_preview_focus() -> void:
	if runtime == null or runtime.screen == null:
		return
	var nodes: Dictionary = runtime.registry.slot_nodes
	var mode := str(ws.data.get("preview_focus", "NORMAL"))
	if selected_key == "":
		# A remount releases the old nodes. Preserve the user preference, but do
		# not apply DIM/SOLO to a targetless fresh substrate; reapply on selection.
		_focus_originals.clear()
		for key in nodes.keys():
			nodes[key].modulate = Color.WHITE
		return
	if mode == "NORMAL":
		for key in _focus_originals.keys():
			if nodes.has(key):
				nodes[key].modulate = _focus_originals[key]
		_focus_originals.clear()
		return
	for key in nodes.keys():
		if not _focus_originals.has(key):
			_focus_originals[key] = nodes[key].modulate
		var base: Color = _focus_originals[key]
		if key == selected_key:
			nodes[key].modulate = base
		elif mode == "DIM OTHERS":
			nodes[key].modulate = Color(base.r, base.g, base.b, base.a * 0.25)
		else:
			nodes[key].modulate = Color(base.r, base.g, base.b, 0.0)

# ================================================================ selection / status

func _on_target_selected(key: String) -> void:
	_select_key(key, false)

func _select_key(key: String, from_preview: bool) -> void:
	if key == "":
		return
	# Auto-stash before target switch (specs/10 §2): no modal, no data loss.
	# DR-07: a failed stash BLOCKS the switch — proceeding would strand dirty
	# work that no longer exists anywhere.
	if key != selected_key and session != null and session.dirty and str(session.current_key) != "":
		var stash_result: Dictionary = session.stash()
		if not bool(stash_result.get("ok", false)):
			action_status.text = "✗ Draft stash failed — staying on current target: " + str(stash_result.get("errors", []))
			return
	selected_key = key
	if not from_preview and browser != null:
		pass # browser already shows the selection
	if from_preview and browser != null:
		_select_browser_row(key)
	_open_session_for(key)
	_refresh_selection_ui()
	_apply_preview_focus()

func _select_browser_row(key: String) -> void:
	if browser == null or _selecting:
		return
	_selecting = true
	for item in browser.row_keys.keys():
		if str(browser.row_keys[item]) == key:
			item.select(0)
			break
	_selecting = false

func _refresh_selection_ui() -> void:
	var registry = runtime.registry
	if selected_key == "" or (selected_key != "composition" and not registry.slot_nodes.has(selected_key)):
		breadcrumb_label.text = "NO TARGET SELECTED"
		if open_browser_button != null:
			open_browser_button.visible = true
		status_title.text = "NO TARGET SELECTED"
		status_badge.text = "○ UNASSIGNED"
		status_badge.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
		status_detail.text = "-"
		if assignment_scope_status != null:
			assignment_scope_status.text = "Scope: select a target"
			assignment_scope_status.tooltip_text = "Select a target before choosing an assignment scope."
		if protected_banner != null:
			protected_banner.visible = false
			protected_banner_host.visible = false
			protected_banner.text = ""
		selection_outline.visible = false
		if why_label != null:
			why_label.visible = false
		why_open = false
		_refresh_scope_ui()
		_sync_actions()
		_rebuild_layers_panel()
		_rebuild_inspector()
		return
	var ctx: Dictionary = registry.context_for_target(selected_key)
	breadcrumb_label.text = _breadcrumb(ctx)
	if open_browser_button != null:
		open_browser_button.visible = false
	status_title.text = _breadcrumb(ctx)
	if _session_ready():
		status_badge.text = session.badge_text()
		status_detail.text = session.status_detail() + "\n" + _spatial_readout(selected_key)
		if protected_banner != null:
			var is_protected := str(session.mode) == "SHARED_PROTECTED"
			protected_banner.visible = is_protected
			protected_banner_host.visible = is_protected
			protected_banner.text = "PROTECTED SHARED LOOK — EDIT SHARED or MAKE UNIQUE to change values." if is_protected else ""
	else:
		status_badge.text = _status_badge_for(selected_key)
		status_detail.text = _spatial_readout(selected_key)
		if protected_banner != null:
			protected_banner.visible = false
			protected_banner_host.visible = false
			protected_banner.text = ""
	status_badge.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	if why_label != null:
		why_label.visible = why_open
		if why_open and _session_ready():
			why_label.text = "WHY?\n" + "\n".join(session.why())
	_refresh_why_actions()
	_sync_actions()
	_rebuild_layers_panel()
	_rebuild_inspector()
	_refresh_library()
	_update_selection_outline()

func _breadcrumb(ctx: Dictionary) -> String:
	var fighter := str(ctx.get("fighter_id", ""))
	var role := str(ctx.get("element_role", ""))
	if fighter != "":
		var parts: Array = [fighter.replace("_", " ").to_upper(), role.to_upper()]
		var slot := str(ctx.get("presentation_slot", ""))
		var side := str(ctx.get("visual_side", ""))
		var tail := slot if slot != "" else side
		if tail != "":
			parts.append(tail.to_upper())
		return " › ".join(parts)
	if role == "vs_mark":
		return "VS › VS MARK"
	if role == "stage":
		return "COMPOSITION › STAGE"
	if role == "side_field":
		return "COMPOSITION › SIDE FIELD %s" % str(ctx.get("visual_side", "")).to_upper()
	if role == "name_plate":
		return "COMPOSITION › NAME PLATE %s" % str(ctx.get("visual_side", "")).to_upper()
	if role == "accent_line":
		return "COMPOSITION › ACCENT LINE %s" % str(ctx.get("visual_side", "")).to_upper()
	return str(ctx.get("element_id", "")).to_upper()

func _status_badge_for(key: String) -> String:
	# Composition is synthetic and has no assignment resolver status.
	if key == "composition":
		if session != null and str(session.current_key) == key:
			return session.badge_text()
		var loaded: Dictionary = production.load_composition() if production != null else {"ok": false}
		if bool(loaded.get("ok", false)) and not (loaded.get("doc", {}) as Dictionary).is_empty():
			return "◈ COMPOSITION / SCENE FX · rev%d" % int((loaded.get("doc", {}) as Dictionary).get("revision", 0))
		return "◈ COMPOSITION / SCENE FX"
	# Resolved through the shared resolver (specs/06 §10); briefly cached so
	# browser rebuilds stay cheap. The open target uses the live session state.
	if session != null and str(session.current_key) == key:
		return session.badge_text()
	if runtime == null or runtime.registry == null or not runtime.registry.slot_nodes.has(key):
		return "○ UNASSIGNED"
	var now := Time.get_ticks_msec() / 1000.0
	if now - _badge_cache_at > 1.0:
		_badge_cache.clear()
		_badge_cache_at = now
	if _badge_cache.has(key):
		return str(_badge_cache[key])
	var ctx: Dictionary = runtime.registry.context_for_target(key)
	var label := "○ UNASSIGNED"
	var draft_signature: String = runtime.registry.signature_for_key(key)
	if drafts != null and drafts.has_target(draft_signature):
		_badge_cache[key] = "◐ DRAFT"
		return "◐ DRAFT"
	var assignments: Dictionary = production.load_assignments()
	if bool(assignments.get("ok", false)):
		var doc: Dictionary = assignments["doc"]
		var res: Dictionary = FxResolverScript.resolve(doc, ctx)
		var status := str(res.get("status", ""))
		match status:
			"BYPASSED":
				label = "⦸ STYLING OFF"
			"ASSIGNED", "AMBIGUOUS":
				var look_id := str(res.get("look_id", ""))
				if not FileAccess.file_exists(production.look_path(look_id)):
					label = "⚠ BROKEN"
				elif status == "AMBIGUOUS":
					label = "⚠ AMBIGUOUS"
				elif str((production.load_look(look_id).get("doc", {}) as Dictionary).get("status", "")) == "MIGRATION_REVIEW_REQUIRED":
					label = "⚠ MIGRATION REVIEW"
				else:
					label = "● ASSIGNED"
			_:
				# No enabled match — is there a disabled one that would match?
				for raw in doc.get("bindings", []):
					if raw is Dictionary and not bool((raw as Dictionary).get("enabled", true)):
						if FxResolverScript.selector_matches((raw as Dictionary).get("selector", {}), ctx):
							label = "○ DISABLED"
							break
	_badge_cache[key] = label
	return label

func _spatial_readout(key: String) -> String:
	var node = runtime.registry.slot_nodes.get(key)
	if not (node is TextureRect) or node.texture == null:
		return "-"
	var tex: Texture2D = node.texture
	var ps: Vector2 = FxTargetsScript.raw_presentation_size(node, tex)
	var sx := ps.x / maxf(float(tex.get_width()), 1.0)
	var sy := ps.y / maxf(float(tex.get_height()), 1.0)
	return "source %d×%d → presentation %.1f×%.1f · scale %.3f×/%.3f×" % [tex.get_width(), tex.get_height(), ps.x, ps.y, sx, sy]

# ================================================================ authoring session

func _session_ready() -> bool:
	return session != null and runtime != null and runtime.registry != null and (selected_key == "composition" or runtime.registry.slot_nodes.has(selected_key)) and str(session.current_key) == selected_key and str(session.mode) != "NONE"

func _open_session_for(key: String) -> void:
	var registry = runtime.registry
	if registry == null or (key != "composition" and not registry.slot_nodes.has(key)):
		return
	var ctx: Dictionary = registry.context_for_target(key)
	# The session's scope builder keys off the canonical element_role id
	# ("echo"/"primary"/"name"/"stage"/...), not the display role label.
	var role := str(ctx.get("element_role", ""))
	if not role in ["primary", "echo", "name"] and str(ctx.get("element_id", "")) == "":
		# Static composition authoring targets: persist a stable element_id.
		ctx["element_id"] = key.replace("_fx_proxy", "")
	var sig: String = registry.signature_for_key(key)
	session.open_target(key, ctx, sig, role)
	_ui_transactions.clear()
	_refresh_scope_ui()
	var layers: Array = session.look.get("layers", [])
	selected_layer_id = str((layers[0] as Dictionary).get("layer_id", "")) if not layers.is_empty() else ""
	action_status.text = ""
	_stash_pending = false
	_render_current_look()

func _render_current_look() -> void:
	# Full composition preview (Round-2 Finding 2): the selected target shows the
	# current Draft while EVERY other target keeps its effective Production look;
	# in PRODUCTION mode all targets show persisted styles only.
	if runtime == null or runtime.screen == null:
		return
	if renderer == null:
		renderer = FxLayerRendererScript.new(runtime.screen, runtime.registry)
	# UI-03 quality: the preview renderer owns the presentation's event marks
	# so named anchors fire at deterministic flow times (manual = triggered).
	renderer.set_event_marks(_compute_event_marks())
	var built := _build_composition_plan()
	var render_options: Dictionary = {}
	if not (built.get("composition", {}) as Dictionary).is_empty():
		render_options["composition"] = built["composition"]
	var result: Dictionary = renderer.apply_composition(built["plan"], render_options)
	# UI-04: fresh quads inherit COMPOSITE — re-assert the selected view so a
	# rebuild/switch/remount can neither leak nor silently drop debug state.
	renderer.set_debug_view(debug_view)
	_update_debug_badge()
	# Keep presentation lifecycle time/state owned by the mounted screen. The
	# renderer has its own authoring/evaluation clock, advanced only by explicit
	# transport actions; rebuilding a Look must never seek the presentation.
	renderer.set_time(_authoring_playhead)
	_plan_status = built["detail"]
	_rendered_key = str(session.current_key) if session != null else ""
	if bool(result.get("ok", false)):
		if status_detail != null:
			status_detail.text = "preview %s · styled=%d" % [preview_mode, int(result.get("targets", 0))]
	elif action_status != null:
		action_status.text = "render: " + str(result.get("errors", []))

func _toggle_preview_mode() -> void:
	preview_mode = "PRODUCTION" if preview_mode == "WORKING" else "WORKING"
	if preview_toggle != null:
		preview_toggle.text = "STATE: " + preview_mode
	_render_current_look()

func _production_look_for(key: String) -> Dictionary:
	# Effective Production style for one target through the shared resolver.
	if production == null or runtime == null or runtime.registry == null:
		return {}
	if key == "composition":
		var composition_loaded: Dictionary = production.load_composition()
		if bool(composition_loaded.get("ok", false)) and not (composition_loaded.get("doc", {}) as Dictionary).is_empty():
			return {"doc": composition_loaded["doc"], "look_id": "", "status": "COMPOSITION", "revision": int((composition_loaded["doc"] as Dictionary).get("revision", 0))}
		return {}
	var loaded_asg: Dictionary = production.load_assignments()
	if not bool(loaded_asg.get("ok", false)):
		return {}
	var ctx: Dictionary = runtime.registry.context_for_target(key)
	var res: Dictionary = FxResolverScript.resolve(loaded_asg["doc"], ctx)
	var status := str(res.get("status", ""))
	if status != "ASSIGNED" and status != "AMBIGUOUS":
		return {}
	var loaded: Dictionary = production.load_look(str(res.get("look_id", "")))
	if not bool(loaded.get("ok", false)):
		return {}
	return {"doc": loaded["doc"], "look_id": str(res.get("look_id", "")), "status": status}

func _build_composition_plan() -> Dictionary:
	var plan: Array = []
	var detail: Dictionary = {}
	if runtime == null or runtime.registry == null:
		return {"plan": plan, "detail": detail}
	var selected := str(session.current_key) if session != null else ""
	for key in runtime.registry.keys():
		var key_str := str(key)
		if preview_mode == "WORKING" and session != null and key_str == selected and not session.look.is_empty():
			plan.append({"key": key_str, "look": session.look})
			detail[key_str] = "DRAFT"
			continue
		var prod_look := _production_look_for(key_str)
		if prod_look.is_empty():
			detail[key_str] = "UNSTYLED"
			continue
		plan.append({"key": key_str, "look": prod_look["doc"]})
		detail[key_str] = "PRODUCTION " + str(prod_look["look_id"])
	var composition_doc: Dictionary = {}
	if preview_mode == "WORKING" and session != null and selected == "composition" and not session.composition.is_empty():
		# Composition Session Authority is already the canonical multi-instance
		# document. Never rebuild Preview from the legacy last recipe_id projection;
		# that would drop earlier authored instances and recreate the old split-brain
		# (Inspector/Session versus Preview) boundary.
		composition_doc = session.composition.duplicate(true)
	if composition_doc.is_empty() and production != null and production.has_method("load_composition"):
		var active_composition: Dictionary = production.load_composition()
		if bool(active_composition.get("ok", false)):
			composition_doc = active_composition.get("doc", {})
	if not composition_doc.is_empty():
		detail["composition"] = "DRAFT" if preview_mode == "WORKING" and selected == "composition" else "PRODUCTION"
		return {"plan": plan, "detail": detail, "composition": composition_doc}
	if runtime.registry.has_method("composition_context"):
		var composition_look: Dictionary = session.look if preview_mode == "WORKING" and session != null and selected == "composition" and not session.look.is_empty() else _production_look_for("composition").get("doc", {})
		if not composition_look.is_empty():
			plan.append({"key": "composition", "scope": "COMPOSITION", "look": composition_look})
			detail["composition"] = "DRAFT" if preview_mode == "WORKING" and selected == "composition" else "PRODUCTION"
	return {"plan": plan, "detail": detail, "composition": {}}

func _schedule_stash() -> void:
	_stash_at = Time.get_ticks_msec() / 1000.0 + 0.5
	_stash_pending = true

func _edit_layer(_layer_id: String, mutator: Callable, rebuild := true, live := false, transaction_key := "") -> void:
	if not _session_ready():
		return
	if not session.is_editable():
		action_status.text = "✗ Protected shared Look — EDIT SHARED or MAKE UNIQUE first"
		return
	var current_layer: Dictionary = FxLookScript.find_layer(session.look, _layer_id)
	if bool(current_layer.get("locked", false)):
		action_status.text = "✗ Layer locked — unlock it before editing"
		return
	var implicit_key := ""
	if not rebuild and not live:
		implicit_key = "layer:%s:control" % _layer_id
	if str(transaction_key) == "" and implicit_key != "":
		transaction_key = implicit_key
		live = true
	if live and str(transaction_key) != "":
		_begin_ui_transaction(str(transaction_key))
	if not live:
		session.snapshot()
	var result: Dictionary = session.edit(mutator)
	if bool(result.get("ok", false)) and bool(result.get("changed", true)):
		_schedule_stash()
		_render_current_look()
		_refresh_inspector_cost()
		_refresh_layers_cost_surfaces()
		if status_badge != null:
			status_badge.text = session.badge_text()
		var warnings: Array = result.get("warnings", [])
		if not warnings.is_empty():
			action_status.text = "⚠ " + str(warnings)
	elif bool(result.get("ok", false)):
		action_status.text = "• No canonical change"
	else:
		action_status.text = "✗ " + str(result.get("errors", []))
	if rebuild:
		_rebuild_layers_panel()
		_rebuild_inspector()
		_refresh_library()

func _begin_ui_transaction(key: String) -> void:
	if not _session_ready():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not _ui_transactions.has(key):
		session.snapshot()
	_ui_transactions[key] = now

func _end_ui_transaction(key: String) -> void:
	_ui_transactions.erase(key)

func _refresh_inspector_cost() -> void:
	if inspector_cost_badge == null or not _session_ready():
		return
	var layer := FxLookScript.find_layer(session.look, selected_layer_id)
	if layer.is_empty():
		inspector_cost_badge.text = ""
		return
	var cost: Dictionary = FxCostScript.layer_cost(layer)
	inspector_cost_badge.text = "LIVE COST %.1f · %s" % [float(cost.get("cost", 0.0)), ", ".join(cost.get("factors", []))]

func _refresh_layers_cost_surfaces() -> void:
	if not _session_ready() or session == null:
		if layers_cost_label != null:
			layers_cost_label.text = ""
		return
	var total: Dictionary = FxCostScript.look_cost(session.look)
	if layers_cost_label != null:
		layers_cost_label.text = "cost %.1f · %s" % [float(total.get("total", 0.0)), str(total.get("level", ""))]
	if layers_rows != null:
		_refresh_cost_nodes(layers_rows)

func _refresh_cost_nodes(node: Node) -> void:
	if node.has_meta("cost_layer_id"):
		var layer_id := str(node.get_meta("cost_layer_id"))
		var layer := FxLookScript.find_layer(session.look, layer_id)
		if not layer.is_empty():
			var layer_cost: Dictionary = FxCostScript.layer_cost(layer)
			(node as Label).text = "COST"
			(node as Label).tooltip_text = "Estimated render cost: %.1f\n%s" % [float(layer_cost.get("cost", 0.0)), "\n".join(layer_cost.get("factors", []))]
	for child in node.get_children():
		_refresh_cost_nodes(child)

func _wire_spin_transaction(spin: SpinBox, key: String) -> void:
	if spin == null:
		return
	spin.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if (event as InputEventMouseButton).pressed:
				_begin_ui_transaction(key)
			else:
				_end_ui_transaction(key)
	)
	spin.focus_entered.connect(func() -> void: _begin_ui_transaction(key))
	spin.focus_exited.connect(func() -> void: _end_ui_transaction(key))

func _wire_slider_transaction(row: Control, key: String, protected: bool) -> void:
	if protected or row == null or row.get_child_count() == 0:
		return
	var slider: HSlider = row.get_child(row.get_child_count() - 1) as HSlider
	if slider == null:
		return
	slider.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if (event as InputEventMouseButton).pressed:
				_begin_ui_transaction(key)
			else:
				_end_ui_transaction(key)
	)
	slider.focus_entered.connect(func() -> void: _begin_ui_transaction(key))
	slider.focus_exited.connect(func() -> void: _end_ui_transaction(key))

func _action_add_layer(template: String) -> void:
	if not _session_ready():
		return
	if not session.is_editable():
		action_status.text = "✗ Protected shared Look — EDIT SHARED or MAKE UNIQUE first"
		return
	session.snapshot()
	var new_layer: Dictionary = FxTemplatesScript.template_layer(template)
	var result: Dictionary = session.edit(func(doc): doc["layers"].append(new_layer))
	if bool(result.get("ok", false)):
		selected_layer_id = str(new_layer.get("layer_id", ""))
		action_status.text = "✓ Added " + template
		_schedule_stash()
		_render_current_look()
		_rebuild_layers_panel()
		_rebuild_inspector()
	else:
		action_status.text = "✗ " + str(result.get("errors", []))

func _on_add_menu_pressed(id: int) -> void:
	# The visible + ADD menu is categorized, but every leaf reaches the same
	# canonical session mutation used by the legacy layer/effect actions.
	if id >= 100 and id < 100 + ADD_LAYER_TEMPLATES.size():
		_action_add_layer(str(ADD_LAYER_TEMPLATES[id - 100]))
		return
	if id >= 200 and id < 200 + ADD_EFFECT_TEMPLATES.size():
		_action_add_layer(str(ADD_EFFECT_TEMPLATES[id - 200]))

func _recipe_instance_key(recipe_id: String) -> String:
	# Repeated clicks remain collision-free without introducing randomness. The
	# ordinal is derived from the current target's existing recipe layer ids,
	# while the registry derives every actual id from this complete key.
	var prefix := "recipe-%s-" % recipe_id.to_lower()
	var matching_layers := 0
	if _session_ready():
		for raw_layer in session.look.get("layers", []):
			if str((raw_layer as Dictionary).get("layer_id", "")).begins_with(prefix):
				matching_layers += 1
	var layer_count := maxi(1, (FxRecipesScript.get_recipe(recipe_id).get("layers", []) as Array).size())
	var ordinal := int(matching_layers / layer_count)

	return "%s:%s:%d" % [selected_key, recipe_id, ordinal]

func _refresh_recipe_discovery() -> void:
	if recipe_filter == null or recipe_selector == null:
		return
	_on_recipe_filter_selected(recipe_filter.selected)

func _on_recipe_filter_selected(index: int) -> void:
	if recipe_filter == null or recipe_selector == null:
		return
	var selected_group := recipe_filter.get_item_text(index)
	recipe_selector.clear()
	var candidate_ids: Array = []
	if selected_group == "ALL RECIPES":
		for raw_group in recipe_ids_by_group.keys():
			candidate_ids.append_array(recipe_ids_by_group[raw_group])
	else:
		candidate_ids = (recipe_ids_by_group.get(selected_group, []) as Array).duplicate()
	for raw_id in candidate_ids:
		var recipe_id := str(raw_id)
		recipe_selector.add_item(str(recipe_names.get(recipe_id, recipe_id)))
		recipe_selector.set_item_metadata(recipe_selector.item_count - 1, recipe_id)
	if not candidate_ids.is_empty():
		recipe_selector.select(0)
		_on_recipe_selected(0)
	else:
		for card in recipe_cards.values():
			(card as Control).visible = false
		for group_label in recipe_group_labels.values():
			(group_label as Control).visible = false

func _on_recipe_selected(index: int) -> void:
	if recipe_selector == null or index < 0 or index >= recipe_selector.item_count:
		return
	var selected_id := str(recipe_selector.get_item_metadata(index))
	for raw_id in recipe_cards.keys():
		(recipe_cards[raw_id] as Control).visible = str(raw_id) == selected_id
	for raw_group in recipe_group_labels.keys():
		var show_group := false
		for group_id in recipe_ids_by_group.get(raw_group, []):
			if str(group_id) == selected_id:
				show_group = true
				break
		(recipe_group_labels[raw_group] as Control).visible = show_group
	if recipes_tab != null:
		recipes_tab.scroll_vertical = 0

func _visible_recipe_add_buttons() -> Array:
	var visible: Array = []
	for raw_button in recipe_add_buttons:
		var button: Control = raw_button
		if button.is_visible_in_tree():
			visible.append(button)
	return visible

func _action_add_recipe(recipe_id: String) -> void:
	if not _session_ready():
		return
	if not session.is_editable():
		action_status.text = "✗ Protected shared Look — EDIT SHARED or MAKE UNIQUE first"
		return
	# Re-read the current registry context at the real UI mutation boundary.
	# Filtering is only discoverability; this guard is authoritative and runs
	# before the session snapshot or any canonical document mutation.
	var current_context: Dictionary = runtime.registry.context_for_target(selected_key)
	if str(current_context.get("target_key", "")) != selected_key:
		action_status.text = "✗ Recipe add refused — current target context is unavailable"
		return
	var compatibility: Dictionary = FxRecipesScript.target_compatibility(recipe_id, current_context)
	if not bool(compatibility.get("ok", false)):
		action_status.text = "✗ Recipe incompatible with current target: " + str(compatibility.get("errors", []))
		return
	var result: Dictionary = session.add_recipe_instance(recipe_id, current_context)
	if bool(result.get("ok", false)):
		var selected_ids: Array = result.get("pass_ids", []) if selected_key == "composition" else result.get("layer_ids", [])
		if not selected_ids.is_empty():
			selected_layer_id = str(selected_ids[0])
		action_status.text = "✓ Added Recipe · " + str(FxRecipesScript.get_recipe(recipe_id).get("name", recipe_id))
		_schedule_stash()
		_render_current_look()
		_rebuild_layers_panel()
		_rebuild_inspector()
	else:
		action_status.text = "✗ " + str(result.get("errors", []))

func _action_undo() -> void:
	if not _session_ready():
		return
	if session.undo():
		_schedule_stash()
		_render_current_look()
		_refresh_selection_ui()
		action_status.text = "↶ Undo"

func _action_redo() -> void:
	if not _session_ready():
		return
	if session.redo():
		_schedule_stash()
		_render_current_look()
		_refresh_selection_ui()
		action_status.text = "↷ Redo"

func _action_revert() -> void:
	if not _session_ready():
		return
	var result: Dictionary = session.revert_draft()
	var target := str(result.get("reverted_to", ""))
	action_status.text = "✓ Reverted to " + (target if target != "" else "neutral design")
	_render_current_look()
	_refresh_selection_ui()

func _action_unassign() -> void:
	if not _session_ready():
		return
	var result: Dictionary = session.unassign_target()
	if bool(result.get("ok", false)):
		# RS-05: surface what is actually effective — never claim bare unassigned.
		action_status.text = "✓ " + str(result.get("message", "Unassigned this target (Look stays in the Library)"))
		browser.rebuild()
	else:
		action_status.text = "✗ " + str(result.get("errors", []))
	_refresh_selection_ui()

func _apply_workspace_preset(name: String) -> void:
	ws.apply_preset(name)
	_apply_state()
	ws.save_state()
	action_status.text = "Workspace preset: " + name

func _set_study(zoom: String) -> void:
	study_mode = "OFF" if study_mode == zoom else zoom
	for key in study_buttons.keys():
		(study_buttons[key] as Button).button_pressed = (study_mode == str(key))

func _refresh_library() -> void:
	if library_rows == null:
		return
	for child in library_rows.get_children():
		library_rows.remove_child(child)
		child.queue_free()
	if session == null:
		return
	var current_look := str(session.base.get("look_id", "")) if session != null and not (session.base as Dictionary).is_empty() else ""
	var library: Array = session.look_library()
	if library.is_empty():
		var empty := Label.new()
		empty.text = "Library is empty — apply a design to create a Production Look."
		empty.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		empty.add_theme_color_override("font_color", UiTokens.DISABLED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		library_rows.add_child(empty)
		return
	for entry in library:
		var row := HBoxContainer.new()
		row.name = "ProductionLookRow_%s" % str(entry.get("look_id", ""))
		row.add_theme_constant_override("separation", 4)
		row.custom_minimum_size.y = 38
		var look_id := str(entry.get("look_id", ""))
		var look_name := look_id
		var loaded: Dictionary = production.load_look(look_id)
		if bool(loaded.get("ok", false)):
			look_name = str((loaded.get("doc", {}) as Dictionary).get("name", look_id))
		var identity := VBoxContainer.new()
		identity.name = "LookIdentity"
		identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		identity.size_flags_stretch_ratio = 1.0
		identity.custom_minimum_size.x = 0
		identity.add_theme_constant_override("separation", 0)
		var primary := Label.new()
		primary.name = "LookName"
		primary.text = look_name
		primary.tooltip_text = "Production Look: %s" % look_name
		primary.set_meta("look_id", look_id)
		primary.set_meta("look_name", look_name)
		primary.clip_text = true
		primary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		primary.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		primary.add_theme_color_override("font_color", UiTokens.ACCENT if str(entry["look_id"]) == current_look else UiTokens.CREAM_DIM)
		primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary.custom_minimum_size.x = 0
		identity.add_child(primary)
		var metadata := Label.new()
		metadata.name = "LookMetadata"
		metadata.text = "ID: %s · rev%d · used by %d target%s" % [look_id, int(entry["revision"]), int(entry["usage"]), "" if int(entry["usage"]) == 1 else "s"]
		metadata.tooltip_text = "Stable ID: %s\nRevision: %d\nUsage: %d target(s)" % [look_id, int(entry["revision"]), int(entry["usage"])]
		metadata.clip_text = true
		metadata.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		metadata.add_theme_font_size_override("font_size", UiTokens.T_META)
		metadata.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
		metadata.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		metadata.custom_minimum_size.x = 0
		identity.add_child(metadata)
		row.add_child(identity)
		if not bool(entry["valid"]):
			var broken := Label.new()
			broken.text = "⚠ BROKEN"
			broken.add_theme_font_size_override("font_size", UiTokens.T_HELP)
			broken.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
			row.add_child(broken)
		elif production != null and production.list_migration_review_look_ids().has(str(entry["look_id"])):
			var review := Label.new()
			review.text = "⚠ REVIEW"
			review.add_theme_font_size_override("font_size", UiTokens.T_HELP)
			review.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
			row.add_child(review)
		var delete_button := Button.new()
		delete_button.name = "DeleteLookButton"
		delete_button.text = "🗑"
		delete_button.flat = true
		delete_button.tooltip_text = "Delete Look (blocked while used)"
		delete_button.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		delete_button.pressed.connect(func() -> void: _action_delete_look(str(entry["look_id"])))
		row.add_child(delete_button)
		library_rows.add_child(row)

func _action_delete_look(look_id: String) -> void:
	# Round-2 Finding 14: used Looks get an explicit three-way choice, never a
	# silent delete and never broken references.
	if production == null:
		return
	var use: Dictionary = production.usage(look_id)
	if int(use.get("total_count", use.get("count", 0))) == 0:
		_apply_retire(look_id, "unassign", "")
		return
	_open_delete_chooser(look_id, use)

func _open_delete_chooser(look_id: String, use: Dictionary) -> void:
	_close_delete_chooser()
	delete_look_id = look_id
	delete_overlay = _new_modal_overlay()
	delete_panel = PanelContainer.new()
	_setup_modal_panel(delete_panel, Vector2(560, 320))
	add_child(delete_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	delete_panel.add_child(box)
	var title := Label.new()
	# RS-06: enabled vs disabled references are distinguished.
	var disabled_refs := int(use.get("total_count", use.get("count", 0))) - int(use.get("count", 0))
	var scope_note := " (%d disabled reference(s) included)" % disabled_refs if disabled_refs > 0 else ""
	title.text = "This Look is used by %d assignment(s)%s." % [int(use.get("total_count", use.get("count", 0))), scope_note]
	title.add_theme_font_size_override("font_size", UiTokens.T_META)
	box.add_child(title)
	for target in use.get("targets", []):
		var line := Label.new()
		line.text = "• " + str((target as Dictionary).get("selector_key", ""))
		line.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		line.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
		box.add_child(line)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 96)
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	var replace_label := Label.new()
	replace_label.text = "Replace With…"
	replace_label.add_theme_font_size_override("font_size", UiTokens.T_META)
	list.add_child(replace_label)
	var candidates: Array = production.list_look_ids()
	var offered := 0
	for candidate in candidates:
		var cand := str(candidate)
		if cand == look_id:
			continue
		offered += 1
		var cand_button := _styled_button(cand, func() -> void: _apply_retire(look_id, "replace", cand))
		list.add_child(cand_button)
	if offered == 0:
		var none := Label.new()
		none.text = "(no other Look available)"
		none.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		none.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
		list.add_child(none)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	var unassign := _styled_button("Unassign affected targets", func() -> void: _apply_retire(look_id, "unassign", ""))
	actions.add_child(unassign)
	var cancel := _styled_button("Cancel", _close_delete_chooser)
	modal_cancel_button = cancel
	actions.add_child(cancel)
	cancel.grab_focus.call_deferred()

func _new_modal_overlay() -> Control:
	var overlay := ColorRect.new()
	overlay.name = "ModalBackdrop"
	overlay.color = Color(0.02, 0.03, 0.05, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	add_child(overlay)
	return overlay

func _setup_modal_panel(panel: PanelContainer, desired: Vector2) -> void:
	panel.z_index = 101
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = desired
	FxLabUiTokensScript.apply_tool_style(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	_layout_modal_panel(panel)

func _layout_modal_panel(panel: PanelContainer) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var desired := panel.custom_minimum_size
	var width := minf(desired.x, maxf(320.0, size.x - 40.0))
	var height := minf(desired.y, maxf(200.0, size.y - 40.0))
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	panel.size = Vector2(width, height)

func _close_delete_chooser() -> void:
	delete_look_id = ""
	modal_cancel_button = null
	if delete_overlay != null and is_instance_valid(delete_overlay):
		delete_overlay.queue_free()
	delete_overlay = null
	if delete_panel != null and is_instance_valid(delete_panel):
		delete_panel.queue_free()
	delete_panel = null

func _apply_retire(look_id: String, mode: String, replacement: String) -> void:
	var result: Dictionary = production.retire_look(look_id, mode, replacement)
	if bool(result.get("ok", false)):
		action_status.text = "✓ Deleted Look %s · %s %d target(s)" % [look_id, mode, int(result.get("rebound", 0)) + int(result.get("unassigned", 0))]
		_close_delete_chooser()
		# DR-08: a retired Look must not linger as live session authority.
		if session != null and str((session.base as Dictionary).get("look_id", "")) == look_id and str(session.current_key) != "":
			session.open_target(str(session.current_key), session.context, str(session.signature), str(session.role))
		_refresh_library()
		_refresh_selection_ui()
		if session != null and str(session.current_key) != "":
			_render_current_look()
			if status_badge != null:
				status_badge.text = _status_badge_for(str(session.current_key))
	else:
		action_status.text = "✗ " + str(result.get("errors", []))
	browser.rebuild()

# ------------------------------------------------------- migration review (UI)
# The queue, notes, repair and approval all run through the production review
# authority; the shell only selects, displays and refreshes.

func migration_review_ids() -> Array:
	if production == null:
		return []
	return production.list_migration_review_look_ids()

func migration_review_select(look_id: String) -> Dictionary:
	if production == null:
		return {"ok": false, "errors": ["no production"]}
	var review: Dictionary = production.load_migration_review(look_id)
	if bool(review.get("ok", false)):
		_open_migration_review_panel(look_id, review.get("notes", []))
		review_look_id = look_id
	return review

func migration_review_approve(ack: String) -> Dictionary:
	if production == null or review_look_id == "":
		return {"ok": false, "errors": ["no review selected"]}
	var result: Dictionary = production.approve_migration_review(review_look_id, ack)
	if bool(result.get("ok", false)):
		action_status.text = "✓ Approved Look %s · PRODUCTION rev%d" % [review_look_id, int(result.get("look_revision", 0))]
		_close_migration_review_panel()
		_refresh_library()
		_refresh_selection_ui()
		if session != null and str(session.current_key) != "":
			_render_current_look()
			if status_badge != null:
				status_badge.text = _status_badge_for(str(session.current_key))
	else:
		action_status.text = "✗ " + str(result.get("errors", []))
	return result

func migration_review_repair_current() -> Dictionary:
	# Persist the currently edited session look back as a REVIEW repair.
	if production == null or review_look_id == "":
		return {"ok": false, "errors": ["no review selected"]}
	if not _session_ready():
		return {"ok": false, "errors": ["no editable session"]}
	var repair := {"layers": {}}
	for layer in (session.look as Dictionary).get("layers", []):
		if layer is Dictionary:
			(repair["layers"] as Dictionary)[str((layer as Dictionary).get("layer_id", ""))] = {
				"fx": ((layer as Dictionary).get("fx", {}) as Dictionary).duplicate(true),
				"mask": ((layer as Dictionary).get("mask", {}) as Dictionary).duplicate(true),
			}
	var result: Dictionary = production.save_migration_repair(review_look_id, repair)
	if bool(result.get("ok", false)):
		action_status.text = "✓ Repair saved for %s · still in review" % review_look_id
		_refresh_library()
	else:
		action_status.text = "✗ " + str(result.get("errors", []))
	return result

func _open_migration_review_queue() -> void:
	var queue := migration_review_ids()
	if queue.is_empty():
		action_status.text = "✓ No looks pending migration review"
		return
	migration_review_select(str(queue[0]))

func _open_migration_review_panel(look_id: String, notes: Array) -> void:
	_close_migration_review_panel()
	review_overlay = _new_modal_overlay()
	review_panel = PanelContainer.new()
	_setup_modal_panel(review_panel, Vector2(560, 360))
	add_child(review_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	review_panel.add_child(box)
	var title := Label.new()
	title.text = "Migration review: %s (%d note(s))" % [look_id, notes.size()]
	title.add_theme_font_size_override("font_size", UiTokens.T_META)
	box.add_child(title)
	for note in notes:
		var line := Label.new()
		line.text = "• " + str(note)
		line.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		line.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(line)
	var ack_label := Label.new()
	ack_label.text = "Acknowledgement (required to approve):"
	ack_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	box.add_child(ack_label)
	review_ack_field = LineEdit.new()
	review_ack_field.placeholder_text = "what did you verify?"
	box.add_child(review_ack_field)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	actions.add_child(_styled_button("Save repair from editor", func() -> void: migration_review_repair_current()))
	actions.add_child(_styled_button("Approve", func() -> void: migration_review_approve(review_ack_field.text if review_ack_field != null else "")))
	var cancel := _styled_button("Cancel", _close_migration_review_panel)
	modal_cancel_button = cancel
	actions.add_child(cancel)
	review_ack_field.grab_focus.call_deferred()

func _close_migration_review_panel() -> void:
	review_look_id = ""
	review_ack_field = null
	modal_cancel_button = null
	if review_overlay != null and is_instance_valid(review_overlay):
		review_overlay.queue_free()
	review_overlay = null
	if review_panel != null and is_instance_valid(review_panel):
		review_panel.queue_free()
		review_panel = null

func _modal_active() -> bool:
	return (delete_panel != null and is_instance_valid(delete_panel)) or (review_panel != null and is_instance_valid(review_panel))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		if delete_panel != null:
			_close_delete_chooser()
			get_viewport().set_input_as_handled()
		elif review_panel != null:
			_close_migration_review_panel()
			get_viewport().set_input_as_handled()

func _action_save_draft() -> void:
	if not _session_ready():
		return
	var result: Dictionary = session.save_draft()
	action_status.text = "✓ Draft saved" if bool(result.get("ok", false)) else "✗ " + str(result.get("errors", []))
	status_badge.text = session.badge_text()

func _action_apply(look_id_override := "") -> void:
	if not _session_ready():
		return
	if str(session.mode) == "SHARED_PROTECTED":
		action_status.text = "✗ Shared Look is protected — EDIT SHARED or MAKE UNIQUE first"
		return
	var result: Dictionary = session.apply(look_id_override)
	if bool(result.get("ok", false)):
		action_status.text = "✓ Applied current draft · revision %d" % int(result["revision"])
		browser.rebuild()
	else:
		action_status.text = "✗ " + str(result.get("errors", []))
	_render_current_look()
	_refresh_selection_ui()

func _action_toggle_styling() -> void:
	if not _session_ready():
		return
	var result: Dictionary = session.set_styling(not session.styling_enabled)
	if bool(result.get("ok", false)):
		action_status.text = "✓ Styling " + ("ON" if session.styling_enabled else "OFF")
		for warning in result.get("warnings", []):
			action_status.text += " · ⚠ " + str(warning)
		_render_current_look()
		browser.rebuild()
	else:
		action_status.text = "✗ " + str(result.get("errors", []))
	_refresh_selection_ui()

func _action_make_unique() -> void:
	if not _session_ready():
		return
	var result: Dictionary = session.make_unique()
	if bool(result.get("ok", false)):
		action_status.text = "✓ Created a unique editable Production Look"
		browser.rebuild()
	else:
		action_status.text = "✗ " + str(result.get("errors", []))
	_render_current_look()
	_refresh_selection_ui()

func _action_edit_shared() -> void:
	if not _session_ready():
		return
	var result: Dictionary = session.edit_shared()
	action_status.text = "✓ Editing shared draft — affects every target using this Look" if bool(result.get("ok", false)) else "✗ " + str(result.get("errors", []))
	_refresh_selection_ui()

func _action_why() -> void:
	why_open = not why_open
	why_label.visible = why_open
	if why_open and _session_ready():
		why_label.text = "WHY?\n" + "\n".join(session.why())

func _refresh_why_actions() -> void:
	if why_actions == null:
		return
	for child in why_actions.get_children():
		why_actions.remove_child(child)
		child.queue_free()
	if not why_open or not _session_ready():
		return
	if session.mode == "SHARED_PROTECTED" or not session.is_editable():
		return
	# RS-02: the WINNER gets a disable action too (letting fallback win is the
	# meaningful choice), and every matching DISABLED binding gets an enable
	# recovery on the same surface.
	for entry in session.resolution.get("chain", []):
		if not bool((entry as Dictionary).get("winner", false)):
			continue
		var disable_winner := Button.new()
		disable_winner.text = "DISABLE " + str((entry as Dictionary).get("binding_id", ""))
		disable_winner.flat = true
		disable_winner.tooltip_text = "Advanced: disable the winning binding so fallback rules win"
		disable_winner.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		disable_winner.pressed.connect(func() -> void: _action_disable_binding(str((entry as Dictionary)["binding_id"])))
		why_actions.add_child(disable_winner)
	for entry in session.resolution.get("chain", []):
		if bool((entry as Dictionary).get("winner", false)):
			continue
		var disable := Button.new()
		disable.text = "DISABLE " + str((entry as Dictionary).get("binding_id", ""))
		disable.flat = true
		disable.tooltip_text = "Advanced: disable this binding so lower-priority rules win"
		disable.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		disable.pressed.connect(func() -> void: _action_disable_binding(str((entry as Dictionary)["binding_id"])))
		why_actions.add_child(disable)
	var assignments: Dictionary = session.production.load_assignments()
	if bool(assignments.get("ok", false)):
		for raw in (assignments["doc"] as Dictionary).get("bindings", []):
			if raw is Dictionary and not bool((raw as Dictionary).get("enabled", true)):
				if FxResolverScript.selector_matches((raw as Dictionary).get("selector", {}), session.context):
					var enable := Button.new()
					enable.text = "ENABLE " + str((raw as Dictionary).get("binding_id", "")) + " (" + str((raw as Dictionary).get("look_id", "")) + ")"
					enable.flat = true
					enable.tooltip_text = "Re-enable this binding"
					enable.add_theme_font_size_override("font_size", UiTokens.T_HELP)
					enable.pressed.connect(func() -> void: _action_enable_binding(str((raw as Dictionary)["binding_id"])))
					why_actions.add_child(enable)

func _action_disable_binding(binding_id: String) -> void:
	var result: Dictionary = session.disable_binding(binding_id)
	if bool(result.get("ok", false)):
		action_status.text = "✓ Disabled " + binding_id + " — fallback active"
		browser.rebuild()
	else:
		action_status.text = "✗ " + str(result.get("errors", []))
	_refresh_selection_ui()

func _action_enable_binding(binding_id: String) -> void:
	var result: Dictionary = session.enable_binding(binding_id)
	if bool(result.get("ok", false)):
		action_status.text = "✓ Enabled " + binding_id
		browser.rebuild()
	else:
		action_status.text = "✗ " + str(result.get("errors", []))
	_refresh_selection_ui()

func _sync_actions() -> void:
	if action_apply == null:
		return
	var has: bool = _session_ready() and selected_key != ""
	var is_composition: bool = has and selected_key == "composition"
	var scope_valid: bool = has and not is_composition and not session.assignment_selector().is_empty()
	# No-target is a real authoring state, not a disabled target editor. Hide
	# target-mutating rows entirely so the workspace cannot imply an action
	# exists before a target is selected.
	if target_action_row != null:
		target_action_row.visible = has
	if target_action_row3 != null:
		target_action_row3.visible = has
	action_save.disabled = not has
	action_apply.disabled = not has or str(session.mode) == "SHARED_PROTECTED"
	var scope: String = session.assignment_scope_text() if scope_valid else ""
	if action_styling != null:
		action_styling.visible = not is_composition
		action_styling.disabled = not scope_valid
	if action_unassign != null:
		action_unassign.visible = not is_composition
		action_unassign.text = "UNASSIGN"
		action_unassign.disabled = not scope_valid
		action_unassign.tooltip_text = "Unassign scope: " + scope if scope_valid else "Choose a non-empty assignment scope"
		action_why.disabled = not has
		action_styling.text = ("STYLING " + ("ON" if session.styling_enabled else "OFF")) if has and not is_composition else "STYLING"
	action_styling.tooltip_text = "Styling scope: " + scope if scope_valid else ""
	if action_more_menu != null:
		action_more_menu.visible = has and not is_composition
	action_apply.text = "UPDATE" if (has and not is_composition and str(session.base.get("kind", "")) == "production") else "APPLY"
	if has and is_composition:
		action_apply.tooltip_text = "Commits the Scene FX composition revision"
	elif has:
		action_apply.tooltip_text = "Commits to assignment scope: " + session.assignment_scope_text()
	else:
		action_apply.tooltip_text = "Select a target and choose a non-empty assignment scope"
	action_unique.visible = scope_valid and str(session.mode) == "SHARED_PROTECTED"
	action_edit_shared.visible = scope_valid and str(session.mode) == "SHARED_PROTECTED"
	if target_action_row2 != null:
		target_action_row2.visible = has and str(session.mode) == "SHARED_PROTECTED"
	if protected_actions_host != null:
		protected_actions_host.visible = has and str(session.mode) == "SHARED_PROTECTED"
	if protected_actions_spacer != null:
		protected_actions_spacer.visible = false
	if add_menu != null:
		add_menu.visible = has
	for recipe_button in recipe_add_buttons:
		(recipe_button as Button).disabled = not has or not session.is_editable()
	if recipe_rows != null:
		recipe_rows.visible = true
	if undo_button != null:
		var editable: bool = has and session.is_editable()
		undo_button.disabled = not editable
		redo_button.disabled = not editable

func _rebuild_layers_panel() -> void:
	if layers_rows == null:
		return
	for child in layers_rows.get_children():
		layers_rows.remove_child(child)
		child.queue_free()
	var has_target := _session_ready()
	var layers: Array = session.look.get("layers", []) if has_target and session != null else []
	if layers_empty != null:
		layers_empty.visible = not has_target or layers.is_empty()
	if layers_cost_label != null:
		if layers.is_empty() or session == null:
			layers_cost_label.text = ""
		else:
			var cost: Dictionary = FxCostScript.look_cost(session.look)
			layers_cost_label.text = "cost %.1f · %s" % [float(cost["total"]), str(cost["level"])]
	var order := ["COMPOSITION_FOREGROUND", "TARGET_OVERLAY", "TARGET_SOURCE", "TARGET_UNDERLAY", "COMPOSITION_BACKGROUND"]
	var labels := {
		"COMPOSITION_FOREGROUND": "FOREGROUND",
		"TARGET_OVERLAY": "IN FRONT OF TARGET",
		"TARGET_SOURCE": "WITH TARGET",
		"TARGET_UNDERLAY": "BEHIND TARGET",
		"COMPOSITION_BACKGROUND": "BACKGROUND",
	}
	# LG-01: one order model — the panel shows global document order within
	# each plane group (no reversal), so visual order IS the authoritative
	# draw/dependency order the renderer resolves inputs against.
	for plane in order:
		var plane_rows: Array = []
		for raw in layers:
			if raw is Dictionary and str((raw as Dictionary).get("plane", "")) == plane:
				plane_rows.append(raw)
		if plane_rows.is_empty():
			continue
		var section = FxPlaneSectionScript.new()
		section.shell = self
		section.plane = plane
		section.add_theme_stylebox_override("panel", UiTokens.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
		var section_box := VBoxContainer.new()
		section_box.add_theme_constant_override("separation", 2)
		section.add_child(section_box)
		var head := Label.new()
		head.text = str(labels[plane])
		head.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		head.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
		section_box.add_child(head)
		for index in range(plane_rows.size()):
			section_box.add_child(_layer_row(plane_rows[index]))
		layers_rows.add_child(section)
	_apply_lab_ui_contract()

func _layer_row(layer: Dictionary) -> Control:
	var row = FxLayerRowScript.new()
	row.shell = self
	var layer_id := str(layer.get("layer_id", ""))
	row.layer_id = layer_id
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, FxLabUiTokensScript.HIT_HEIGHT)
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var eye := Button.new()
	eye.name = "VisibilityButton"
	eye.custom_minimum_size = Vector2(FxLabUiTokensScript.HIT_WIDTH, FxLabUiTokensScript.HIT_HEIGHT)
	FxLabUiTokensScript.apply_hit_target(eye)
	eye.text = "◉" if bool(layer.get("enabled", true)) else "○"
	eye.tooltip_text = "Visible — click to hide this layer" if bool(layer.get("enabled", true)) else "Hidden — click to show this layer"
	eye.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	eye.pressed.connect(func() -> void: _edit_layer(layer_id, func(doc):
		var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
		l["enabled"] = not bool(l.get("enabled", true))
	))
	row.add_child(eye)
	var lock := Button.new()
	lock.name = "LockButton"
	lock.custom_minimum_size.x = FxLabUiTokensScript.HIT_WIDTH
	FxLabUiTokensScript.apply_hit_target(lock)
	lock.text = "🔒" if bool(layer.get("locked", false)) else "🔓"
	lock.tooltip_text = "Locked — click to allow editing" if bool(layer.get("locked", false)) else "Unlocked — click to lock editing"
	lock.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	lock.pressed.connect(func() -> void:
		if not _session_ready() or not session.is_editable():
			return
		session.snapshot()
		var lock_result: Dictionary = session.edit(func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			l["locked"] = not bool(l.get("locked", false))
		)
		if bool(lock_result.get("ok", false)):
			_schedule_stash()
			_rebuild_layers_panel()
			_rebuild_inspector()
		else:
			action_status.text = "✗ " + str(lock_result.get("errors", []))
	)
	row.add_child(lock)
	var pick := Button.new()
	pick.name = "LayerName"
	FxLabUiTokensScript.apply_hit_target(pick)
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.text = str(layer.get("name", "Layer"))
	pick.tooltip_text = "Select layer: %s" % str(layer.get("name", "Layer"))
	pick.clip_text = true
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	pick.add_theme_color_override("font_color", UiTokens.ACCENT if layer_id == selected_layer_id else UiTokens.CREAM)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.custom_minimum_size.x = 0
	pick.clip_text = true
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick.pressed.connect(func() -> void:
		selected_layer_id = layer_id
		_rebuild_layers_panel()
		_rebuild_inspector()
	)
	row.add_child(pick)
	var drag := Button.new()
	drag.name = "DragButton"
	drag.text = "⠿"
	drag.tooltip_text = "Drag handle — move this layer onto another row or plane section"
	drag.custom_minimum_size.x = FxLabUiTokensScript.HIT_WIDTH
	drag.flat = true
	FxLabUiTokensScript.apply_hit_target(drag)
	drag.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	row.add_child(drag)
	var layer_cost: Dictionary = FxCostScript.layer_cost(layer)
	pick.tooltip_text = "Select layer: %s\nRender cost: %.1f\n%s\nOpacity: %d%%" % [str(layer.get("name", "Layer")), float(layer_cost["cost"]), "\n".join(layer_cost["factors"]), roundi(float(layer.get("opacity", 1.0)) * 100.0)]
	var menu := MenuButton.new()
	menu.name = "ContextMenu"
	FxLabUiTokensScript.apply_hit_target(menu)
	menu.text = "⋯"
	menu.flat = true
	menu.custom_minimum_size.x = FxLabUiTokensScript.HIT_WIDTH
	menu.tooltip_text = "Layer context actions — duplicate, move, reset, delete, copy or paste"
	menu.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	menu.get_popup().add_item("Duplicate Layer", 1)
	menu.get_popup().add_item("Move Up", 2)
	menu.get_popup().add_item("Move Down", 3)
	menu.get_popup().add_item("Reset Layer", 4)
	menu.get_popup().add_item("Delete Layer", 5)
	menu.get_popup().add_item("Copy Layer", 6)
	menu.get_popup().add_item("Paste Layer", 7)
	menu.get_popup().id_pressed.connect(func(id: int) -> void: _layer_menu_action(id, layer_id))
	row.add_child(menu)
	return row

func layer_display_name(layer_id: String) -> String:
	var layer: Dictionary = FxLookScript.find_layer(session.look, layer_id) if session != null else {}
	return str(layer.get("name", layer_id))

func _layer_menu_action(id: int, layer_id: String) -> void:
	if not _session_ready():
		return
	var layer: Dictionary = FxLookScript.find_layer(session.look, layer_id)
	if layer.is_empty():
		return
	var is_source := str(layer.get("type", "")) == "SOURCE"
	match id:
		1: # Duplicate
			_edit_layer(layer_id, func(doc):
				var copy: Dictionary = FxLookScript.duplicate_layer_in(doc, layer_id)
				if not copy.is_empty() and str(copy.get("type", "")) == "SOURCE":
					copy["type"] = "SOURCE_COPY"
					copy["name"] = "Source Copy"
			)
		2: _move_layer(layer_id, -1)
		3: _move_layer(layer_id, 1)
		4:
			_edit_layer(layer_id, func(doc):
				FxLookScript.reset_layer_in(doc, layer_id)
			)
		5:
			if is_source:
				action_status.text = "✗ The mandatory SOURCE layer cannot be deleted"
			else:
				_edit_layer(layer_id, func(doc):
					var layers: Array = doc["layers"]
					for i in range(layers.size()):
						if str((layers[i] as Dictionary).get("layer_id", "")) == layer_id:
							layers.remove_at(i)
							break
					if selected_layer_id == layer_id:
						selected_layer_id = str((doc["layers"][0] as Dictionary).get("layer_id", ""))
				)
		6: _action_copy_layer(layer_id)
		7: _action_paste_layer()

func _action_copy_layer(layer_id: String) -> void:
	if session == null:
		return
	var layer: Dictionary = FxLookScript.find_layer(session.look, layer_id)
	if layer.is_empty():
		action_status.text = "✗ select a layer to copy"
		return
	layer_clipboard = layer.duplicate(true)
	action_status.text = "✓ Copied Layer " + str(layer.get("name", layer_id))

func _action_paste_layer() -> void:
	if not _session_ready():
		return
	if layer_clipboard.is_empty():
		action_status.text = "✗ clipboard is empty"
		return
	if not session.is_editable():
		action_status.text = "✗ Protected shared Look — EDIT SHARED or MAKE UNIQUE first"
		return
	session.snapshot()
	var uploaded: Dictionary = layer_clipboard.duplicate(true)
	uploaded["layer_id"] = FxLookScript.next_layer_id(str(uploaded.get("type", "fx")).to_lower())
	if str(uploaded.get("type", "")) == "SOURCE":
		uploaded["type"] = "SOURCE_COPY"
	uploaded["name"] = str(uploaded.get("name", "Layer")) + " (pasted)"
	var result: Dictionary = session.edit(func(doc):
		doc["layers"].append(uploaded)
	)
	if bool(result.get("ok", false)):
		selected_layer_id = str(uploaded.get("layer_id", ""))
		action_status.text = "✓ Pasted Layer " + str(uploaded.get("name", ""))
		_schedule_stash()
		_render_current_look()
		_rebuild_layers_panel()
		_rebuild_inspector()
	else:
		action_status.text = "✗ " + str(result.get("errors", []))

func _move_layer(layer_id: String, direction: int) -> void:
	# LG-02/LG-04: visual order is document order, so Up/Down moves in raw
	# index space directly; SOURCE is pinned and refuses to move.
	_edit_layer(layer_id, func(doc):
		FxLookScript.move_layer_in(doc, layer_id, direction)
	)

func _drop_layer_on_layer(drag_id: String, target_id: String) -> void:
	# LG-05: dropping onto a layer reorders dependency position ONLY — plane
	# changes happen exclusively via plane-section drops, never implicitly.
	_edit_layer(drag_id, func(doc):
		FxLookScript.reorder_layer_in(doc, drag_id, target_id)
	)

func _drop_layer_on_plane(drag_id: String, plane: String) -> void:
	_edit_layer(drag_id, func(doc):
		FxLookScript.set_layer_plane(doc, drag_id, plane)
	)

func _rebuild_inspector() -> void:
	if inspector_content == null:
		return
	var focus_field := _focused_canonical_field()
	if inspector_scroll != null:
		_inspector_scroll_value = inspector_scroll.scroll_vertical
	for child in inspector_content.get_children():
		if child is TabContainer:
			var old_tabs: TabContainer = child as TabContainer
			if old_tabs.current_tab >= 0 and old_tabs.current_tab < old_tabs.get_tab_count():
				_inspector_tab_name = old_tabs.get_tab_title(old_tabs.current_tab)
	for child in inspector_content.get_children():
		inspector_content.remove_child(child)
		child.queue_free()
	var layer: Dictionary = FxLookScript.find_layer(session.look, selected_layer_id) if _session_ready() and session != null else {}
	if inspector_empty != null:
		inspector_empty.visible = layer.is_empty()
	if layer.is_empty():
		return
	# One lock invariant for every authoring control: shared protection and the
	# selected layer lock both make the inspector read-only.
	var protected: bool = not session.is_editable() or bool(layer.get("locked", false))
	var layer_id := str(layer.get("layer_id", ""))
	var type := str(layer.get("type", ""))
	var is_source := type == "SOURCE"
	var is_fx := type == "FX"
	# Round-2 Finding 8: grouped, novice-readable inspector tabs. Raw enum
	# tokens are reserved for the ADVANCED tab.
	var tab_names: Array = ["LOOK", "MOTION", "MASK", "PALETTE", "ADVANCED", "DIAGNOSTICS"] if is_fx else ["SOURCE", "TRANSFORM", "DISPLACE", "MASK"]
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_content.add_child(tabs)
	var tab_pages: Dictionary = {}
	for tab_name in tab_names:
		var page := VBoxContainer.new()
		page.name = str(tab_name)
		page.add_theme_constant_override("separation", 4)
		tabs.add_child(page)
		tab_pages[str(tab_name)] = page
	var tab_identity := "LOOK" if is_fx else "SOURCE"
	var tab_transform := "LOOK" if is_fx else "TRANSFORM"
	var tab_motion := "MOTION" if is_fx else "DISPLACE"

	var title := Label.new()
	title.text = "%s  ·  %s" % [str(layer.get("name", "")), type]
	title.add_theme_font_size_override("font_size", UiTokens.T_META)
	title.add_theme_color_override("font_color", UiTokens.CREAM)
	_tab_page_add(tab_pages, tab_identity, title)
	var name_edit := LineEdit.new()
	name_edit.text = str(layer.get("name", ""))
	name_edit.editable = not protected
	name_edit.text_submitted.connect(func(text: String) -> void:
		if text.strip_edges() == "":
			return
		_edit_layer(layer_id, func(doc):
			(FxLookScript.find_layer(doc, layer_id))["name"] = text.strip_edges()
		)
	)
	_tab_page_add(tab_pages, tab_identity, name_edit)

	# --- Opacity / Blend ---------------------------------------------------------
	var opacity_slider := _inspector_slider("Opacity", 0.0, 1.0, 0.01, float(layer.get("opacity", 1.0)), protected, func(value: float) -> void:
		_edit_layer(layer_id, func(doc):
			(FxLookScript.find_layer(doc, layer_id))["opacity"] = value
		, false, true)
	, "layer:%s:opacity" % layer_id
	)
	_tab_page_add(tab_pages, tab_identity, opacity_slider)
	var blend := _inspector_option("Blend", FxLookScript.BLEND_MODES, str(layer.get("blend_mode", "NORMAL")), protected, func(value: String) -> void:
		_edit_layer(layer_id, func(doc):
			(FxLookScript.find_layer(doc, layer_id))["blend_mode"] = value
		, false)
	)
	_tab_page_add(tab_pages, tab_identity, blend)

	# --- Plane --------------------------------------------------------------------
	var plane_opt := _inspector_option("Plane", FxLookScript.PLANES, str(layer.get("plane", "TARGET_SOURCE")), protected or is_source, func(value: String) -> void:
		if is_source:
			action_status.text = "✗ The SOURCE layer is pinned to TARGET_SOURCE (specs/02 §10)"
			return
		_edit_layer(layer_id, func(doc):
			(FxLookScript.find_layer(doc, layer_id))["plane"] = value
		)
	)
	if is_source:
		plane_opt.tooltip_text = "Mandatory SOURCE is fixed to TARGET_SOURCE"
	plane_opt.set_meta("canonical_field", "layer.plane")
	_tab_page_add(tab_pages, tab_identity, plane_opt)

	if type == "FX":
		var input_row := _inspector_option("Input", FxLookScript.INPUTS, str(layer.get("input", "ORIGINAL_SOURCE")), protected, func(value: String) -> void:
			_edit_layer(layer_id, func(doc):
				(FxLookScript.find_layer(doc, layer_id))["input"] = value
			, false)
		)
		input_row.set_meta("canonical_field", "layer.input")
		_tab_page_add(tab_pages, "LOOK", input_row)

	# --- Transform ------------------------------------------------------------------
	var transform: Dictionary = layer.get("transform", {})
	var pos_row := HBoxContainer.new()
	var pos_label := Label.new()
	pos_label.text = "Position"
	pos_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	pos_label.custom_minimum_size.x = 70
	pos_row.add_child(pos_label)
	for axis in [0, 1]:
		var spin := SpinBox.new()
		spin.min_value = -2048
		spin.max_value = 2048
		spin.step = 1
		spin.value = float((transform.get("position_px", [0.0, 0.0]) as Array)[axis])
		spin.editable = not protected
		spin.value_changed.connect(func(value: float) -> void: _edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["transform"] as Dictionary)["position_px"][axis] = value
		, false, true, "layer:%s:transform.position_px.%d" % [layer_id, axis]))
		_wire_spin_transaction(spin, "layer:%s:transform.position_px.%d" % [layer_id, axis])
		pos_row.add_child(spin)
	_tab_page_add(tab_pages, tab_transform, pos_row)

	var scale_row := HBoxContainer.new()
	var scale_label := Label.new()
	scale_label.text = "Scale"
	scale_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	scale_label.custom_minimum_size.x = 70
	scale_row.add_child(scale_label)
	for axis in [0, 1]:
		var scale_spin := SpinBox.new()
		scale_spin.min_value = 0.05
		scale_spin.max_value = 8.0
		scale_spin.step = 0.05
		scale_spin.value = float((transform.get("scale", [1.0, 1.0]) as Array)[axis])
		scale_spin.editable = not protected
		scale_spin.value_changed.connect(func(value: float) -> void: _edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["transform"] as Dictionary)["scale"][axis] = value
		, false, true, "layer:%s:transform.scale.%d" % [layer_id, axis]))
		_wire_spin_transaction(scale_spin, "layer:%s:transform.scale.%d" % [layer_id, axis])
		scale_row.add_child(scale_spin)
	_tab_page_add(tab_pages, tab_transform, scale_row)

	var rot_pivot_row := HBoxContainer.new()
	var rot_label := Label.new()
	rot_label.text = "Rot°"
	rot_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	rot_pivot_row.add_child(rot_label)
	var rot_spin := SpinBox.new()
	rot_spin.min_value = -360
	rot_spin.max_value = 360
	rot_spin.step = 1
	rot_spin.value = float(transform.get("rotation_deg", 0.0))
	rot_spin.editable = not protected
	rot_spin.value_changed.connect(func(value: float) -> void: _edit_layer(layer_id, func(doc):
		var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
		(l["transform"] as Dictionary)["rotation_deg"] = value
	, false, true, "layer:%s:transform.rotation_deg" % layer_id))
	_wire_spin_transaction(rot_spin, "layer:%s:transform.rotation_deg" % layer_id)
	rot_pivot_row.add_child(rot_spin)
	var pivot_label := Label.new()
	pivot_label.text = "  Pivot"
	pivot_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	rot_pivot_row.add_child(pivot_label)
	for axis in [0, 1]:
		var pivot_spin := SpinBox.new()
		pivot_spin.min_value = 0.0
		pivot_spin.max_value = 1.0
		pivot_spin.step = 0.05
		pivot_spin.value = float((transform.get("pivot", [0.5, 0.5]) as Array)[axis])
		pivot_spin.editable = not protected
		pivot_spin.value_changed.connect(func(value: float) -> void: _edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["transform"] as Dictionary)["pivot"][axis] = value
		, false, true, "layer:%s:transform.pivot.%d" % [layer_id, axis]))
		_wire_spin_transaction(pivot_spin, "layer:%s:transform.pivot.%d" % [layer_id, axis])
		rot_pivot_row.add_child(pivot_spin)
	_tab_page_add(tab_pages, tab_transform, rot_pivot_row)

	var flip_row := HBoxContainer.new()
	for flip_key in ["flip_x", "flip_y"]:
		var check := CheckBox.new()
		check.text = str(flip_key).to_upper()
		check.button_pressed = bool(transform.get(flip_key, false))
		check.disabled = protected
		check.toggled.connect(func(pressed: bool) -> void: _edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["transform"] as Dictionary)[flip_key] = pressed
		, false))
		flip_row.add_child(check)
	var reset_transform := _styled_button("RESET TRANSFORM", func() -> void:
		_edit_layer(layer_id, func(doc):
			(FxLookScript.find_layer(doc, layer_id))["transform"] = FxLookScript.neutral_transform()
		)
	)
	reset_transform.disabled = protected
	flip_row.add_child(reset_transform)
	_tab_page_add(tab_pages, tab_transform, flip_row)

	# --- Displacement -----------------------------------------------------------------
	var displacement: Dictionary = layer.get("displacement", {})
	var disp_head := HBoxContainer.new()
	var disp_check := CheckBox.new()
	disp_check.text = "DISPLACE"
	disp_check.button_pressed = bool(displacement.get("enabled", false))
	disp_check.disabled = protected
	disp_check.toggled.connect(func(pressed: bool) -> void: _edit_layer(layer_id, func(doc):
		var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
		(l["displacement"] as Dictionary)["enabled"] = pressed
	, false))
	disp_head.add_child(disp_check)
	_tab_page_add(tab_pages, tab_motion, disp_head)
	var driver_row := _inspector_option("Driver", FxLookScript.DISPLACEMENT_DRIVERS, str(displacement.get("driver", "NOISE")), protected, func(value: String) -> void:
		_edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["displacement"] as Dictionary)["driver"] = value
		, true)
	)
	driver_row.set_meta("canonical_field", "displacement.driver")
	_tab_page_add(tab_pages, tab_motion, driver_row)
	var amount_row := HBoxContainer.new()
	var amount_label := Label.new()
	amount_label.text = "Amount"
	amount_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	amount_label.custom_minimum_size.x = 70
	amount_row.add_child(amount_label)
	for axis in [0, 1]:
		var amount_spin := SpinBox.new()
		amount_spin.min_value = -256
		amount_spin.max_value = 256
		amount_spin.step = 1
		amount_spin.value = float((displacement.get("amount_px", [0.0, 0.0]) as Array)[axis])
		amount_spin.editable = not protected
		amount_spin.value_changed.connect(func(value: float) -> void: _edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["displacement"] as Dictionary)["amount_px"][axis] = value
		, false, true, "layer:%s:displacement.amount_px.%d" % [layer_id, axis]))
		_wire_spin_transaction(amount_spin, "layer:%s:displacement.amount_px.%d" % [layer_id, axis])
		amount_row.add_child(amount_spin)
	_tab_page_add(tab_pages, tab_motion, amount_row)
	var disp_misc := HBoxContainer.new()
	for spec in [["Speed", "speed", 0.0, 8.0, 0.05], ["Seed", "seed", 0.0, 999.0, 1.0], ["Angle", "angle_deg", -360.0, 360.0, 1.0]]:
		var misc_label := Label.new()
		misc_label.text = " " + str(spec[0])
		misc_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		disp_misc.add_child(misc_label)
		var misc_spin := SpinBox.new()
		misc_spin.min_value = float(spec[2])
		misc_spin.max_value = float(spec[3])
		misc_spin.step = float(spec[4])
		misc_spin.value = float(displacement.get(str(spec[1]), spec[2]))
		misc_spin.custom_minimum_size.x = 84
		misc_spin.set_meta("canonical_field", "displacement.%s" % str(spec[1]))
		misc_spin.editable = not protected
		misc_spin.value_changed.connect(func(value: float) -> void: _edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["displacement"] as Dictionary)[str(spec[1])] = value
		, false, true, "layer:%s:displacement.%s" % [layer_id, str(spec[1])]))
		_wire_spin_transaction(misc_spin, "layer:%s:displacement.%s" % [layer_id, str(spec[1])])
		disp_misc.add_child(misc_spin)
	_tab_page_add(tab_pages, tab_motion, disp_misc)
	var edge_row := _inspector_option("Edge", FxLookScript.EDGE_MODES, str(displacement.get("edge_mode", "TRANSPARENT")), protected, func(value: String) -> void:
		_edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["displacement"] as Dictionary)["edge_mode"] = value
		, false)
	)
	_tab_page_add(tab_pages, tab_motion, edge_row)
	# UI-01: displacement fully authorable — scale/phase/time/custom/influence.
	var disp_extra := HBoxContainer.new()
	for spec in [["Scale", "scale", 0.05, 8.0, 0.05], ["Phase", "phase", -8.0, 8.0, 0.1]]:
		var extra_label := Label.new()
		extra_label.text = " " + str(spec[0])
		extra_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		disp_extra.add_child(extra_label)
		var extra_spin := SpinBox.new()
		extra_spin.min_value = float(spec[2])
		extra_spin.max_value = float(spec[3])
		extra_spin.step = float(spec[4])
		extra_spin.value = clampf(float(displacement.get(str(spec[1]), 1.0 if str(spec[1]) == "scale" else 0.0)), float(spec[2]), float(spec[3]))
		extra_spin.custom_minimum_size.x = 84
		extra_spin.editable = not protected
		extra_spin.value_changed.connect(func(value: float) -> void: _edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["displacement"] as Dictionary)[str(spec[1])] = value
		, false, true, "layer:%s:displacement.%s" % [layer_id, str(spec[1])]))
		_wire_spin_transaction(extra_spin, "layer:%s:displacement.%s" % [layer_id, str(spec[1])])
		disp_extra.add_child(extra_spin)
	_tab_page_add(tab_pages, tab_motion, disp_extra)
	_tab_page_add(tab_pages, tab_motion, _inspector_option("Time", FxLookScript.TIME_SOURCES, str(displacement.get("time_source", "PRESENTATION_TIME")), protected, func(value: String) -> void:
		_edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["displacement"] as Dictionary)["time_source"] = value
		, true)
	))
	_tab_page_add(tab_pages, tab_motion, _dep_asset_row("displacement.custom_texture", "Custom tex", layer, layer_id, protected, func(text: String) -> void:
		_edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["displacement"] as Dictionary)["custom_texture"] = text.strip_edges() if text.strip_edges() != "" else null
		, true)
	))
	_dep_note(tab_pages, tab_motion, "displacement.custom_texture", layer)
	# --- influence mask subgroup (same contract as layer.mask, pre-displacement)
	_tab_page_add(tab_pages, tab_motion, _fx_group_header("INFLUENCE"))
	var infl = displacement.get("influence_mask", null)
	var infl_dict: Dictionary = infl if infl is Dictionary else {}
	var infl_check := CheckBox.new()
	infl_check.set_meta("canonical_field", "displacement.influence.enabled")
	infl_check.text = "INFLUENCE"
	infl_check.button_pressed = bool(infl_dict.get("enabled", false))
	infl_check.disabled = protected
	infl_check.toggled.connect(func(pressed: bool) -> void: _edit_layer(layer_id, func(doc):
		var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
		var d: Dictionary = l["displacement"]
		if d.get("influence_mask", null) == null or not ((d["influence_mask"]) is Dictionary):
			d["influence_mask"] = FxLookScript.neutral_mask()
		(d["influence_mask"] as Dictionary)["enabled"] = pressed
	, true))
	_tab_page_add(tab_pages, tab_motion, infl_check)
	var infl_source_row := _inspector_option("I-Source", FxLookScript.MASK_SOURCES, str(infl_dict.get("source", "NONE")), protected, func(value: String) -> void:
		_edit_layer(layer_id, func(doc):
			_disp_ensure_influence(doc, layer_id)["source"] = value
		, true)
	)
	infl_source_row.set_meta("canonical_field", "displacement.influence.source")
	_tab_page_add(tab_pages, tab_motion, infl_source_row)
	_tab_page_add(tab_pages, tab_motion, _inspector_option("I-Region", FxLookScript.MASK_REGIONS, str(infl_dict.get("region", "FULL")), protected, func(value: String) -> void:
		_edit_layer(layer_id, func(doc):
			_disp_ensure_influence(doc, layer_id)["region"] = value
		, true)
	))
	_tab_page_add(tab_pages, tab_motion, _inspector_option("I-Space", FxLookScript.MASK_SPACES, str(infl_dict.get("space", "LAYER_SPACE")), protected, func(value: String) -> void:
		_edit_layer(layer_id, func(doc):
			_disp_ensure_influence(doc, layer_id)["space"] = value
		, true)
	))
	var infl_misc := HBoxContainer.new()
	for spec in [["W", "width_px", 0.0, 256.0, 1.0], ["F", "feather_px", 0.0, 256.0, 1.0], ["±", "expand_contract_px", -128.0, 128.0, 1.0]]:
		var infl_label := Label.new()
		infl_label.text = " " + str(spec[0])
		infl_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		infl_misc.add_child(infl_label)
		var infl_spin := SpinBox.new()
		infl_spin.min_value = float(spec[2])
		infl_spin.max_value = float(spec[3])
		infl_spin.step = float(spec[4])
		infl_spin.value = float(infl_dict.get(str(spec[1]), 0.0))
		infl_spin.custom_minimum_size.x = 84
		infl_spin.editable = not protected
		infl_spin.value_changed.connect(func(value: float) -> void: _edit_layer(layer_id, func(doc):
			_disp_ensure_influence(doc, layer_id)[str(spec[1])] = value
		, false, true, "layer:%s:influence.%s" % [layer_id, str(spec[1])]))
		_wire_spin_transaction(infl_spin, "layer:%s:influence.%s" % [layer_id, str(spec[1])])
		infl_misc.add_child(infl_spin)
	var infl_invert := CheckBox.new()
	infl_invert.text = "INV"
	infl_invert.button_pressed = bool(infl_dict.get("invert", false))
	infl_invert.disabled = protected
	infl_invert.toggled.connect(func(pressed: bool) -> void: _edit_layer(layer_id, func(doc):
		_disp_ensure_influence(doc, layer_id)["invert"] = pressed
	, true))
	infl_misc.add_child(infl_invert)
	_tab_page_add(tab_pages, tab_motion, infl_misc)
	_tab_page_add(tab_pages, tab_motion, _dep_asset_row("displacement.influence_mask.custom_mask", "I-Custom", layer, layer_id, protected, func(text: String) -> void:
		_edit_layer(layer_id, func(doc):
			_disp_ensure_influence(doc, layer_id)["custom_mask"] = text.strip_edges() if text.strip_edges() != "" else null
		, true)
	))
	_dep_note(tab_pages, tab_motion, "displacement.influence_mask.custom_mask", layer)

	# --- Mask -------------------------------------------------------------------------
	var mask: Dictionary = layer.get("mask", {})
	var mask_check := CheckBox.new()
	mask_check.set_meta("canonical_field", "mask.enabled")
	mask_check.text = "MASK"
	mask_check.button_pressed = bool(mask.get("enabled", false))
	mask_check.disabled = protected
	mask_check.toggled.connect(func(pressed: bool) -> void: _edit_layer(layer_id, func(doc):
		var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
		(l["mask"] as Dictionary)["enabled"] = pressed
	, true))
	_tab_page_add(tab_pages, "MASK", mask_check)
	var mask_source_row := _inspector_option("Source", FxLookScript.MASK_SOURCES, str(mask.get("source", "NONE")), protected, func(value: String) -> void:
		_edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["mask"] as Dictionary)["source"] = value
		, true)
	)
	mask_source_row.set_meta("canonical_field", "mask.source")
	_tab_page_add(tab_pages, "MASK", mask_source_row)
	var mask_region_row := _inspector_option("Region", FxLookScript.MASK_REGIONS, str(mask.get("region", "FULL")), protected, func(value: String) -> void:
		_edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["mask"] as Dictionary)["region"] = value
		, false)
	)
	mask_region_row.set_meta("canonical_field", "mask.region")
	_tab_page_add(tab_pages, "MASK", mask_region_row)
	_tab_page_add(tab_pages, "MASK", _inspector_option("Space", FxLookScript.MASK_SPACES, str(mask.get("space", "LAYER_SPACE")), protected, func(value: String) -> void:
		_edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["mask"] as Dictionary)["space"] = value
		, false)
	))
	var mask_misc := HBoxContainer.new()
	for spec in [["W", "width_px", 0.0, 256.0, 1.0], ["F", "feather_px", 0.0, 256.0, 1.0], ["±", "expand_contract_px", -128.0, 128.0, 1.0]]:
		var misc_label2 := Label.new()
		misc_label2.text = " " + str(spec[0])
		misc_label2.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		mask_misc.add_child(misc_label2)
		var misc_spin2 := SpinBox.new()
		misc_spin2.set_meta("canonical_field", "mask." + str(spec[1]))
		misc_spin2.min_value = float(spec[2])
		misc_spin2.max_value = float(spec[3])
		misc_spin2.step = float(spec[4])
		misc_spin2.value = float(mask.get(str(spec[1]), 0.0))
		misc_spin2.custom_minimum_size.x = 84
		misc_spin2.editable = not protected
		misc_spin2.value_changed.connect(func(value: float) -> void: _edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["mask"] as Dictionary)[str(spec[1])] = value
		, false, true, "layer:%s:mask.%s" % [layer_id, str(spec[1])]))
		_wire_spin_transaction(misc_spin2, "layer:%s:mask.%s" % [layer_id, str(spec[1])])
		mask_misc.add_child(misc_spin2)
	var invert_check := CheckBox.new()
	invert_check.set_meta("canonical_field", "mask.invert")
	invert_check.text = "INVERT"
	invert_check.button_pressed = bool(mask.get("invert", false))
	invert_check.disabled = protected
	invert_check.toggled.connect(func(pressed: bool) -> void: _edit_layer(layer_id, func(doc):
		var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
		(l["mask"] as Dictionary)["invert"] = pressed
	, false))
	mask_misc.add_child(invert_check)
	_tab_page_add(tab_pages, "MASK", mask_misc)
	_tab_page_add(tab_pages, "MASK", _dep_asset_row("mask.custom_mask", "Custom", layer, layer_id, protected, func(text: String) -> void:
		_edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["mask"] as Dictionary)["custom_mask"] = text.strip_edges() if text.strip_edges() != "" else null
		, true)
	))
	_dep_note(tab_pages, "MASK", "mask.custom_mask", layer)

	# --- FX amounts + cost ---------------------------------------------------------------
	if is_fx:
		var fx: Dictionary = layer.get("fx", {})
		for key in ["fringe", "rgb", "dither", "intensity", "size"]:
			_tab_page_add(tab_pages, "LOOK", _inspector_slider(str(key).to_upper(), 0.0, 4.0, 0.05, float(fx.get(key, 1.0 if key in ["intensity", "size"] else 0.0)), protected, func(value: float) -> void:
				_edit_layer(layer_id, func(doc):
					var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
					(l["fx"] as Dictionary)[key] = value
				, false, true)
			, "fx:%s:%s" % [layer_id, key]
			))
		# UI-01: intent macro groups — additive UX over the same canonical fx
		# fields (macros never replace the direct expert controls in ADVANCED).
		var look_page: VBoxContainer = _tab_page(tab_pages, "LOOK")
		if look_page == null:
			return
		look_page.add_child(_fx_group_header("FRINGE"))
		for spec in [["Fringe", "fringe"], ["Edge width", "edge_width"], ["Wind reach", "wind_reach"], ["Wind trail", "wind_trail"], ["Split", "split_separation"]]:
			look_page.add_child(_fx_slider(str(spec[0]), str(spec[1]), fx, layer_id, protected))
		look_page.add_child(_fx_group_header("RGB"))
		for spec in [["RGB", "rgb"], ["Shift px", "rgb_shift_amount"], ["Shift angle", "rgb_shift_angle"], ["Shift alpha", "rgb_shift_alpha"]]:
			look_page.add_child(_fx_slider(str(spec[0]), str(spec[1]), fx, layer_id, protected))
		look_page.add_child(_fx_group_header("DITHER"))
		# NOTE: dither_threshold has no control anywhere by contract (CT-10,
		# LEGACY_DEAD_SURFACE): persisted + validated + passed through, but
		# declaration-only in legacy AND vNEXT shaders — presenting it as
		# editable would fake capability. See AUTHORING_INVENTORY.
		for spec in [["Dither", "dither"], ["Pixel", "dither_pixel"], ["Levels", "dither_levels"]]:
			look_page.add_child(_fx_slider(str(spec[0]), str(spec[1]), fx, layer_id, protected))
		look_page.add_child(_fx_group_header("FLOW"))
		var flow_note := Label.new()
		flow_note.text = "Flow drives the fringe field — needs Fringe > 0."
		flow_note.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		flow_note.add_theme_color_override("font_color", UiTokens.DISABLED)
		look_page.add_child(flow_note)
		for spec in [["Flow", "flow"], ["Strength", "flow_strength"]]:
			look_page.add_child(_fx_slider(str(spec[0]), str(spec[1]), fx, layer_id, protected))
		look_page.add_child(_fx_group_header("GRADE"))
		for spec in [["Grade amount", "base_grade_amount"], ["Brightness", "grade_brightness"], ["Contrast", "grade_contrast"], ["Saturation", "grade_saturation"], ["Gamma", "grade_gamma"]]:
			look_page.add_child(_fx_slider(str(spec[0]), str(spec[1]), fx, layer_id, protected))
		look_page.add_child(_fx_group_header("MONO"))
		for spec in [["Threshold", "mono_threshold"]]:
			look_page.add_child(_fx_slider(str(spec[0]), str(spec[1]), fx, layer_id, protected))
		look_page.add_child(_fx_option("Base", "base_mode", fx, layer_id, protected))
		_build_palette_page(tab_pages, layer, layer_id, protected)
		_build_motion_page(tab_pages, layer, layer_id, protected)
		if is_fx:
			var intent_page: VBoxContainer = _tab_page(tab_pages, "LOOK")
			if intent_page != null:
				_build_recipe_macros(intent_page, layer, layer_id, protected)
	var layer_cost: Dictionary = FxCostScript.layer_cost(layer)
	inspector_cost_badge = Label.new()
	inspector_cost_badge.text = "LIVE COST %.1f · %s" % [float(layer_cost["cost"]), ", ".join(layer_cost["factors"])]
	inspector_cost_badge.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	inspector_cost_badge.add_theme_color_override("font_color", UiTokens.DISABLED)
	inspector_cost_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tab_page_add(tab_pages, tab_identity, inspector_cost_badge)
	_build_advanced_page(tab_pages, layer, layer_id, type, protected)
	var restored_tab := tab_names.find(_inspector_tab_name)
	if restored_tab >= 0:
		tabs.current_tab = restored_tab
	call_deferred("_restore_inspector_navigation")
	_restore_canonical_focus(focus_field)
	_apply_lab_ui_contract()

func _restore_inspector_navigation() -> void:
	if inspector_scroll != null and is_instance_valid(inspector_scroll):
		inspector_scroll.scroll_vertical = int(_inspector_scroll_value)

func _focused_canonical_field() -> String:
	var owner: Node = get_viewport().gui_get_focus_owner()
	while owner != null and owner != inspector_content:
		if owner.has_meta("canonical_field"):
			return str(owner.get_meta("canonical_field"))
		owner = owner.get_parent()
	return ""

func _restore_canonical_focus(field: String) -> void:
	if field == "":
		return
	var found := _find_canonical_control(inspector_content, field)
	if found != null:
		(found as Control).grab_focus()

func _find_canonical_control(node: Node, field: String) -> Control:
	if node.has_meta("canonical_field") and str(node.get_meta("canonical_field")) == field:
		if node is Control and (node as Control).focus_mode != Control.FOCUS_NONE:
			return node as Control
		var focusable := _first_focusable(node)
		if focusable != null:
			return focusable
	for child in node.get_children():
		var nested := _find_canonical_control(child, field)
		if nested != null:
			return nested
	return null

func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE:
			return child as Control
		var nested := _first_focusable(child)
		if nested != null:
			return nested
	return null

# UI-01: macro-group header + canonical-fx slider bound through _edit_layer
# (live preview). Macros are additive UX; ADVANCED keeps direct controls.
func _fx_group_header(text: String) -> Control:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", UiTokens.T_META)
	header.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	return header

func _fx_slider(label_text: String, fx_key: String, fx: Dictionary, layer_id: String, protected: bool, regen_palette := false) -> Control:
	# UI-05: ranges/units come from the canonical field metadata (single
	# source) — macros cannot drift from expert controls or the model.
	var meta: Dictionary = FxLookScript.field_meta_all().get(fx_key, {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05})
	var row := _inspector_slider(label_text, float(meta.get("min", 0.0)), float(meta.get("max", 4.0)), float(meta.get("step", 0.05)), clampf(float(fx.get(fx_key, float(meta.get("min", 0.0)))), float(meta.get("min", 0.0)), float(meta.get("max", 4.0))), protected, func(value: float) -> void:
		_edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["fx"] as Dictionary)[fx_key] = value
			if regen_palette:
				_regenerate_palette(doc, layer_id)
		, false, true)
	, "fx:%s:%s" % [layer_id, fx_key]
	)
	row.set_meta("canonical_field", fx_key)
	return row

# UI-02 quality: palette intent edits immediately regenerate unlocked colors
# in the SAME transaction — output can never silently go stale behind intent.
func _regenerate_palette(doc: Dictionary, layer_id: String) -> void:
	var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
	if l.is_empty():
		return
	var lfx: Dictionary = l["fx"]
	var dom_arr: Array = lfx.get("palette_source_color", [0.5, 0.5, 0.5, 1.0])
	var distant_arr: Array = lfx.get("fringe_color_b", [1.0, 0.4, 0.85, 1.0])
	var generated: Dictionary = FxLookScript.generate_palette(doc, layer_id,
		Color(float(dom_arr[0]), float(dom_arr[1]), float(dom_arr[2]), 1.0),
		Color(float(distant_arr[0]), float(distant_arr[1]), float(distant_arr[2]), 1.0))
	if not bool(generated.get("ok", false)):
		action_status.text = "✗ palette generate: " + str(generated.get("errors", []))

# UI-01/UI-07: asset reference row (LineEdit committed on submit) for
# dependency-bearing modes. Empty clears to null (procedural path).
func _asset_row(label_text: String, current: String, protected: bool, on_submit: Callable) -> Control:
	# Legacy plain path row (kept for non-dependency uses, if any). All
	# dependency-bearing asset fields use _dep_asset_row instead.
	return _dep_asset_row("", label_text, {}, "", protected, on_submit)

# UI-07/08: one shared typed asset control for every dependency-bearing
# asset field (displacement.custom_texture, influence custom_mask,
# mask.custom_mask, fx.treatment_mask_path). Display + BROWSE/REPLACE +
# CLEAR + status badge share FxAssets dependency truth — never local
# string-emptiness checks.
var asset_dialog: FileDialog
var _asset_pick_setter: Callable

func _ensure_asset_dialog() -> void:
	if asset_dialog != null:
		return
	asset_dialog = FileDialog.new()
	asset_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	asset_dialog.access = FileDialog.ACCESS_FILESYSTEM
	asset_dialog.filters = PackedStringArray(["*.png ; PNG images", "*.jpg,*.jpeg ; JPEG images", "*.webp ; WebP images", "*.bmp ; BMP images", "*.exr ; EXR images", "*.tres,*.res ; Godot resources (Texture2D)"])
	asset_dialog.file_selected.connect(_on_asset_picked)
	add_child(asset_dialog)

func _open_asset_picker(setter: Callable, current: String) -> void:
	_ensure_asset_dialog()
	_asset_pick_setter = setter
	if current.strip_edges() != "":
		asset_dialog.current_path = current.strip_edges()
	asset_dialog.popup_centered(Vector2i(720, 480))

func _on_asset_picked(path: String) -> void:
	asset_dialog.hide()
	if _asset_pick_setter.is_valid():
		_asset_pick_setter.call(path)
		_asset_pick_setter = Callable()

func _dep_asset_row(field_id: String, label_text: String, layer: Dictionary, layer_id: String, protected: bool, set_path: Callable) -> Control:
	var raw_path = FxAssetsScript.field_path(field_id, layer) if field_id != "" else null
	# NOTE: GDScript `or` returns bool — never `str(x or "")` (yields "false").
	var current := str(raw_path) if raw_path != null else ""
	var wrap := VBoxContainer.new()
	if field_id != "":
		wrap.set_meta("canonical_field", field_id)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	label.custom_minimum_size.x = 70
	row.add_child(label)
	var edit := LineEdit.new()
	edit.name = "AssetPath"
	edit.text = current
	edit.tooltip_text = current
	edit.placeholder_text = "pick or type a texture path"
	edit.editable = not protected
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(text: String) -> void:
		set_path.call(text.strip_edges())
	)
	row.add_child(edit)
	var pick := Button.new()
	pick.name = "AssetBrowse"
	pick.text = "REPLACE" if current.strip_edges() != "" else "BROWSE"
	pick.disabled = protected
	pick.pressed.connect(func() -> void:
		_open_asset_picker(set_path, current)
	)
	row.add_child(pick)
	var clear := Button.new()
	clear.name = "AssetClear"
	clear.text = "CLEAR"
	clear.tooltip_text = "Clears the path only — never changes the mode."
	clear.disabled = protected or current.strip_edges() == ""
	clear.pressed.connect(func() -> void:
		set_path.call("")
	)
	row.add_child(clear)
	wrap.add_child(row)
	var badge := Label.new()
	badge.name = "AssetStatus"
	badge.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if field_id == "":
		badge.text = "○ path"
		badge.add_theme_color_override("font_color", UiTokens.DISABLED)
	else:
		var st: Dictionary = FxAssetsScript.dependency_status(field_id, layer, production.data_dir)
		var state := str(st.get("state", ""))
		match state:
			"COMPLETE":
				if bool(st.get("needs_harvest", false)):
					badge.text = "✓ COMPLETE · harvest on apply"
					badge.add_theme_color_override("font_color", UiTokens.CREAM)
				else:
					badge.text = "✓ COMPLETE"
					badge.add_theme_color_override("font_color", UiTokens.TEAM_A)
			"MISSING":
				badge.text = "⚠ INCOMPLETE — " + str(st.get("detail", "required asset missing"))
				badge.add_theme_color_override("font_color", UiTokens.ERROR)
			"NOT_REQUIRED":
				badge.text = "○ not required by current mode"
				badge.add_theme_color_override("font_color", UiTokens.DISABLED)
			"DORMANT":
				badge.text = "○ dormant — kept, not required by mode"
				badge.add_theme_color_override("font_color", UiTokens.DISABLED)
			"DORMANT_WARNING":
				badge.text = "○ dormant — invalid while unused"
				badge.add_theme_color_override("font_color", UiTokens.CREAM)
			_:
				badge.text = "✖ INVALID — " + str(st.get("detail", state))
				badge.add_theme_color_override("font_color", UiTokens.ERROR)
		badge.tooltip_text = str(st.get("detail", ""))
	wrap.add_child(badge)
	return wrap

# Tab-level INCOMPLETE note from the SAME central truth (replaces the loose
# per-mode string-emptiness chains).
func _dep_note(tab_pages: Dictionary, tab_name: String, field_id: String, layer: Dictionary) -> void:
	var st: Dictionary = FxAssetsScript.dependency_status(field_id, layer, production.data_dir)
	if bool(st.get("required", false)) and str(st.get("state", "")) != "COMPLETE":
		_disp_incomplete(tab_pages, tab_name, str(st.get("detail", field_id)))

# UI-01/UI-07: honest INCOMPLETE state — a visible red row iff a required
# asset is missing. Empty message = complete (no row).
func _incomplete_note(message: String) -> Label:
	var note := Label.new()
	note.text = "⚠ INCOMPLETE: " + message
	note.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	note.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note

func _disp_incomplete(tab_pages: Dictionary, tab_name: String, message: String) -> void:
	if message == "":
		return
	_tab_page_add(tab_pages, tab_name, _incomplete_note(message))

func _disp_ensure_influence(doc: Dictionary, layer_id: String) -> Dictionary:
	var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
	var d: Dictionary = l["displacement"]
	if d.get("influence_mask", null) == null or not (d["influence_mask"] is Dictionary):
		d["influence_mask"] = FxLookScript.neutral_mask()
	return d["influence_mask"]

# UI-05: generic meta-driven option. Numeric enums map by index, string
# enums (time_source) map by value.
func _fx_option(label_text: String, fx_key: String, fx: Dictionary, layer_id: String, protected: bool) -> Control:
	var meta: Dictionary = FxLookScript.field_meta_all().get(fx_key, {"kind": "option", "options": []})
	var options: Array = meta.get("options", [])
	var current = fx.get(fx_key, 0.0)
	var selected := 0
	if current is String:
		selected = maxi(0, options.find(str(current)))
	else:
		selected = clampi(int(float(current)), 0, maxi(0, options.size() - 1))
	var optrow := _inspector_option(label_text, options, str(options[selected]) if not options.is_empty() else "", protected, func(value: String) -> void:
		_edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			if (fx.get(fx_key, 0.0)) is String or str(fx.get(fx_key, "")) in options:
				(l["fx"] as Dictionary)[fx_key] = value
			else:
				(l["fx"] as Dictionary)[fx_key] = float(options.find(value))
		, false)
	)
	optrow.set_meta("canonical_field", fx_key)
	return optrow

func _inspector_slider(label_text: String, min_value: float, max_value: float, step: float, value: float, disabled: bool, on_change: Callable, transaction_key := "") -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	label.custom_minimum_size.x = 70
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.editable = not disabled
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(next_value: float) -> void:
		if str(transaction_key) != "":
			_begin_ui_transaction(str(transaction_key))
		on_change.call(next_value)
	)
	row.add_child(slider)
	if str(transaction_key) != "":
		_wire_slider_transaction(row, str(transaction_key), disabled)
	return row

func _build_palette_page(tab_pages: Dictionary, layer: Dictionary, layer_id: String, protected: bool) -> void:
	# UI-02: palette editing is canonical layer.fx state (strategy/locks/H/S/V
	# author the intent; GENERATE materializes fringe_color_a/b; the shader
	# only ever renders the materialized colors).
	var page: VBoxContainer = _tab_page(tab_pages, "PALETTE")
	if page == null:
		return
	var fx: Dictionary = layer.get("fx", {})
	var names := ["DOMINANT + DISTANT", "COMPLEMENT", "SPLIT COMPLEMENT", "ANALOGOUS", "TRIADIC", "MONOCHROME"]
	page.add_child(_inspector_option("Strategy", names, names[clampi(int(float(fx.get("palette_strategy", 0.0))), 0, 5)], protected, func(value: String) -> void:
		_edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["fx"] as Dictionary)["palette_strategy"] = float(names.find(value))
			_regenerate_palette(doc, layer_id)
		, false, true)
	))
	var lockrow := HBoxContainer.new()
	for pair in [["Lock A", "palette_lock_a"], ["Lock B", "palette_lock_b"], ["Swap A/B", "palette_swap"]]:
		var check := CheckBox.new()
		check.text = str(pair[0])
		check.button_pressed = bool(fx.get(str(pair[1]), false))
		check.disabled = protected
		check.toggled.connect(func(pressed: bool) -> void: _edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["fx"] as Dictionary)[str(pair[1])] = pressed
		, false, true))
		lockrow.add_child(check)
	page.add_child(lockrow)
	var scol := HBoxContainer.new()
	var slab := Label.new()
	slab.text = "Source"
	slab.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	slab.custom_minimum_size.x = 70
	scol.add_child(slab)
	var picker := ColorPickerButton.new()
	picker.set_meta("canonical_field", "palette_source_color")
	var sc: Array = fx.get("palette_source_color", [0.5, 0.5, 0.5, 1.0])
	picker.color = Color(float(sc[0]), float(sc[1]), float(sc[2]), 1.0)
	picker.disabled = protected
	picker.custom_minimum_size = Vector2(96, 22)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.color_changed.connect(func(color: Color) -> void: _edit_layer(layer_id, func(doc):
		var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
		(l["fx"] as Dictionary)["palette_source_color"] = [color.r, color.g, color.b, 1.0]
		_regenerate_palette(doc, layer_id)
	, false, true))
	scol.add_child(picker)
	page.add_child(scol)
	page.add_child(_fx_slider("Hue offset", "palette_hue_offset", fx, layer_id, protected, true))
	page.add_child(_fx_slider("Saturation", "palette_saturation", fx, layer_id, protected, true))
	page.add_child(_fx_slider("Value", "palette_value", fx, layer_id, protected, true))
	var gen := Button.new()
	gen.text = "REGENERATE UNLOCKED FROM STRATEGY"
	gen.disabled = protected
	gen.tooltip_text = "Re-materializes unlocked colors (intent edits already regenerate live)"
	gen.pressed.connect(func() -> void:
		_edit_layer(layer_id, func(doc):
			_regenerate_palette(doc, layer_id)
		, true, true)
	)
	page.add_child(gen)
	# A/B direct authoring: choosing a color sets ONLY the color. Locks stay
	# explicit separate controls, so authored-unlocked is a reachable state
	# (no surprise second mutation from a picker). Rows stack vertically with
	# expanding pickers: side-by-side at minimum size crushed them to ~7 px.
	var abcol := VBoxContainer.new()
	for pair in [["A", "fringe_color_a"], ["B", "fringe_color_b"]]:
		var abrow := HBoxContainer.new()
		var cap := Label.new()
		cap.text = str(pair[0])
		cap.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		cap.custom_minimum_size.x = 24
		abrow.add_child(cap)
		var pick := ColorPickerButton.new()
		pick.set_meta("canonical_field", str(pair[1]))
		var carr: Array = fx.get(str(pair[1]), [1.0, 1.0, 1.0, 1.0])
		pick.color = Color(float(carr[0]), float(carr[1]), float(carr[2]), 1.0)
		pick.disabled = protected
		pick.custom_minimum_size = Vector2(96, 22)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.tooltip_text = str(pair[1]) + " (sets the color only; use Lock to pin it)"
		pick.color_changed.connect(func(color: Color) -> void: _edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["fx"] as Dictionary)[str(pair[1])] = [color.r, color.g, color.b, 1.0]
		, false, true))
		abrow.add_child(pick)
		abcol.add_child(abrow)
	page.add_child(abcol)

func _build_motion_page(tab_pages: Dictionary, layer: Dictionary, layer_id: String, protected: bool) -> void:
	# UI-03: motion tracks fully authorable. Four canonical domains; each has
	# an enable gate plus a full envelope track. Anchor is "manual" (fired via
	# the TRIGGER button through the live renderer) or a match-flow event
	# name. Ranges mirror validator + runtime clamps (TM-07): attack/release
	# > 0, sustain in [0,1], times >= 0.
	var page: VBoxContainer = _tab_page(tab_pages, "MOTION")
	if page == null:
		return
	var motion = layer.get("motion", {})
	var header := Label.new()
	header.text = "MOTION ENVELOPES"
	header.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	header.add_theme_color_override("font_color", UiTokens.ACCENT)
	page.add_child(header)
	if not (motion is Dictionary) or (motion as Dictionary).is_empty():
		var note := Label.new()
		note.text = "No envelope fields on this layer yet."
		note.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		note.add_theme_color_override("font_color", UiTokens.DISABLED)
		page.add_child(note)
		return
	var enabled: Dictionary = (motion as Dictionary).get("enabled", {})
	var tracks: Dictionary = (motion as Dictionary).get("tracks", {})
	var curves := ["linear", "cubic_in", "cubic_out", "sine_in_out", "back_out"]
	# Anchor presets come from the event authority (manual/fixed plus the
	# deterministic entry/hold anchors), never from a parallel hardcoded
	# table. Unknown names are INVALID: the envelope never fires and
	# production validation rejects them (typo footgun closed).
	var anchors: Array = ["manual", "fixed"]
	if runtime != null and runtime.has_method("event_marks"):
		for ev in (runtime.event_marks() as Dictionary).keys():
			if str(ev) not in anchors:
				anchors.append(str(ev))
	else:
		anchors = ["manual", "fixed", "vs_enter", "stage_reveal", "fighter_reveal", "clash_impact", "hold_enter"]
	for domain in ["dither", "fringe", "flow", "rgb"]:
		var on := bool(enabled.get(str(domain), false))
		var dhead := HBoxContainer.new()
		var dlabel := Label.new()
		dlabel.text = str(domain).to_upper()
		dlabel.add_theme_font_size_override("font_size", UiTokens.T_META)
		dlabel.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
		dlabel.custom_minimum_size.x = 90
		dhead.add_child(dlabel)
		var en := CheckBox.new()
		en.text = "ON"
		en.button_pressed = on
		en.disabled = protected
		en.toggled.connect(func(pressed: bool) -> void: _edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			((l["motion"] as Dictionary)["enabled"] as Dictionary)[str(domain)] = pressed
		, true))
		dhead.add_child(en)
		var track: Dictionary = tracks.get(str(domain), {})
		var is_manual := str(track.get("anchor", "manual")) == "manual"
		var trig := Button.new()
		trig.text = "TRIGGER"
		trig.tooltip_text = "Restart the manual-anchored %s envelope at the current clock (live preview)" % str(domain) if is_manual else "Trigger needs a manual anchor (this track arms at anchor_time/event)"
		trig.disabled = protected or not on or not is_manual
		trig.pressed.connect(func() -> void:
			if renderer != null and renderer.has_method("trigger_manual"):
				renderer.trigger_manual(str(domain))
			else:
				action_status.text = "✗ live renderer unavailable for trigger"
		)
		dhead.add_child(trig)
		page.add_child(dhead)
		if not on:
			var off := Label.new()
			off.text = "OFF — parameters parked (enable to author live)"
			off.add_theme_font_size_override("font_size", UiTokens.T_HELP)
			off.add_theme_color_override("font_color", UiTokens.DISABLED)
			page.add_child(off)
		# Anchor row: preset option writes the anchor text (experts keep the
		# LineEdit-equivalent via CUSTOM preset value passthrough below).
		page.add_child(_motion_row("Anchor", _motion_anchor_option(layer_id, str(domain), str(track.get("anchor", "manual")), anchors, protected), on and not protected))
		# Anchor time is capped at the lab presentation length: longer times
		# validate but can never preview (presentation ends at TIMELINE_LEN).
		page.add_child(_motion_row("Anchor time", _motion_spin(layer_id, str(domain), "anchor_time", 0.0, TIMELINE_LEN, 0.05, float(track.get("anchor_time", 0.0)), protected), on and not protected))
		page.add_child(_motion_row("Delay", _motion_spin(layer_id, str(domain), "delay", 0.0, 10.0, 0.05, float(track.get("delay", 0.0)), protected), on and not protected))
		page.add_child(_motion_row("Attack", _motion_spin(layer_id, str(domain), "attack", 0.001, 5.0, 0.01, float(track.get("attack", 0.1)), protected), on and not protected))
		page.add_child(_motion_row("Hold", _motion_spin(layer_id, str(domain), "hold", 0.0, 10.0, 0.05, float(track.get("hold", 0.0)), protected), on and not protected))
		page.add_child(_motion_row("Release", _motion_spin(layer_id, str(domain), "release", 0.001, 5.0, 0.01, float(track.get("release", 0.25)), protected), on and not protected))
		page.add_child(_motion_row("Sustain", _motion_spin(layer_id, str(domain), "sustain", 0.0, 1.0, 0.05, float(track.get("sustain", 0.0)), protected), on and not protected))
		page.add_child(_motion_row("Attack curve", _motion_curve_option(layer_id, str(domain), "attack_curve", str(track.get("attack_curve", "cubic_out")), curves, protected), on and not protected))
		page.add_child(_motion_row("Release curve", _motion_curve_option(layer_id, str(domain), "release_curve", str(track.get("release_curve", "sine_in_out")), curves, protected), on and not protected))
		if str(track.get("anchor", "manual")) not in anchors and str(track.get("anchor", "manual")) != "":
			var custom := Label.new()
			custom.text = "Anchor '%s' is not part of the event authority — the envelope never fires and production rejects it. Pick manual, fixed, or a known event." % str(track.get("anchor", ""))
			custom.add_theme_font_size_override("font_size", UiTokens.T_HELP)
			custom.add_theme_color_override("font_color", UiTokens.DISABLED)
			custom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			page.add_child(custom)

# UI-03 quality helpers: one labeled row each; rows dim when the domain is OFF.
func _motion_row(label_text: String, control: Control, active: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label_text
	lab.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	lab.custom_minimum_size.x = 110
	if not active:
		lab.add_theme_color_override("font_color", UiTokens.DISABLED)
	row.add_child(lab)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if control is SpinBox:
		(control as SpinBox).editable = (control as SpinBox).editable and active
	elif control is OptionButton:
		(control as OptionButton).disabled = (control as OptionButton).disabled or not active
	elif control is LineEdit:
		(control as LineEdit).editable = (control as LineEdit).editable and active
	row.add_child(control)
	return row

func _motion_spin(layer_id: String, domain: String, key: String, min_value: float, max_value: float, step: float, value: float, protected: bool) -> SpinBox:
	var spin := SpinBox.new()
	var tx_key := "motion:%s:%s:%s" % [layer_id, domain, key]
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = clampf(value, min_value, max_value)
	spin.custom_minimum_size.x = 76
	spin.editable = not protected
	spin.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if (event as InputEventMouseButton).pressed:
				_begin_ui_transaction(tx_key)
			else:
				_end_ui_transaction(tx_key)
	)
	spin.focus_entered.connect(func() -> void: _begin_ui_transaction(tx_key))
	spin.focus_exited.connect(func() -> void: _end_ui_transaction(tx_key))
	spin.value_changed.connect(func(new_value: float) -> void:
		_begin_ui_transaction(tx_key)
		_edit_layer(layer_id, func(doc):
			_motion_track(doc, layer_id, domain)[key] = new_value
		, false, true)
	)
	return spin

func _motion_curve_option(layer_id: String, domain: String, key: String, current: String, curves: Array, protected: bool) -> OptionButton:
	var copt := OptionButton.new()
	for item in curves:
		copt.add_item(str(item))
	copt.selected = maxi(0, curves.find(current))
	copt.disabled = protected
	copt.item_selected.connect(func(selected: int) -> void: _edit_layer(layer_id, func(doc):
		_motion_track(doc, layer_id, domain)[key] = str(curves[selected])
	, false))
	return copt

func _motion_anchor_option(layer_id: String, domain: String, current: String, anchors: Array, protected: bool) -> OptionButton:
	var copt := OptionButton.new()
	var items: Array = anchors.duplicate()
	if current not in items:
		items.append(current)
	for item in items:
		copt.add_item(str(item))
	copt.selected = maxi(0, items.find(current))
	copt.disabled = protected
	copt.tooltip_text = "manual = live TRIGGER; fixed = anchor_time; known events fire at mark + offset; unknown names never fire"
	copt.item_selected.connect(func(selected: int) -> void: _edit_layer(layer_id, func(doc):
		_motion_track(doc, layer_id, domain)["anchor"] = str(items[selected])
	, true))
	return copt

# UI-03: ensure the domain track dict exists before writing (sparse docs).
func _motion_track(doc: Dictionary, layer_id: String, domain: String) -> Dictionary:
	var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
	if not ((l["motion"] as Dictionary).get("tracks", {}) is Dictionary):
		(l["motion"] as Dictionary)["tracks"] = {}
	var tracks: Dictionary = (l["motion"] as Dictionary)["tracks"]
	if not (tracks.get(domain, {}) is Dictionary):
		tracks[domain] = {"anchor": "manual", "anchor_time": 0.0, "delay": 0.0, "attack": 0.1, "hold": 0.0, "release": 0.25, "sustain": 0.0, "attack_curve": "cubic_out", "release_curve": "sine_in_out"}
	return tracks[domain]

func _build_advanced_page(tab_pages: Dictionary, layer: Dictionary, layer_id: String, type: String, protected: bool) -> void:
	# SOURCE is intentionally artist-simple. FX creative expert fields and
	# developer diagnostics/raw values have separate explicit planes.
	if type == "SOURCE":
		return
	var expert_page: VBoxContainer = _tab_page(tab_pages, "ADVANCED")
	var diagnostics_page: VBoxContainer = _tab_page(tab_pages, "DIAGNOSTICS")
	if expert_page == null or diagnostics_page == null:
		return
	var debug_header := Label.new()
	debug_header.text = "DIAGNOSTICS · DEBUG VIEW (preview only)"
	debug_header.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	debug_header.add_theme_color_override("font_color", UiTokens.ACCENT)
	diagnostics_page.add_child(debug_header)
	diagnostics_page.add_child(_inspector_option("View", ["COMPOSITE", "BASE", "EFFECT", "EDGE", "COVERAGE", "MASK", "DRIVER"], debug_view, false, func(value: String) -> void:
		debug_view = value
		if renderer != null:
			renderer.set_debug_view(value)
		_update_debug_badge()
	))
	var raw_header := Label.new()
	raw_header.text = "RAW FIELDS"
	raw_header.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	raw_header.add_theme_color_override("font_color", UiTokens.ACCENT)
	diagnostics_page.add_child(raw_header)
	for pair in [["layer_id", str(layer.get("layer_id", ""))], ["type", type], ["input", str(layer.get("input", ""))], ["plane", str(layer.get("plane", ""))], ["blend_mode", str(layer.get("blend_mode", ""))], ["enabled", str(layer.get("enabled", true))], ["locked", str(layer.get("locked", false))]]:
		var raw := Label.new()
		raw.text = "%s: %s" % [str(pair[0]), str(pair[1])]
		raw.add_theme_font_size_override("font_size", UiTokens.T_HELP)
		raw.add_theme_color_override("font_color", UiTokens.DISABLED)
		raw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		diagnostics_page.add_child(raw)
	if type == "FX":
		_build_expert_fx(expert_page, layer, layer_id, protected)

# UI-01 (slice) / UI-05: expert direct canonical controls, fully driven by
# field metadata (no parallel ranges/enums here). Groups mirror macro domains
# plus FIELD/DRIVER catalogues; palette colors live on PALETTE while final
# composite color remains authorable in ADVANCED; assets have dedicated rows;
# Recipe macro controls are instance-owned. A recipe_id-only projection is
# intentionally not enough: repeated instances must never share an edit path.
func _recipe_instance_for_layer(layer_id: String) -> Dictionary:
	if session == null:
		return {}
	var documents: Array = []
	if session.look is Dictionary:
		documents.append(session.look)
	if session.composition is Dictionary:
		documents.append(session.composition)
	for raw_document in documents:
		var document: Dictionary = raw_document
		var metadata: Dictionary = document.get("metadata", {}) if document.get("metadata", {}) is Dictionary else {}
		var raw_instances: Variant = metadata.get("recipe_instances", [])
		if not (raw_instances is Array):
			continue
		for raw_instance in raw_instances:
			if not (raw_instance is Dictionary):
				continue
			var instance: Dictionary = raw_instance
			var layer_ids: Array = instance.get("layer_ids", []) if instance.get("layer_ids", []) is Array else []
			var pass_ids: Array = instance.get("pass_ids", []) if instance.get("pass_ids", []) is Array else []
			if layer_id in layer_ids or layer_id in pass_ids:
				return instance
	return {}

func _build_recipe_macros(page: VBoxContainer, layer: Dictionary, layer_id: String, protected: bool) -> void:
	if session == null:
		return
	var instance := _recipe_instance_for_layer(layer_id)
	var recipe_id := str(instance.get("recipe_id", ""))
	var recipe_instance_id := str(instance.get("recipe_instance_id", ""))
	if recipe_id == "" or recipe_instance_id == "" or not FxRecipesScript.has_recipe(recipe_id):
		return
	var recipe := FxRecipesScript.get_recipe(recipe_id)
	var macros: Array = recipe.get("macros", [])
	if macros.is_empty():
		return
	var authority_doc: Dictionary = session.composition if session.current_key == "composition" else session.look
	page.add_child(_fx_group_header("RECIPE MACROS · INTENT CONTROLS"))
	var note := Label.new()
	note.text = "Artist intent controls · maps to the same canonical fields shown below in Advanced"
	note.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	note.add_theme_color_override("font_color", FxLabUiTokensScript.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)
	for raw_macro in macros:
		var macro: Dictionary = raw_macro
		var macro_id := str(macro.get("id", ""))
		var mapping: Dictionary = macro.get("mapping", {})
		var macro_state: Dictionary = FxRecipesScript.macro_state(authority_doc, recipe_id, recipe_instance_id, macro_id)
		var source := "value"
		for raw_rule in mapping.values():
			if raw_rule is Dictionary and str((raw_rule as Dictionary).get("source", "value")) != "value":
				source = str((raw_rule as Dictionary).get("source", "value"))
				break
		if source in ["anchor", "clock", "option", "mode"]:
			var option := OptionButton.new()
			var items: Array = _recipe_macro_options(recipe_id, macro_id, source)
			for item in items:
				option.add_item(str(item))
			var current := str(macro_state.get("token", items[0] if not items.is_empty() else ""))
			option.selected = maxi(0, items.find(current))
			option.custom_minimum_size.x = 116.0
			option.disabled = protected
			option.tooltip_text = "Intent macro → canonical fields: " + ", ".join((macro.get("fields", []) as Array).map(func(path): return str(path)))
			option.item_selected.connect(func(index: int) -> void:
				_edit_recipe_macro(recipe_id, recipe_instance_id, macro_id, items[index], layer_id, false)
			)
			page.add_child(_macro_row(str(macro.get("label", macro_id)), option))
		else:
			var spin := SpinBox.new()
			spin.min_value = 0.0
			spin.max_value = 1.0
			spin.step = 0.01
			spin.value = float(macro_state.get("value", 0.0))
			spin.custom_minimum_size.x = 88.0
			spin.editable = not protected
			spin.tooltip_text = "Intent macro → canonical fields: " + ", ".join((macro.get("fields", []) as Array).map(func(path): return str(path)))
			if bool(macro_state.get("mixed", false)):
				spin.tooltip_text += " · MIXED canonical targets"
			spin.value_changed.connect(func(value: float) -> void:
				_edit_recipe_macro(recipe_id, recipe_instance_id, macro_id, value, layer_id, true)
			)
			_wire_spin_transaction(spin, "recipe:%s:macro:%s" % [recipe_instance_id, macro_id])
			page.add_child(_macro_row(str(macro.get("label", macro_id)), spin))

func _macro_row(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 112.0
	label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	label.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(control)
	return row

func _recipe_macro_options(recipe_id: String, macro_id: String, source: String) -> Array:
	return FxRecipesScript.macro_options(recipe_id, macro_id, source)

func _recipe_macro_current_token(layer: Dictionary, macro: Dictionary, items: Array) -> String:
	var mapping: Dictionary = macro.get("mapping", {})
	for raw_path in mapping.keys():
		var path := str(raw_path)
		var rule: Dictionary = mapping[raw_path] if mapping[raw_path] is Dictionary else {}
		var source := str(rule.get("source", "value"))
		if source == "anchor":
			return str((layer.get("fx", {}) as Dictionary).get("operator_anchor", items[0]))
		if source == "clock":
			return str((layer.get("fx", {}) as Dictionary).get("operator_time_source", items[0]))
		if source == "mode":
			var mode := int((layer.get("fx", {}) as Dictionary).get("operator_mix_mode", 0))
			return str(items[clampi(mode, 0, items.size() - 1)])
		if source == "option":
			var option := int((layer.get("fx", {}) as Dictionary).get(path.get_slice(".", path.get_slice_count(".") - 1), 0))
			return str(items[clampi(option, 0, items.size() - 1)])
	return str(items[0])

func _recipe_macro_current_normalized(layer: Dictionary, macro: Dictionary) -> float:
	var mapping: Dictionary = macro.get("mapping", {})
	for raw_path in mapping.keys():
		var path := str(raw_path)
		var rule: Dictionary = mapping[raw_path] if mapping[raw_path] is Dictionary else {}
		if str(rule.get("source", "value")) != "value":
			continue
		var leaf := path.get_slice(".", path.get_slice_count(".") - 1)
		var raw_value = (layer.get("fx", {}) as Dictionary).get(leaf, 0.0)
		var min_value := float(rule.get("min", FxLookScript.field_meta_all().get(leaf, {}).get("min", 0.0)))
		var max_value := float(rule.get("max", FxLookScript.field_meta_all().get(leaf, {}).get("max", 1.0)))
		return inverse_lerp(min_value, max_value, float(raw_value)) if not is_equal_approx(min_value, max_value) else 0.0
	return 0.0

func _edit_recipe_macro(recipe_id: String, recipe_instance_id: String, macro_id: String, value, layer_id: String, continuous := false) -> void:
	if recipe_instance_id == "" or not _session_ready():
		return
	var transaction_key := "recipe:%s:macro:%s" % [recipe_instance_id, macro_id]
	if session.current_key == "composition":
		if not continuous:
			_begin_ui_transaction(transaction_key)
		var result: Dictionary = session.edit_recipe_macro(recipe_id, recipe_instance_id, macro_id, value)
		if bool(result.get("ok", false)) and bool(result.get("changed", false)):
			_schedule_stash()
			_render_current_look()
			_refresh_inspector_cost()
			_refresh_layers_cost_surfaces()
			if status_badge != null:
				status_badge.text = session.badge_text()
		else:
			action_status.text = "✗ " + str(result.get("errors", ["Macro mutation rejected"]))
		if not continuous:
			_end_ui_transaction(transaction_key)
		_rebuild_layers_panel()
		_rebuild_inspector()
		_refresh_library()
		return
	_edit_layer(layer_id, func(doc): return FxRecipesScript.apply_macro_result(doc, recipe_id, recipe_instance_id, macro_id, value), false, true, transaction_key)
	if not continuous:
		_end_ui_transaction(transaction_key)

func _build_expert_fx(page: VBoxContainer, layer: Dictionary, layer_id: String, protected: bool) -> void:
	var fx: Dictionary = layer.get("fx", {})
	var meta_all: Dictionary = FxLookScript.field_meta_all()
	var header := Label.new()
	header.text = "EXPERT · DIRECT CANONICAL FX FIELDS"
	header.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	header.add_theme_color_override("font_color", UiTokens.ACCENT)
	page.add_child(header)
	var groups := [
		["SIGNAL", ["signal_gain", "color_blur", "signal_softness", "signal_posterize", "pattern_scale", "pure_continuous", "intensity", "size"]],
		["GRADE DETAIL", ["grade_black_point", "grade_white_point", "base_opacity"]],
		["WIND", ["wind_cutoff", "wind_displace"]],
		["MONO", ["mono_mode", "mono_bayer_level", "mono_pixel", "mono_space"]],
		["DITHER DETAIL", ["dither_black_point", "dither_white_point", "dither_gamma", "dither_contrast", "dither_brightness", "dither_mode", "dither_bayer_level", "dither_space"]],
		["FRINGE DETAIL", ["fringe_coverage_mode", "fringe_coverage_threshold", "fringe_bayer_level", "fringe_pixel", "fringe_space", "fringe_coverage_gain", "fringe_bleed", "fringe_blend_mode", "geometry_units"]],
		["RGB DETAIL", ["rgb_gradient", "rgb_gradient_balance", "rgb_gradient_contrast", "rgb_shift_units"]],
		["EFFECT MASK", ["effect_mask_enabled", "effect_mask_invert", "effect_mask_threshold", "effect_mask_softness", "effect_mask_base", "treatment_mask_path"]],
		["DRIVER", ["driver_mode", "driver_sampling_mode", "driver_pixel_size"]],
		["FIELD", ["FIELD_STRENGTH", "FIELD_SPEED", "OUTWARDNESS", "FIELD_BREAKUP", "COORD_NUDGE", "FIELD_SIZE", "FIELD_CENTER_X", "FIELD_CENTER_Y", "LEGACY_SCALE", "LEGACY_SPEED", "LEGACY_RADIAL", "DRIVER_CENTER_X", "DRIVER_CENTER_Y", "DRIVER_SCALE", "DRIVER_STRETCH", "DRIVER_ANGLE", "DRIVER_SPEED", "DRIVER_DETAIL", "DRIVER_FLOW"]],
		["FLOW DETAIL", ["flow_center_x", "flow_center_y"]],
		["TIME", ["temporal_hold", "time_source"]],
		["EDGE SOURCE", ["edge_source_mode", "edge_alpha_weight", "edge_luma_weight", "edge_threshold"]],
		["PIXEL GRIDS", ["source_pixel_size", "source_pixel_units"]],
		["PALETTE DETAIL", ["palette_strategy", "palette_lock_a", "palette_lock_b", "palette_swap", "palette_hue_offset", "palette_saturation", "palette_value"]],
		["FINAL COMPOSITE", ["final_tint_amount", "final_tint_color"]],
		["GOLD OPERATORS", ["operator", "operator_secondary", "operator_scope", "operator_strength", "operator_scale", "operator_speed", "operator_threshold", "operator_softness", "operator_mix", "operator_mix_mode", "operator_center_x", "operator_center_y", "operator_progress", "operator_progress_start", "operator_progress_end", "operator_polarity", "operator_axis_x", "operator_axis_y", "operator_pattern_mode", "operator_pattern_family", "operator_distortion", "operator_time_source", "operator_event_start", "operator_duration", "operator_color_a", "operator_color_b"]],
	]
	var pending_checks: Array = []
	for group in groups:
		page.add_child(_fx_group_header(str(group[0])))
		pending_checks.clear()
		for key in (group[1] as Array):
			var spec: Dictionary = meta_all.get(str(key), {})
			var kind := str(spec.get("kind", "amount"))
			if kind == "check":
				pending_checks.append(str(key))
				if pending_checks.size() == 3:
					page.add_child(_expert_check_row(pending_checks, fx, layer_id, protected))
					pending_checks.clear()
				continue
			if kind == "option":
				page.add_child(_expert_option_row(str(key), spec, fx, layer_id, protected))
			elif kind == "amount" or kind == "int":
				page.add_child(_expert_spin_row(str(key), spec, fx, layer_id, protected))
			elif kind == "color":
				page.add_child(_expert_color_row(str(key), spec, fx, layer_id, protected))
			elif kind == "asset":
				var dep_row := _dep_asset_row(str(key), str(key), layer, layer_id, protected, func(text: String) -> void:
					_edit_layer(layer_id, func(doc):
						var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
						(l["fx"] as Dictionary)[str(key)] = text.strip_edges() if text.strip_edges() != "" else null
					, false)
				)
				page.add_child(dep_row)
				_dep_note({"ADVANCED": page}, "ADVANCED", str(key), layer)
		if not pending_checks.is_empty():
			page.add_child(_expert_check_row(pending_checks, fx, layer_id, protected))
			pending_checks.clear()
	var skipped: Array = []
	for key in meta_all.keys():
		var kind := str((meta_all[key] as Dictionary).get("kind", ""))
		if kind == "color":
			continue # colors are authored on PALETTE (see pointer below)
		if kind == "compat" or kind == "rejected":
			skipped.append(str(key))
	var note := Label.new()
	note.text = "A/B + source colors live on PALETTE. Not controlled here: " + ", ".join(skipped) + "."
	note.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	note.add_theme_color_override("font_color", UiTokens.DISABLED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)

func _expert_spin_row(key: String, spec: Dictionary, fx: Dictionary, layer_id: String, protected: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.set_meta("canonical_field", key)
	var lab := Label.new()
	lab.text = key
	lab.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	lab.custom_minimum_size.x = 150
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(lab)
	var spin := SpinBox.new()
	spin.min_value = float(spec.get("min", 0.0))
	spin.max_value = float(spec.get("max", 4.0))
	spin.step = float(spec.get("step", 0.05))
	spin.value = clampf(float(fx.get(key, 0.0)), spin.min_value, spin.max_value)
	spin.custom_minimum_size.x = 100
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.editable = not protected
	spin.value_changed.connect(func(value: float) -> void: _edit_layer(layer_id, func(doc):
		var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
		(l["fx"] as Dictionary)[key] = value
	, false, true, "layer:%s:expert:%s" % [layer_id, key]))
	_wire_spin_transaction(spin, "layer:%s:expert:%s" % [layer_id, key])
	row.add_child(spin)
	return row

func _expert_color_row(key: String, _spec: Dictionary, fx: Dictionary, layer_id: String, protected: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.set_meta("canonical_field", key)
	var lab := Label.new()
	lab.text = key
	lab.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	lab.custom_minimum_size.x = 150
	row.add_child(lab)
	var picker := ColorPickerButton.new()
	var value: Array = fx.get(key, [1.0, 1.0, 1.0, 1.0])
	if value.size() < 3:
		value = [1.0, 1.0, 1.0, 1.0]
	picker.color = Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if value.size() > 3 else 1.0)
	picker.disabled = protected
	picker.custom_minimum_size = Vector2(96, 22)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.color_changed.connect(func(color: Color) -> void: _edit_layer(layer_id, func(doc):
		var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
		(l["fx"] as Dictionary)[key] = [color.r, color.g, color.b, color.a]
	, false, true))
	row.add_child(picker)
	return row

func _expert_check_row(keys: Array, fx: Dictionary, layer_id: String, protected: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	for key in keys:
		var check := CheckBox.new()
		check.set_meta("canonical_field", str(key))
		check.text = str(key)
		check.tooltip_text = str(key)
		check.button_pressed = bool(fx.get(str(key), false))
		check.disabled = protected
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.toggled.connect(func(pressed: bool) -> void: _edit_layer(layer_id, func(doc):
			var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
			(l["fx"] as Dictionary)[str(key)] = pressed
		, false))
		row.add_child(check)
	return row

func _expert_option_row(key: String, spec: Dictionary, fx: Dictionary, layer_id: String, protected: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.set_meta("canonical_field", key)
	var lab := Label.new()
	lab.text = key
	lab.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	lab.custom_minimum_size.x = 150
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(lab)
	var options: Array = spec.get("options", [])
	var current = fx.get(key, 0.0)
	var selected := 0
	if current is String:
		selected = maxi(0, options.find(str(current)))
	else:
		selected = clampi(int(float(current)), 0, maxi(0, options.size() - 1))
	var copt := OptionButton.new()
	for item in options:
		copt.add_item(str(item))
	copt.selected = selected
	copt.disabled = protected
	copt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copt.item_selected.connect(func(which: int) -> void: _edit_layer(layer_id, func(doc):
		var l: Dictionary = FxLookScript.find_layer(doc, layer_id)
		if (fx.get(key, 0.0)) is String:
			(l["fx"] as Dictionary)[key] = str(options[which])
		else:
			(l["fx"] as Dictionary)[key] = float(which)
	, false))
	row.add_child(copt)
	return row

# UI-04: badge + re-application keep the debug view truthful across
# rebuilds, target switches and remounts (new quads inherit COMPOSITE).
func _update_debug_badge() -> void:
	if debug_badge == null:
		return
	if debug_view == "COMPOSITE":
		debug_badge.visible = false
		debug_badge.text = ""
	else:
		debug_badge.visible = true
		debug_badge.text = "DEBUG: " + debug_view

func _inspector_option(label_text: String, options: Array, current: String, disabled: bool, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	label.custom_minimum_size.x = 70
	row.add_child(label)
	var option := OptionButton.new()
	for item in options:
		option.add_item(display_token(str(item)))
	var index := options.find(current)
	option.selected = maxi(0, index)
	option.disabled = disabled
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(func(selected: int) -> void:
		on_change.call(str(options[selected]))
	)
	row.add_child(option)
	return row

# ================================================================ frame

func _apply_lab_ui_contract() -> void:
	if lab_theme == null:
		lab_theme = FxLabUiTokensScript.make_theme()
		theme = lab_theme
	_apply_lab_ui_node_contract(self)

func _apply_lab_ui_node_contract(node: Node) -> void:
	if node is Control:
		(node as Control).theme = lab_theme
	if node is Button or node is OptionButton or node is MenuButton:
		FxLabUiTokensScript.apply_hit_target(node as Control)
	if node is PopupMenu:
		_register_lab_popup(node as PopupMenu)
	if node is OptionButton or node is MenuButton:
		var popup: PopupMenu
		if node is OptionButton:
			popup = (node as OptionButton).get_popup()
		else:
			popup = (node as MenuButton).get_popup()
		_register_lab_popup(popup)
	for child in node.get_children():
		_apply_lab_ui_node_contract(child)

func _register_lab_popup(popup: PopupMenu) -> void:
	if popup == null or not is_instance_valid(popup):
		return
	popup.theme = lab_theme
	if not popup.has_meta("fx_lab_popup_contract"):
		popup.set_meta("fx_lab_popup_contract", true)
		popup.about_to_popup.connect(func() -> void: _bound_lab_popup(popup))
	if popup not in _popup_contracts:
		_popup_contracts.append(popup)

func _bound_lab_popup(popup: PopupMenu) -> void:
	if popup == null or not is_instance_valid(popup):
		return
	FxLabUiTokensScript.bound_popup(popup, get_viewport_rect().size)

func _process(_delta: float) -> void:
	if not _native_pointer_acquired:
		_acquire_native_pointer()
	for popup in _popup_contracts:
		if is_instance_valid(popup) and popup.visible:
			_bound_lab_popup(popup)
	if runtime == null or viewport_host == null or disp == null:
		return
	if dock_host != null and dock != null and dock_host.size.x > 0.0:
		dock.position = Vector2.ZERO
		dock.size = dock_host.size
	var available := viewport_host.size
	if available.x > 10.0 and available.y > 10.0:
		var scale_factor := minf(available.x / 1280.0, available.y / 720.0)
		var zoom := 1.0
		if study_mode != "OFF":
			zoom = float(study_mode.trim_suffix("%")) / 100.0
		disp.scale = Vector2(scale_factor * zoom, scale_factor * zoom)
		if study_mode != "OFF" and selected_key != "" and runtime.registry.slot_nodes.has(selected_key):
			# Study zoom centers on the selected target; authored geometry is
			# untouched (presentation-space rects live in the data, not the view).
			var node = runtime.registry.slot_nodes[selected_key]
			var rect: Rect2 = FxTargetsScript.presentation_rect(node)
			var center := rect.get_center()
			disp.position = available * 0.5 - center * disp.scale
		else:
			disp.position = (available - Vector2(1280, 720) * disp.scale) * 0.5
	_update_selection_outline()
	_update_play_button()
	# Scrubbing sets the authoring clock explicitly; during PLAY the mounted
	# screen advances it. Keep the final-composite renderer on that same clock,
	# otherwise the scene moves while its FX remain frozen at the last seek.
	if runtime.screen != null and not runtime.screen.lab_preview_is_paused():
		_authoring_playhead = clampf(runtime.elapsed(), 0.0, TIMELINE_LEN)
		if renderer != null:
			renderer.set_time(_authoring_playhead)
	var authoring_t: float = _authoring_playhead
	if not time_syncing:
		time_syncing = true
		time_spin.set_value_no_signal(authoring_t)
		time_syncing = false
	# The visible timeline and authoring renderer use the bounded explicit
	# playhead. The mounted screen owns its independent lifecycle elapsed clock.
	timeline_time_label.text = "T %.3f / %.3f" % [authoring_t, TIMELINE_LEN]
	if timeline_ruler.visible:
		timeline_ruler.queue_redraw()
	if renderer != null:
		# PRESENTATION_TIME changes only through explicit authoring transport;
		# FREE_RUN remains wall-clock-driven even while presentation is paused.
		renderer.set_free_run(Time.get_ticks_msec() / 1000.0)
	if _stash_pending and session != null and session.dirty:
		var now := Time.get_ticks_msec() / 1000.0
		if now >= _stash_at:
			# DR-07: a failed debounced stash stays pending for retry and is
			# surfaced — it must never be silently dropped.
			var stash_result: Dictionary = session.stash()
			if bool(stash_result.get("ok", false)):
				_stash_pending = false
			else:
				_stash_at = now + 2.0
				action_status.text = "✗ Draft stash failed — retrying: " + str(stash_result.get("errors", []))
			if status_badge != null and _session_ready():
				status_badge.text = session.badge_text()
	var transaction_now := Time.get_ticks_msec() / 1000.0
	for transaction_key in _ui_transactions.keys().duplicate():
		if transaction_now - float(_ui_transactions[transaction_key]) >= 0.25:
			_ui_transactions.erase(transaction_key)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	var key := event as InputEventKey
	if _modal_active():
		accept_event()
		return
	if key.ctrl_pressed and key.keycode == KEY_S:
		_action_save_draft()
		accept_event()
	elif key.ctrl_pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
		_action_apply()
		accept_event()
	# Ctrl+Shift+Z must win over the plain Ctrl+Z branch; otherwise the
	# modifier is silently ignored and the user's redo gesture undoes again.
	elif key.ctrl_pressed and (key.keycode == KEY_Y or (key.keycode == KEY_Z and key.shift_pressed)):
		_action_redo()
		accept_event()
	elif key.ctrl_pressed and key.keycode == KEY_Z:
		_action_undo()
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and session != null and session.dirty:
		var close_stash: Dictionary = session.stash()
		if not bool(close_stash.get("ok", false)) and action_status != null:
			action_status.text = "✗ Draft stash failed on close: " + str(close_stash.get("errors", []))

func _compute_event_marks() -> Dictionary:
	# P0: the shell owns NO timing table — the ScreenRuntime is the single
	# event authority for lab preview and reference/game runtime alike.
	return runtime.event_marks() if runtime != null else {}

# (P0: shell timing helpers retired; FxScreenRuntime.event_marks is the
# single authority. This space intentionally left blank.)
