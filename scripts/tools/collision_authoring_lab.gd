extends Control
## Isolated authoring preview. Never instantiates a fighter or gameplay world.
var generated: Resource
var working: Resource
var generated_path := ""
var last_error := ""
var body_wire: MeshInstance3D
var world: Node3D
var camera: Camera3D
var panel: VBoxContainer
var path_entry: LineEdit
var status: Label
var body_fields: Array[LineEdit] = []
var save_entry: LineEdit
var reset_dialog: ConfirmationDialog
var model: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var hurt_wires: Array[MeshInstance3D] = []
var hurt_selector: OptionButton
var bone_selector: OptionButton
var animation_selector: OptionButton
var profile_selector: OptionButton
var hurt_fields: Array[LineEdit] = []
var slider: HSlider
var detail: Label
var metadata: Label
var previous_content_scale := Vector2i.ZERO

func _update_authoring_scale() -> void:
	# Headless standalone runners may start with a tiny dummy window. Retain
	# the project canvas there; real supported windows use actual pixel layout.
	get_window().content_scale_size = previous_content_scale if get_window().size.x < 960 else Vector2i.ZERO

func _exit_tree() -> void:
	get_window().size_changed.disconnect(_update_authoring_scale)
	get_window().content_scale_size = previous_content_scale

func build_pose_controls() -> void:
	profile_selector = OptionButton.new(); profile_selector.name = "ProfileSelector"; panel.add_child(profile_selector)
	profile_selector.add_item("Discovered generated profiles")
	for path in discover_profiles("res://data/collision"):
		profile_selector.add_item(path.get_file()); profile_selector.set_item_metadata(profile_selector.item_count-1,path)
	profile_selector.item_selected.connect(func(i):
		if i > 0: open_profile(profile_selector.get_item_metadata(i)))
	var browse := Button.new(); browse.text = "Browse profile…"; panel.add_child(browse)
	var dialog := FileDialog.new(); dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; dialog.access = FileDialog.ACCESS_FILESYSTEM; dialog.filters = PackedStringArray(["*.tres ; Collision profile"]); add_child(dialog); dialog.file_selected.connect(open_profile)
	browse.pressed.connect(func(): dialog.popup_centered_ratio(0.8))
	animation_selector = OptionButton.new(); animation_selector.name = "AnimationSelector"; panel.add_child(animation_selector)
	slider = HSlider.new(); slider.step = 0.001; panel.add_child(slider)
	animation_selector.item_selected.connect(func(i):
		slider.max_value = animation_player.get_animation(animation_selector.get_item_text(i)).length
		slider.value = 0; scrub(animation_selector.get_item_text(i),0))
	slider.value_changed.connect(func(t):
		if animation_selector.selected >= 0: scrub(animation_selector.get_item_text(animation_selector.selected),t))
	hurt_selector = OptionButton.new(); panel.add_child(hurt_selector); hurt_selector.item_selected.connect(func(_i): sync_hurt_fields())
	bone_selector = OptionButton.new(); panel.add_child(bone_selector)
	hurt_fields = add_fields("Bone-local: radius / height / offset X / Y / Z",[0.1,0.2,0,0,0])
	var apply := Button.new(); apply.text = "Apply selected hurtbox"; panel.add_child(apply)
	apply.pressed.connect(func():
		if bone_selector.selected >= 0: edit_hurtbox(hurt_selector.selected,bone_selector.get_item_text(bone_selector.selected),hurt_fields[0].text,hurt_fields[1].text,hurt_fields[2].text,hurt_fields[3].text,hurt_fields[4].text))
	detail = Label.new(); detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; detail.custom_minimum_size.x = 360; detail.max_lines_visible = 3; panel.add_child(detail)
	var download := Button.new(); download.text = "Download override (.tres, Web)"; download.disabled = not OS.has_feature("web"); panel.add_child(download); download.pressed.connect(download_override)

