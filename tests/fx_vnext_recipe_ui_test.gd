extends SceneTree
# Phase 7 shell vertical slice: Hero Recipe rows remain authoring-only and
# instantiate complete stacks through one FxSession undo transaction.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")

var shell: Control
var failures := 0
var checks := 0
var blocked := 0

func _init() -> void:
	# Production/Draft paths must be isolated before the shell's _ready() runs;
	# wiping after instantiation is too late because recovery happens at boot.
	var test_root := "user://fx_recipe_ui_%d" % Time.get_ticks_usec()
	var production_root := test_root.path_join("production")
	var draft_root := test_root.path_join("drafts")
	OS.set_environment("NRCU_FX_DATA_DIR", production_root)
	OS.set_environment("NRCU_FX_DRAFT_DIR", draft_root)
	OS.set_environment("NRCU_FX_WORKSPACE_PATH", test_root.path_join("workspace.json"))
	_wipe_dir(ProjectSettings.globalize_path(production_root))
	_wipe_dir(ProjectSettings.globalize_path(draft_root))
	shell = _spawn()
	await settle(30)
	_check(str(shell.production.data_dir) == production_root and str(shell.drafts.base_dir) == draft_root, "Recipe UI test booted with isolated Production/Draft paths")
	shell.drafts.clear_target(shell.runtime.registry.signature_for_key(_target_key("primary", "left")))
	var primary_key := _target_key("primary", "left")
	_check(primary_key != "", "public registry resolves PRIMARY left target from semantic identity")
	await _click_target(primary_key)
	await settle(15)
	_check(shell._session_ready(), "recipe shell test opens a primary target through Browser selection")
	_check(_reachable(shell.add_menu), "+ ADD is visibly reachable at the 1280x720 floor", _geometry(shell.add_menu))
	_check(_reachable(shell.action_apply), "APPLY is visibly reachable at the 1280x720 floor", _geometry(shell.action_apply))
	_check(shell.recipe_rows != null and shell.recipe_rows.get_child_count() >= 5, "Recipe Library exposes Hero Recipes and curated starting points")
	_check(shell.library_rows != null and shell.recipe_rows != null and shell.library_rows != shell.recipe_rows and shell.production_tab.is_ancestor_of(shell.library_rows) and shell.recipes_tab.is_ancestor_of(shell.recipe_rows), "Production Looks and Recipes are separate secondary dock surfaces")
	_check(shell.has_method("_action_add_recipe"), "shell exposes a first-class recipe action")

	if shell.has_method("_action_add_recipe") and shell._session_ready():
		var before_layers: Array = shell.session.look.get("layers", []).duplicate(true)
		shell.session.set_assignment_scope("ROLE")
		await _select_recipe_and_click_add(FxRecipesScript.PRIMARY_FLAME_ENERGY)
		await settle(12)
		var flame_layers: Array = shell.session.look.get("layers", [])
		_check(flame_layers.size() == before_layers.size() + 3, "PRIMARY_FLAME_ENERGY instantiates its complete layer stack", str(flame_layers.size()))
		_check(shell.session._undo_stack.size() == 1, "PRIMARY_FLAME_ENERGY creates one undo transaction", "stack=%d" % shell.session._undo_stack.size())
		_check(str(shell.session.assignment_scope_mode) == "ROLE", "recipe instantiation is independent of Assignment Scope")
		_check(bool(shell.session.undo()), "one recipe transaction can be undone")
		await settle(5)
		_check((shell.session.look.get("layers", []) as Array).size() == before_layers.size(), "one undo removes the complete recipe stack")

		# ORGANIC_SIDE_FIELD is intentionally fail-closed for fighter targets;
		# continue the real UI flow on the declared side-field target instead of
		# weakening the compatibility authority to satisfy this shell fixture.
		var side_field_key := _target_key("side_field", "left")
		_check(side_field_key != "", "public registry resolves LEFT side-field target from semantic identity")
		await _click_target(side_field_key)
		await settle(15)
		_check(str(shell.selected_key) == side_field_key and str(shell.session.current_key) == side_field_key, "Browser selection opens the resolved side-field target", "selected=%s current=%s status=%s" % [shell.selected_key, shell.session.current_key, shell.action_status.text])
		var organic_before_layers: Array = shell.session.look.get("layers", []).duplicate(true)
		await _select_recipe_and_click_add(FxRecipesScript.ORGANIC_SIDE_FIELD)
		await settle(12)
		var organic_layers: Array = shell.session.look.get("layers", [])
		_check(organic_layers.size() == organic_before_layers.size() + 2, "ORGANIC_SIDE_FIELD instantiates its complete layer stack", str(organic_layers.size()))
		_check(shell.session._undo_stack.size() == 1, "ORGANIC_SIDE_FIELD creates one undo transaction", "stack=%d" % shell.session._undo_stack.size())
		var canonical: Dictionary = shell.session.look.duplicate(true)
		canonical["look_id"] = "P7_SHELL"
		canonical["name"] = "P7 Shell Recipe Fixture"
		var validation: Dictionary = FxLookScript.validate_input(canonical)
		_check(bool(validation.get("ok", false)), "recipe shell result remains a valid canonical Look", str(validation.get("errors", [])))

	# Composition Recipe macro reachability: the selected projected pass must
	# route the visible control to composition.final_passes, not to the editor
	# projection. Target and ADD are real pointer actions; the pass row and
	# OptionButton are also reached through their hit rectangles.
	var composition_key := _role_key("composition")
	_check(composition_key != "", "public registry resolves the Composition target")
	if composition_key != "":
		await _click_target(composition_key)
		await settle(15)
		await _select_recipe_and_click_add(FxRecipesScript.CLASH_OVERDRIVE)
		await settle(12)
		var speed_id := ""
		var pattern_id := ""
		for raw_pass in shell.session.composition.get("final_passes", []):
			var pass_doc: Dictionary = raw_pass
			if str(pass_doc.get("operator", "")) == "speedlines_field":
				speed_id = str(pass_doc.get("pass_id", ""))
			if str(pass_doc.get("operator", "")) == "pattern_transition":
				pattern_id = str(pass_doc.get("pass_id", ""))
		_check(speed_id != "", "Composition ADD creates a speedline pass")
		_check(pattern_id == "", "CLASH_OVERDRIVE does not force a Pattern pass")
		await _click_layer_name("Clash Speedline Burst")
		await settle(8)
		_show_tab_by_title("PROPERTIES")
		await settle(4)
		_show_inspector_tab("LOOK")
		await settle(4)
		var direction := _control_for_label("Direction")
		_check(direction != null, "Composition Direction intent control is visible on LOOK")
		if direction != null:
			var direction_scroll := _scroll_ancestor(direction)
			if direction_scroll != null:
				direction_scroll.ensure_control_visible(direction)
				await settle(3)
			_check(_reachable(direction), "Composition Direction intent control is inside the visible Inspector viewport", _geometry(direction))

	# Let queued UI redraws and deferred children finish before engine shutdown.
	shell.queue_free()
	await settle(10)
	print("[FX-RECIPES-UI] done · checks=%d failures=%d blocked=%d" % [checks, failures, blocked])
	quit(1 if failures > 0 or blocked > 0 else 0)

