extends SceneTree
# Macro UI authority proof: a visible macro control routes through the owning
# recipe_instance_id, never through recipe_id fan-out across repeated instances.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")

var shell: Control
var failures := 0
var checks := 0

func _init() -> void:
	var test_root := "user://fx_macro_ui_%d" % Time.get_ticks_usec()
	OS.set_environment("NRCU_FX_DATA_DIR", test_root.path_join("production"))
	OS.set_environment("NRCU_FX_DRAFT_DIR", test_root.path_join("drafts"))
	_wipe_dir(ProjectSettings.globalize_path(OS.get_environment("NRCU_FX_DATA_DIR")))
	_wipe_dir(ProjectSettings.globalize_path(OS.get_environment("NRCU_FX_DRAFT_DIR")))
	shell = _spawn()
	await settle(30)
	shell.drafts.clear_target(shell.runtime.registry.signature_for_key("echo_left"))
	shell._select_key("echo_left", false)
	await settle(15)
	_check(shell._session_ready(), "macro UI opens the echo target")
	if not shell._session_ready():
		_finish()
		return
	var context: Dictionary = shell.runtime.registry.context_for_target("echo_left")
	var first: Dictionary = shell.session.add_recipe_instance(FxRecipesScript.SIGNAL_MELT, context)
	var second: Dictionary = shell.session.add_recipe_instance(FxRecipesScript.SIGNAL_MELT, context)
	_check(bool(first.get("ok", false)) and bool(second.get("ok", false)), "two repeated Signal Melt instances are authorable")
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		_finish()
		return
	var first_instance_id := str(first.get("recipe_instance_id", ""))
	var second_instance_id := str(second.get("recipe_instance_id", ""))
	var first_layer_id := str((first.get("layer_ids", []) as Array)[0])
	var second_layer_id := str((second.get("layer_ids", []) as Array)[0])
	var first_before: Dictionary = FxLookScript.find_layer(shell.session.look, first_layer_id).duplicate(true)
	var second_before: Dictionary = FxLookScript.find_layer(shell.session.look, second_layer_id).duplicate(true)
	shell.selected_layer_id = first_layer_id
	shell._rebuild_inspector()
	await settle(5)
	var melt := _spin_for("Melt")
	_check(melt != null, "Melt macro is visible for the selected recipe instance")
	if melt != null:
		shell.session._undo_stack.clear()
		shell.session._redo_stack.clear()
		_click_point(melt.get_global_rect().get_center(), true)
		melt.value = 0.91
		_click_point(melt.get_global_rect().get_center(), false)
		await settle(8)
	var first_after: Dictionary = FxLookScript.find_layer(shell.session.look, first_layer_id)
	var second_after: Dictionary = FxLookScript.find_layer(shell.session.look, second_layer_id)
	_check(float((first_after.get("fx", {}) as Dictionary).get("operator_strength", 0.0)) > 0.9, "selected instance receives the macro edit", str(first_after.get("fx", {}).get("operator_strength", "")))
	_check(second_after == second_before, "sibling recipe instance remains canonically unchanged")
	_check(shell.session._undo_stack.size() == 1, "continuous Macro pointer edit creates exactly one undo entry", "stack=%d" % shell.session._undo_stack.size())
	var after_edit: Dictionary = first_after.duplicate(true)
	_check(shell.session.undo(), "Macro pointer edit undoes")
	var first_undone: Dictionary = FxLookScript.find_layer(shell.session.look, first_layer_id)
	_check(first_undone == first_before, "Macro undo restores the canonical pre-edit instance")
	_check(shell.session.redo(), "Macro pointer edit redoes")
	_check(FxLookScript.find_layer(shell.session.look, first_layer_id) == after_edit, "Macro redo restores the canonical post-edit instance")
	_check(str((shell.session.look.get("metadata", {}) as Dictionary).get("recipe_instances", [])[0].get("recipe_instance_id", "")) == first_instance_id, "instance provenance remains durable")
	_check(second_instance_id != first_instance_id, "repeated instances have distinct identities")
	_finish()

func _finish() -> void:
	print("[FX-MACRO-UI-AUTHORITY] done · checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	if ok:
		print("[CHECK] PASS  ", label)
	else:
		failures += 1
		printerr("[CHECK] FAIL  ", label, "  ", detail)

func _spawn() -> Control:
	var scene: PackedScene = load("res://scenes/nrcu_fx_lab_vnext.tscn")
	var node: Control = scene.instantiate()
	root.add_child(node)
	return node

func settle(frames: int) -> void:
	for i in frames:
		await process_frame

func _click_point(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _spin_for(label_text: String) -> SpinBox:
	for child in _walk(shell.inspector_content):
		if child is HBoxContainer:
			var children: Array[Node] = (child as HBoxContainer).get_children()
			if children.size() >= 2 and children[0] is Label and (children[0] as Label).text == label_text:
				for sub in children:
					if sub is SpinBox:
						return sub
	return null

func _wipe_dir(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		DirAccess.make_dir_recursive_absolute(abs_path)
		return
	for file_name in DirAccess.get_files_at(abs_path):
		DirAccess.remove_absolute(abs_path.path_join(file_name))
	for sub in DirAccess.get_directories_at(abs_path):
		_wipe_dir(abs_path.path_join(sub))
		DirAccess.remove_absolute(abs_path.path_join(sub))