func discover_profiles(directory: String) -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(directory)
	if not dir: return result
	for file in dir.get_files():
		# Exported resources are listed as .tres.remap; load their canonical
		# resource paths, not the remap sidecars. Never invent unresolved paths.
		var canonical := file.trim_suffix(".remap") if file.ends_with(".tres.remap") else file
		var path := directory.path_join(canonical)
		if canonical.ends_with(".tres") and not result.has(path) and ResourceLoader.exists(path):
			var resource = load(path)
			if resource and resource.get_script() == load("res://scripts/core/collision/character_collision_profile.gd") and not resource.manual_override: result.append(path)
	for subdir in dir.get_directories():
		if subdir != "overrides": result.append_array(discover_profiles(directory.path_join(subdir)))
	result.sort()
	return result

func load_model() -> void:
	if model: model.free()
	model = null; skeleton = null; animation_player = null
	animation_selector.clear(); bone_selector.clear(); hurt_selector.clear()
	slider.editable = false; animation_selector.disabled = true; hurt_selector.disabled = true; bone_selector.disabled = true
	detail.text = "Static model — body only; no skeleton/hurtboxes or animation scrubbing."
	if working.source_asset.is_empty() or not ResourceLoader.exists(working.source_asset):
		detail.text = "Source model unavailable; body only. No invented hurtbox placement."
		return
	var packed = load(working.source_asset)
	if not packed is PackedScene: detail.text = "Source is not a model scene"; return
	model = packed.instantiate(); world.add_child(model)
	model.scale = Vector3.ONE * working.visual_scale; model.position = -working.foot_origin
	var skeletons := model.find_children("*","Skeleton3D",true,false)
	if not skeletons.is_empty(): skeleton = skeletons[0]
	var players := model.find_children("*","AnimationPlayer",true,false)
	if not players.is_empty():
		animation_player = players[0]; animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		# Private nonlooping copies keep endpoint seeks exact without editing imported keys.
		for library_name in animation_player.get_animation_library_list():
			var library := animation_player.get_animation_library(library_name).duplicate(true)
			animation_player.remove_animation_library(library_name); animation_player.add_animation_library(library_name,library)
			for clip in library.get_animation_list(): library.get_animation(clip).loop_mode = Animation.LOOP_NONE
		for clip in animation_player.get_animation_list(): animation_selector.add_item(clip)
	if skeleton:
		for i in range(skeleton.get_bone_count()): bone_selector.add_item(skeleton.get_bone_name(i))
	for h in working.hurtboxes: hurt_selector.add_item(h.hurtbox_id)
	hurt_selector.disabled = hurt_selector.item_count == 0; bone_selector.disabled = bone_selector.item_count == 0
	sync_hurt_fields()
	if animation_selector.item_count:
		slider.editable = true; animation_selector.disabled = false
		slider.max_value = animation_player.get_animation(animation_selector.get_item_text(0)).length
		scrub(animation_selector.get_item_text(0),0)

func scrub(clip: String, seconds: float) -> bool:
	if not animation_player or not animation_player.has_animation(clip) or not is_finite(seconds): return fail("Missing animation or invalid time")
	animation_player.play(clip); animation_player.seek(clampf(seconds,0,animation_player.get_animation(clip).length),true); animation_player.advance(0)
	if skeleton: skeleton.force_update_all_bone_transforms()
	update_hurt_wires()
	return true

func sync_hurt_fields() -> void:
	if not working or hurt_selector.selected < 0 or hurt_selector.selected >= working.hurtboxes.size(): return
	var h = working.hurtboxes[hurt_selector.selected]
	var values := [h.radius,h.height,h.local_transform.origin.x,h.local_transform.origin.y,h.local_transform.origin.z]
	for i in range(hurt_fields.size()): hurt_fields[i].text = str(values[i])
	for i in range(bone_selector.item_count):
		if bone_selector.get_item_text(i) == h.bone_name: bone_selector.select(i)
	detail.text = "Confidence: " + h.confidence + "\n" + h.provenance + "\nOrange: bone-local units; model transform applied."

func edit_hurtbox(index: int, bone: String, radius: String, height: String, x: String, y: String, z: String) -> bool:
	if not working or index < 0 or index >= working.hurtboxes.size(): return fail("Select a hurtbox")
	if not skeleton or skeleton.find_bone(bone) < 0: return fail("Bone absent from source skeleton")
	if bone != generated.hurtboxes[index].bone_name: return fail("Shared overrides cannot rebind bones; edit dimensions/offsets on the generated bone")
	for text in [radius,height,x,y,z]:
		if not text.is_valid_float() or not is_finite(text.to_float()): return fail("Enter finite capsule values")
	var h = working.hurtboxes[index].duplicate(true)
	h.bone_name = bone; h.radius = radius.to_float(); h.height = height.to_float(); h.local_transform.origin = Vector3(x.to_float(),y.to_float(),z.to_float())
	if not h.validate().is_empty(): return fail(str(h.validate()))
	h.manual_override = true; working.hurtboxes[index] = h; mark_override([]); update_hurt_wires(); sync_hurt_fields()
	return true