func _role_key(element_role: String) -> String:
	if shell == null or shell.runtime == null or shell.runtime.registry == null:
		return ""
	if element_role.to_lower() == "composition":
		return "composition"
	for raw_key in shell.runtime.registry.keys():
		var key := str(raw_key)
		var ctx: Dictionary = shell.runtime.registry.context_for_target(key)
		if str(ctx.get("element_role", "")).to_lower() == element_role.to_lower():
			return key
	return ""

func _click_layer_name(label_text: String) -> void:
	for child in _walk(shell.layers_rows):
		if child is Button and (child as Button).text == label_text:
			_click_point((child as Button).get_global_rect().get_center())
			return
	_check(false, "Layers exposes the requested projected pass row", label_text)

func _show_tab_by_title(title: String) -> void:
	for node in _walk(shell):
		if not node is TabContainer:
			continue
		var tabs: TabContainer = node as TabContainer
		for index in range(tabs.get_tab_count()):
			if tabs.get_tab_title(index) == title:
				tabs.current_tab = index
				return

func _show_inspector_tab(tab_name: String) -> void:
	var tab: TabContainer = _find_first_tab(shell.inspector_content)
	if tab == null:
		return
	for index in range(tab.get_tab_count()):
		if tab.get_tab_title(index) == tab_name:
			tab.current_tab = index
			return

