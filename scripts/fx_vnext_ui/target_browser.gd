extends VBoxContainer
# NRCU FX Lab vNext — Context & Target Browser (specs/01 §1–§4).
# Left dock: matchup summary, search, target tree, status badges.
# Selection and navigation only — no effect controls live here.

signal target_selected(key: String)
signal remount_requested(format: String, stage: String, left: String, right: String)

const UiTokens := preload("res://scripts/ui_tokens.gd")

var runtime # FxScreenRuntime
var status_provider: Callable = Callable()

var summary_button: Button
var matchup_body: VBoxContainer
var mode_option: OptionButton
var stage_option: OptionButton
var left_option: OptionButton
var right_option: OptionButton
var search_edit: LineEdit
var tree: Tree
var row_keys: Dictionary = {}
var fighter_ids: Array = []
var _search_text := ""

const FORMAT_NAMES := ["1v1", "FFA_3", "FFA_4", "TEAM_2V2", "TEAM_2V1", "TEAM_3V1"]
const STAGE_IDS := ["debug", "toy_room", "sky"]

func setup(runtime_ref, provider: Callable = Callable()) -> void:
	runtime = runtime_ref
	status_provider = provider
	_scan_fighters()
	_build()
	rebuild()

func _scan_fighters() -> void:
	fighter_ids.clear()
	var d := DirAccess.open("res://assets/vs/fighters")
	if d != null:
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			if d.current_is_dir() and not name.begins_with(".") and not name.ends_with(".import"):
				fighter_ids.append(name)
			name = d.get_next()
		d.list_dir_end()
	fighter_ids.sort()

# ---------------------------------------------------------------- build

func _build() -> void:
	add_theme_constant_override("separation", 6)

	summary_button = Button.new()
	summary_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	summary_button.add_theme_font_size_override("font_size", UiTokens.T_META)
	summary_button.pressed.connect(_toggle_matchup)
	UiTokens.apply_styles(summary_button, {
		"normal": UiTokens.flat(UiTokens.SURFACE_1, UiTokens.RULE, UiTokens.STROKE),
		"hover": UiTokens.flat(UiTokens.SURFACE_2, UiTokens.RULE_WARM, UiTokens.STROKE),
		"pressed": UiTokens.flat(UiTokens.SURFACE_2, UiTokens.ACCENT, UiTokens.STROKE),
		"focus": UiTokens.flat(UiTokens.SURFACE_2, UiTokens.ACCENT, UiTokens.STROKE),
	})
	add_child(summary_button)

	matchup_body = VBoxContainer.new()
	matchup_body.visible = false
	matchup_body.add_theme_constant_override("separation", 4)
	add_child(matchup_body)
	mode_option = _make_option("Mode", FORMAT_NAMES)
	stage_option = _make_option("Stage", STAGE_IDS)
	left_option = _make_option("Left fighter", fighter_ids, "Left")
	right_option = _make_option("Right fighter", fighter_ids, "Right")
	var remount := _make_button("⟲ REMOUNT CONTEXT", _on_remount)
	matchup_body.add_child(remount)

	var onboarding := Label.new()
	onboarding.name = "OnboardingHint"
	onboarding.text = "1. Select a target · 2. Build or edit its layers · 3. Apply to Target when satisfied"
	onboarding.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	onboarding.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	onboarding.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	add_child(onboarding)
	var search_label := Label.new()
	search_label.text = "SEARCH"
	search_label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	search_label.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	add_child(search_label)

	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Target, fighter or role…"
	search_edit.add_theme_font_size_override("font_size", UiTokens.T_META)
	search_edit.text_changed.connect(func(text: String) -> void:
		_search_text = text.strip_edges().to_lower()
		rebuild()
	)
	add_child(search_edit)

	tree = Tree.new()
	tree.hide_root = true
	tree.columns = 2
	tree.set_column_expand(0, true)
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 104)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	tree.item_selected.connect(_on_tree_selected)
	add_child(tree)

func _make_option(label_text: String, items: Array, side := "") -> OptionButton:
	var row := HBoxContainer.new()
	matchup_body.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 86
	label.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	label.add_theme_color_override("font_color", UiTokens.CREAM_DIM)
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override("font_size", UiTokens.T_META)
	for item in items:
		var identity := _display_name(str(item))
		if side != "":
			identity += " · " + side
		option.add_item(identity)
		option.get_popup().set_item_tooltip(option.item_count - 1, _full_identity(str(item), side))
	option.tooltip_text = "%s identity: %s" % [side if side != "" else label_text, _full_identity(str(items[0]) if not items.is_empty() else "", side)]
	row.add_child(option)
	return option

func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", UiTokens.T_HELP)
	button.pressed.connect(callback)
	return button

func _toggle_matchup() -> void:
	matchup_body.visible = not matchup_body.visible
	_refresh_summary()