func update_hurt_wires() -> void:
	for wire in hurt_wires: wire.free()
	hurt_wires.clear()
	if not skeleton: return
	for h in working.hurtboxes:
		var bone := skeleton.find_bone(h.bone_name)
		if bone < 0:
			detail.text = "WARNING: missing bone " + h.bone_name + "; volume not drawn"
			continue
		var wire := wire_capsule(h.radius,h.height,Color.ORANGE); world.add_child(wire)
		wire.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(bone) * h.local_transform
		hurt_wires.append(wire)
	fit_profile_camera()

func fit_profile_camera() -> void:
	# Camera only: conservative bound of actual profile geometry, never resize colliders.
	var extent: float = working.body_height * 0.9
	for wire in hurt_wires:
		var bounds := wire.mesh.get_aabb()
		for i in range(8):
			extent = maxf(extent,(wire.global_transform * bounds.get_endpoint(i)).distance_to(working.body_center))
	camera.size = extent * 2.4

func serialize_download() -> PackedByteArray:
	if not working or not working.validate().is_empty():
		fail("Open a valid profile before downloading")
		return PackedByteArray()
	var copy = working.duplicate(true); copy.manual_override = true; copy.provenance["authoring_generated_path"] = generated_path
	var path := "user://collision_authoring_download.tres"
	if not safe_save_path(path):
		fail("Unsafe temporary download path (alias or protected resource)")
		return PackedByteArray()
	if ResourceSaver.save(copy,path) != OK:
		fail("Temporary export failed")
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)

func download_override() -> bool:
	if not working or not OS.has_feature("web"): return fail("Download is Web-only; native uses separate override save")
	var bytes := serialize_download()
	if bytes.is_empty(): return false
	JavaScriptBridge.download_buffer(bytes,"collision_override.tres","text/plain")
	status.text = "Download requested; browser cannot write the local repository."
	return true

func add_fields(label: String, values: Array) -> Array[LineEdit]:
	var title := Label.new(); title.text = label; panel.add_child(title)
	var row := HBoxContainer.new(); panel.add_child(row)
	var fields: Array[LineEdit] = []
	for value in values:
		var field := LineEdit.new(); field.text = str(value); field.custom_minimum_size.x = 60; field.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(field); fields.append(field)
	return fields

func build_edit_controls() -> void:
	body_fields = add_fields("Body: radius / total height / center X / Y / Z", [0.3,2,0,1,0])
	var apply := Button.new(); apply.text = "Apply body"; panel.add_child(apply)
	apply.pressed.connect(func(): edit_body(body_fields[0].text,body_fields[1].text,body_fields[2].text,body_fields[3].text,body_fields[4].text))
	save_entry = LineEdit.new(); save_entry.text = "user://collision_authoring_override.tres"; panel.add_child(save_entry)
	var save := Button.new(); save.name = "SaveOverride"; save.text = "Save separate override"; panel.add_child(save); save.pressed.connect(func(): save_override(save_entry.text))
	var reload_button := Button.new(); reload_button.text = "Reload override"; panel.add_child(reload_button); reload_button.pressed.connect(func(): reload_override(save_entry.text))
	reset_dialog = ConfirmationDialog.new(); reset_dialog.dialog_text = "Discard unsaved edits and return to generated?\nNo file is deleted or overwritten."; add_child(reset_dialog); reset_dialog.confirmed.connect(func(): reset_to_generated(true))
	var reset := Button.new(); reset.text = "RESET to generated…"; panel.add_child(reset); reset.pressed.connect(func(): reset_dialog.popup_centered())