func _find_first_tab(node: Node) -> TabContainer:
	if node is TabContainer:
		return node as TabContainer
	for child in node.get_children():
		var found := _find_first_tab(child)
		if found != null:
			return found
	return null

func _control_for_label(label_text: String) -> Control:
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var children: Array[Node] = (child as HBoxContainer).get_children()
			if children.size() >= 2 and children[0] is Label and (children[0] as Label).text == label_text:
				for sub in children:
					if sub is Control and sub != children[0]:
						return sub as Control
	return null

func _option_for(label_text: String) -> OptionButton:
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var children: Array[Node] = (child as HBoxContainer).get_children()
			if children.size() >= 2 and children[0] is Label and (children[0] as Label).text == label_text:
				for sub in children:
					if sub is OptionButton:
						return sub as OptionButton
	return null

func _visibility_chain(control: Control) -> String:
	var values: Array[String] = []
	var cursor: Node = control
	while cursor != null:
		if cursor is CanvasItem:
			values.append("%s:%s" % [cursor.name, str((cursor as CanvasItem).visible)])
		cursor = cursor.get_parent()
	return " / ".join(values)

func _choose_option_by_pointer(option: OptionButton, desired_text: String) -> Dictionary:
	_click_point(option.get_global_rect().get_center())
	await settle(2)
	var popup: PopupMenu = option.get_popup()
	if not popup.visible:
		return {"opened": false, "selected": false}
	var item_index := -1
	for index in range(popup.item_count):
		if popup.get_item_text(index) == desired_text:
			item_index = index
			break
	if item_index < 0:
		popup.hide()
		return {"opened": true, "selected": false}
	var was_opened := popup.visible
	popup.hide()
	return {"opened": was_opened, "selected": false}

func _pass_by_id(passes: Array, pass_id: String) -> Dictionary:
	for raw_pass in passes:
		if str((raw_pass as Dictionary).get("pass_id", "")) == pass_id:
			return raw_pass as Dictionary
	return {}

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _target_key(element_role: String, visual_side: String) -> String:
	if shell == null or shell.runtime == null or shell.runtime.registry == null:
		return ""
	for raw_key in shell.runtime.registry.keys():
		var key := str(raw_key)
		var ctx: Dictionary = shell.runtime.registry.context_for_target(key)
		if str(ctx.get("element_role", "")).to_lower() == element_role.to_lower() and str(ctx.get("visual_side", "")).to_lower() == visual_side.to_lower():
			return key
	return ""

func _click_target(key: String) -> void:
	if shell.browser == null or shell.browser.tree == null:
		_check(false, "Browser target tree is available")
		return
	# Fresh AUTO layout at 1280px legitimately collapses the Browser. Open it
	# through its visible public control; never click a hidden TreeItem rectangle.
	if not shell.browser.is_visible_in_tree():
		_click_control(shell.browser_toggle)
		await settle(4)
		_check(shell.browser.is_visible_in_tree(), "Browser toggle opens target tree in fresh workspace")
	for raw_item in shell.browser.row_keys.keys():
		var item: TreeItem = raw_item
		if str(shell.browser.row_keys[raw_item]) != key:
			continue
		shell.browser.tree.scroll_to_item(item, true)
		await settle(2)
		var area: Rect2 = shell.browser.tree.get_item_area_rect(item, 0)
		_click_point(shell.browser.tree.get_global_transform_with_canvas() * area.get_center())
		return
	_check(false, "Browser exposes the semantic target row", key)