func _on_remount() -> void:
	var format: String = str(FORMAT_NAMES[clampi(mode_option.selected, 0, FORMAT_NAMES.size() - 1)])
	var stage: String = str(STAGE_IDS[clampi(stage_option.selected, 0, STAGE_IDS.size() - 1)])
	var left := str(fighter_ids[clampi(left_option.selected, 0, fighter_ids.size() - 1)]) if not fighter_ids.is_empty() else ""
	var right := str(fighter_ids[clampi(right_option.selected, 0, fighter_ids.size() - 1)]) if not fighter_ids.is_empty() else ""
	remount_requested.emit(format, stage, left, right)

# ---------------------------------------------------------------- rebuild

func refresh_context() -> void:
	_sync_options()
	_refresh_summary()

func _sync_options() -> void:
	if runtime == null:
		return
	var format_index := FORMAT_NAMES.find(runtime.mode_format)
	if format_index >= 0:
		mode_option.select(format_index)
	var stage_index := STAGE_IDS.find(runtime.stage_id)
	if stage_index >= 0:
		stage_option.select(stage_index)
	var left_index := fighter_ids.find(runtime.pick_l)
	if left_index >= 0:
		left_option.select(left_index)
	var right_index := fighter_ids.find(runtime.pick_r)
	if right_index >= 0:
		right_option.select(right_index)

func _refresh_summary() -> void:
	if runtime == null:
		return
	summary_button.text = "▸ " + _matchup_summary()

func _matchup_summary() -> String:
	if runtime == null:
		return "NO CONTEXT"
	return "%s · %s vs %s · %s" % [
		str(runtime.mode_format),
		_display_name(str(runtime.pick_l)),
		_display_name(str(runtime.pick_r)),
		str(runtime.stage_id),
	]

func rebuild() -> void:
	if tree == null or runtime == null:
		return
	tree.clear()
	row_keys.clear()
	var root_item := tree.create_item()
	var registry = runtime.registry

	# ---- VS ---------------------------------------------------------------
	var mark_keys := _keys_with_role(registry, "VS MARK")
	var vs_shown := _add_group(root_item, "VS")
	for key in mark_keys:
		_add_target_row(vs_shown, key, "VS Mark")
	vs_shown.visible = not mark_keys.is_empty()

	# ---- FIGHTERS ----------------------------------------------------------
	var fighter_keys := []
	var composition_keys := []
	for key in registry.keys():
		var role := str(registry.slot_roles.get(key, ""))
		if role == "PRIMARIES" or role == "ECHOES" or role == "NAMES":
			fighter_keys.append(key)
		elif role in ["STAGE", "SIDE FIELDS", "NAME PLATES", "ACCENT LINES"]:
			composition_keys.append(key)

	var fighters_item := _add_group(root_item, "FIGHTERS")
	var by_fighter: Dictionary = {}
	for key in fighter_keys:
		var ctx: Dictionary = registry.context_for_target(str(key))
		var fighter := str(ctx.get("fighter_id", ""))
		if fighter == "":
			continue
		if not by_fighter.has(fighter):
			by_fighter[fighter] = []
		by_fighter[fighter].append({"key": key, "ctx": ctx})
	var fighter_shown := false
	var fighter_names: Array = by_fighter.keys()
	fighter_names.sort()
	for fighter in fighter_names:
		var entries: Array = by_fighter[fighter]
		var visible_entries := _filter_entries(entries, _display_name(fighter) + " " + fighter)
		if visible_entries.is_empty():
			continue
		fighter_shown = true
		var fighter_item := _add_group(fighters_item, _display_name(str(fighter)))
		for role_name in ["PRIMARY", "ECHO", "NAME"]:
			var role_entries := []
			for entry in visible_entries:
				if str(entry["ctx"].get("element_role", "")) == role_name.to_lower():
					role_entries.append(entry)
			_add_role_rows(fighter_item, role_name, role_entries)
	fighters_item.visible = fighter_shown

	# ---- COMPOSITION -------------------------------------------------------
	var comp_item := _add_group(root_item, "COMPOSITION")
	var comp_entries := []
	if runtime.registry.has_method("context_for_target"):
		comp_entries.append({"key": "composition", "ctx": runtime.registry.context_for_target("composition")})
	for key in composition_keys:
		comp_entries.append({"key": key, "ctx": registry.context_for_target(str(key))})
	comp_entries.sort_custom(func(a, b): return str(a["ctx"].get("element_id", a["key"])) < str(b["ctx"].get("element_id", b["key"])))
	_add_role_rows(comp_item, "", _filter_entries(comp_entries, "composition"))
	var comp_shown := comp_entries.size() > 0
	comp_item.visible = comp_shown

func _add_role_rows(parent_item: TreeItem, role_name: String, entries: Array) -> void:
	if entries.is_empty():
		return
	if entries.size() == 1:
		var entry: Dictionary = entries[0]
		_add_target_row(parent_item, str(entry["key"]), _role_label(role_name, entry))
		return
	var group := _add_group(parent_item, role_name.capitalize() if role_name != "" else "Elements")
	for entry in entries:
		_add_target_row(group, str(entry["key"]), _instance_label(entry))