func edit_body(radius: String, height: String, x: String, y: String, z: String) -> bool:
	if working == null: return fail("Open a profile first")
	for text in [radius,height,x,y,z]:
		if not text.is_valid_float() or not is_finite(text.to_float()): return fail("Enter finite numbers; dimensions must be positive")
	var candidate = working.duplicate(true)
	candidate.body_radius = radius.to_float(); candidate.body_height = height.to_float(); candidate.body_center = Vector3(x.to_float(),y.to_float(),z.to_float())
	if not candidate.validate().is_empty(): return fail(str(candidate.validate()))
	working = candidate; mark_override(["body_radius","body_height","body_center"]); refresh_preview()
	status.text = "Body updated in preview; generated source unchanged."
	return true

func mark_override(fields: Array) -> void:
	working.manual_override = true
	for field in fields:
		if not working.override_fields.has(field): working.override_fields.append(field)

func safe_save_path(path: String) -> bool:
	if path.contains("..") or path.contains("\\") or not path.ends_with(".tres"): return false
	if not (path.begins_with("user://") or path.begins_with("res://data/collision/overrides/")): return false
	# Reject aliases at every existing ancestor, including the allowlisted root
	# and leaf itself. Never follow a local symlink before ResourceSaver writes.
	var absolute := ProjectSettings.globalize_path(path)
	if absolute != absolute.simplify_path(): return false
	var cursor := absolute
	while cursor != cursor.get_base_dir():
		var parent := DirAccess.open(cursor.get_base_dir())
		if parent and parent.is_link(cursor): return false
		cursor = cursor.get_base_dir()
	if FileAccess.file_exists(path):
		var existing = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not existing or existing.get_script() != working.get_script() or not existing.manual_override: return false
	return ProjectSettings.globalize_path(path).simplify_path() != ProjectSettings.globalize_path(generated_path).simplify_path()

func save_override(path: String) -> bool:
	if working == null: return fail("Open a profile first")
	if not safe_save_path(path): return fail("Save only a separate .tres under user:// or res://data/collision/overrides/; no traversal")
	if not working.validate().is_empty(): return fail(str(working.validate()))
	if OS.has_feature("web"): return fail("Web cannot write your repository. Use Download override.")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var copy = working.duplicate(true); copy.manual_override = true
	copy.provenance["authoring_generated_path"] = generated_path
	var result := ResourceSaver.save(copy, path)
	if result != OK: return fail("Save failed: " + error_string(result))
	status.text = "Saved separate override: " + path
	return true

func reload_override(path: String) -> bool:
	if working == null or not ResourceLoader.exists(path): return fail("Open generated profile, then an existing override")
	var resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null or resource.get_script() != generated.get_script(): return fail("Not a collision override")
	if not resource.manual_override or resource.character_id != generated.character_id or not resource.validate().is_empty(): return fail("Invalid or mismatched override")
	var merged: Dictionary = generated.merged_with(resource)
	if not merged.errors.is_empty(): return fail(str(merged.errors))
	working = merged.profile.duplicate(true); working.override_fields = resource.override_fields.duplicate()
	refresh_preview(); sync_fields(); status.text = "Reloaded override; generated source untouched."
	return true

func reset_to_generated(confirmed: bool) -> bool:
	if not confirmed or generated == null: return false
	working = generated.duplicate(true); refresh_preview(); sync_fields(); status.text = "Reset preview to generated. No files changed."
	return true

func sync_fields() -> void:
	sync_hurt_fields()
	var values := [working.body_radius,working.body_height,working.body_center.x,working.body_center.y,working.body_center.z]
	for i in range(body_fields.size()): body_fields[i].text = str(values[i])

func return_to_combat() -> void:
	get_tree().change_scene_to_file("res://scenes/combat_lab.tscn")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.physical_keycode != KEY_ESCAPE: return
	if get_viewport().gui_get_focus_owner() is LineEdit: return
	for child in get_children():
		if child is Window and child.visible: return
	get_viewport().set_input_as_handled()
	return_to_combat()