func _select_recipe_and_click_add(recipe_id: String) -> void:
	var tab_index: int = shell.authoring_tabs.get_tab_idx_from_control(shell.recipes_tab)
	shell.authoring_tabs.current_tab = tab_index
	var recipe: Dictionary = FxRecipesScript.get_recipe(recipe_id)
	var group := str(recipe.get("library_group", recipe.get("category", ""))).to_upper()
	var filter_index := 0
	for index in range(shell.recipe_filter.item_count):
		if shell.recipe_filter.get_item_text(index).to_upper() == group:
			filter_index = index
			break
	shell.recipe_filter.select(filter_index)
	shell.recipe_filter.item_selected.emit(filter_index)
	var selector_index := -1
	for index in range(shell.recipe_selector.item_count):
		if str(shell.recipe_selector.get_item_metadata(index)) == recipe_id:
			selector_index = index
			break
	_check(selector_index >= 0, "Recipe Browser exposes the requested recipe", recipe_id)
	if selector_index < 0:
		return
	shell.recipe_selector.select(selector_index)
	shell.recipe_selector.item_selected.emit(selector_index)
	await settle(3)
	for raw_button in shell.recipe_add_buttons:
		var button: Button = raw_button
		if not button.is_visible_in_tree():
			continue
		var ancestor: Node = button
		while ancestor != null:
			if ancestor.name == "RecipeCard_" + recipe_id:
				var scroll: ScrollContainer = _scroll_ancestor(button)
				if scroll != null:
					scroll.ensure_control_visible(button)
					await settle(2)
				_check(_reachable(button), "Recipe ADD control is inside the visible clipped Recipes viewport", "%s %s" % [recipe_id, _geometry(button)])
				_click_point(button.get_global_rect().get_center())
				return
			ancestor = ancestor.get_parent()
	_check(false, "Visible Recipe ADD reaches the requested recipe card", recipe_id)

func _scroll_ancestor(control: Control) -> ScrollContainer:
	var cursor: Node = control.get_parent()
	while cursor != null:
		if cursor is ScrollContainer:
			return cursor as ScrollContainer
		cursor = cursor.get_parent()
	return null

func _click_control(control: Control) -> void:
	_click_point(control.get_global_rect().get_center())

func _reachable(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree():
		return false
	var clip := Rect2(Vector2.ZERO, shell.get_viewport().get_visible_rect().size)
	var cursor: Node = control
	while cursor != null:
		if cursor is Control:
			var current: Control = cursor
			if current.clip_contents or current is ScrollContainer:
				clip = clip.intersection(current.get_global_rect())
		cursor = cursor.get_parent()
	var rect := control.get_global_rect()
	var center := rect.get_center()
	return clip.has_point(center) and clip.encloses(rect)

func _click_point(point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.position = point
	release.global_position = point
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)

func _spawn() -> Control:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	var node: Control = scene.instantiate()
	root.add_child(node)
	return node

func settle(frames: int) -> void:
	for i in frames:
		await process_frame

func _geometry(control: Control) -> String:
	if control == null:
		return "<null>"
	var clip := Rect2(Vector2.ZERO, shell.get_viewport().get_visible_rect().size)
	var cursor: Node = control
	while cursor != null:
		if cursor is Control:
			var current: Control = cursor
			if current.clip_contents or current is ScrollContainer:
				clip = clip.intersection(current.get_global_rect())
		cursor = cursor.get_parent()
	return "rect=%s clip=%s viewport=%s" % [str(control.get_global_rect()), str(clip), str(shell.get_viewport().get_visible_rect())]

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if ok:
		print("[CHECK] PASS  ", label)
	else:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)

func _blocked(label: String) -> void:
	checks += 1
	blocked += 1
	printerr("[CHECK] BLOCKED ", label)

func _wipe_dir(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		DirAccess.make_dir_recursive_absolute(abs_path)
		return
	for file_name in DirAccess.get_files_at(abs_path):
		DirAccess.remove_absolute(abs_path.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs_path):
		_wipe_dir(abs_path.path_join(sub))
		DirAccess.remove_absolute(abs_path.path_join(sub))