func _role_label(role_name: String, entry: Dictionary) -> String:
	if role_name != "":
		return role_name.capitalize()
	return _composition_label(entry)

func _instance_label(entry: Dictionary) -> String:
	var ctx: Dictionary = entry["ctx"]
	var role_name := str(ctx.get("element_role", "")).capitalize()
	var slot := _slot_label(str(ctx.get("presentation_slot", "")))
	var side := str(ctx.get("visual_side", "")).capitalize()
	var suffix := slot if slot != "" else side
	if suffix == "":
		return role_name
	return "%s — %s" % [role_name, suffix]

func _composition_label(entry: Dictionary) -> String:
	var ctx: Dictionary = entry["ctx"]
	var element := str(ctx.get("element_id", entry["key"]))
	var role := str(ctx.get("element_role", ""))
	if role == "stage":
		return "Stage (%s)" % str(ctx.get("stage_id", ""))
	match role:
		"side_field":
			return "Side Field %s" % str(ctx.get("visual_side", "")).capitalize()
		"name_plate":
			return "Name Plate %s" % str(ctx.get("visual_side", "")).capitalize()
		"accent_line":
			return "Accent Line %s" % str(ctx.get("visual_side", "")).capitalize()
	return element.capitalize()

func _filter_entries(entries: Array, group_hint: String) -> Array:
	if _search_text == "":
		return entries
	var out := []
	for entry in entries:
		var ctx: Dictionary = entry["ctx"]
		var haystack := "%s %s %s %s %s" % [
			str(entry["key"]), str(ctx.get("fighter_id", "")), str(ctx.get("element_role", "")),
			str(ctx.get("element_id", "")), group_hint,
		]
		if _search_text in haystack.to_lower():
			out.append(entry)
	return out

func _keys_with_role(registry, role: String) -> Array:
	var out := []
	for key in registry.keys():
		if str(registry.slot_roles.get(key, "")) == role:
			out.append(key)
	return out

func _add_group(parent_item: TreeItem, label: String) -> TreeItem:
	var item := tree.create_item(parent_item)
	item.set_text(0, label)
	item.set_custom_color(0, UiTokens.ACCENT)
	item.set_selectable(0, false)
	item.set_selectable(1, false)
	return item

func _add_target_row(parent_item: TreeItem, key: String, label: String) -> TreeItem:
	var item := tree.create_item(parent_item)
	var ctx: Dictionary = runtime.registry.context_for_target(key) if runtime != null and runtime.registry != null else {}
	var identity_label := _identity_label(label, ctx)
	item.set_text(0, identity_label)
	item.set_text(1, _badge_for(key))
	item.set_custom_color(1, UiTokens.CREAM_DIM)
	item.set_metadata(0, key)
	item.set_tooltip_text(0, _full_identity(key, str(ctx.get("visual_side", "")), ctx))
	item.set_tooltip_text(1, "Assignment status for " + _full_identity(key, str(ctx.get("visual_side", "")), ctx))
	row_keys[item] = key
	return item

func _identity_label(label: String, ctx: Dictionary) -> String:
	var side := str(ctx.get("visual_side", "")).to_lower()
	if side == "left":
		return "L · " + label
	if side == "right":
		return "R · " + label
	return label

func _full_identity(key: String, side := "", ctx := {}) -> String:
	var identity: Dictionary = ctx
	if identity.is_empty() and runtime != null and runtime.registry != null:
		identity = runtime.registry.context_for_target(key)
	var actual_side := side if side != "" else str(identity.get("visual_side", ""))
	return "Target identity\nkey: %s\nfighter: %s\nrole: %s\nvisual side: %s\nelement: %s" % [
		key,
		str(identity.get("fighter_id", "")),
		str(identity.get("element_role", "")),
		actual_side,
		str(identity.get("element_id", "")),
	]

func _badge_for(key: String) -> String:
	if status_provider.is_valid():
		return str(status_provider.call(key))
	return "○ UNASSIGNED"

func _on_tree_selected() -> void:
	var item := tree.get_selected()
	if item == null:
		return
	var key := str(item.get_metadata(0))
	if key == "":
		return
	target_selected.emit(key)

# ---------------------------------------------------------------- helpers

func _display_name(id: String) -> String:
	var parts := id.split("_")
	var out: Array = []
	for part in parts:
		if part.length() > 0:
			out.append(part.substr(0, 1).to_upper() + part.substr(1))
	return " ".join(out)

func _slot_label(slot: String) -> String:
	if slot == "":
		return ""
	var parts := slot.split("_")
	var out: Array = []
	for part in parts:
		if part.length() > 0:
			out.append(part.substr(0, 1).to_upper() + part.substr(1))
	return " ".join(out)