func _ready() -> void:
	previous_content_scale = get_window().content_scale_size
	_update_authoring_scale()
	get_window().size_changed.connect(_update_authoring_scale)
	theme = Theme.new(); theme.default_font_size = 13
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout := HBoxContainer.new(); layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(layout)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size.x = 380; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; layout.add_child(scroll)
	panel = VBoxContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(panel)
	var back := Button.new(); back.name = "ReturnCombat"; back.text = "Return combat lab [Esc] — RESET match"; back.focus_mode = Control.FOCUS_NONE; panel.add_child(back); back.pressed.connect(return_to_combat)
	back.tooltip_text = "Fresh default fighters, rules and bindings. Unsaved editor changes are discarded."
	var title := Label.new(); title.text = "COLLISION AUTHORING\nGenerated draft — NOT balance approval"; panel.add_child(title)
	path_entry = LineEdit.new(); path_entry.name = "ProfilePath"; path_entry.placeholder_text = "res://data/collision/...tres"; panel.add_child(path_entry)
	var open := Button.new(); open.text = "Open profile path"; open.pressed.connect(func(): open_profile(path_entry.text)); panel.add_child(open)
	build_pose_controls()
	build_edit_controls()
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status.custom_minimum_size.x = 325; panel.add_child(status)
	metadata = Label.new(); metadata.name = "ProfileMetadata"; metadata.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; metadata.custom_minimum_size.x = 360; panel.add_child(metadata)
	var container := SubViewportContainer.new(); container.stretch = true; container.size_flags_horizontal = Control.SIZE_EXPAND_FILL; container.size_flags_vertical = Control.SIZE_EXPAND_FILL; layout.add_child(container)
	var viewport := SubViewport.new(); viewport.size = Vector2i(850,720); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; container.add_child(viewport)
	world = Node3D.new(); viewport.add_child(world)
	camera = Camera3D.new(); world.add_child(camera); camera.position = Vector3(3,2,5); camera.look_at(Vector3(0,1,0)); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 3.5
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-35,-30,0); world.add_child(light)
	var paths := discover_profiles("res://data/collision")
	var startup := "" if paths.is_empty() else paths[0]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile="): startup = argument.trim_prefix("--profile=")
	if not startup.is_empty(): open_profile(startup)

func open_profile(path: String) -> bool:
	if not ResourceLoader.exists(path): return fail("Profile not found: " + path)
	var resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null or resource.get_script() != load("res://scripts/core/collision/character_collision_profile.gd"): return fail("Not a character collision profile")
	if resource.manual_override: return fail("Open generated baseline first, then use Reload override")
	if not resource.validate().is_empty(): return fail(str(resource.validate()))
	generated = resource; generated_path = path; working = generated.duplicate(true)
	path_entry.text = path
	load_model(); sync_fields()
	refresh_preview()
	status.text = "Body: cyan | hurtboxes: orange\nIsolated preview only, no gameplay claims"
	metadata.text = "Generated warnings:\n" + "\n".join(working.warnings) + "\nProvenance: " + str(working.provenance) + "\nSource: " + working.source_asset + "\nSHA256: " + working.source_sha256
	return true

func fail(message: String) -> bool:
	last_error = message
	if status: status.text = "ERROR: " + message
	return false

func refresh_preview() -> void:
	update_hurt_wires()
	if body_wire: body_wire.free()
	body_wire = wire_capsule(working.body_radius, working.body_height, Color.CYAN)
	world.add_child(body_wire); body_wire.position = working.body_center
	fit_profile_camera()
	camera.position = working.body_center + Vector3(3,1,5); camera.look_at(working.body_center)

func wire_capsule(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = color; material.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var half := height * 0.5 - radius
	for i in range(48):
		var a := TAU*i/48.0; var b := TAU*(i+1)/48.0
		for y in [-half,half]:
			mesh.surface_add_vertex(Vector3(cos(a)*radius,y,sin(a)*radius)); mesh.surface_add_vertex(Vector3(cos(b)*radius,y,sin(b)*radius))
		for axis in [0,1]:
			var va := Vector3(cos(a)*radius, sin(a)*radius + (half if sin(a)>=0 else -half),0)
			var vb := Vector3(cos(b)*radius, sin(b)*radius + (half if sin(b)>=0 else -half),0)
			if axis: va = Vector3(0,va.y,va.x); vb = Vector3(0,vb.y,vb.x)
			mesh.surface_add_vertex(va); mesh.surface_add_vertex(vb)
	mesh.surface_end()
	var node := MeshInstance3D.new(); node.mesh = mesh; node.set_meta("radius",radius); node.set_meta("height",height)
	return node
