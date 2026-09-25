class_name FxScreenRuntime
extends RefCounted
# NRCU FX Lab vNext — screen runtime (Stream B/C foundation).
#
# Owns the canonical VS screen instance inside a SubViewport, installs the
# lab-side vector proxies for static composition targets (side fields, name
# plates, accent lines — duel + multiplayer families) and keeps the FxTargets
# registry in sync. Transport access is a thin passthrough to the screen's
# lab preview API.
#
# Behavior ported from the certified v0.3 lab (_mount_screen,
# _install_vector_proxies, _load_project_texture) — the v0.3 lab remains the
# reference implementation; this module is the vNext replacement.

const SCREEN_SCENE := "res://scenes/vs_screen.tscn"
const VSRequest := preload("res://scripts/vs_presentation_request.gd")
const FxSideShapesScript := preload("res://scripts/fx_vnext/fx_side_shapes.gd")

var subvp: SubViewport
var screen: Node
var registry # FxTargets instance (loaded by path so headless runs do not depend on class cache)
var mode_format := "1v1"
var stage_id := "debug"
var pick_l := "ice_mage"
var pick_r := "doge_man"
var extras: Array = ["ggb", "teknium"]

var last_mount_ok := false
var last_mount_label := ""

func _init(create_viewport := true) -> void:
	# Game binding adopts a started screen without a second viewport/lifetime.
	if create_viewport:
		subvp = SubViewport.new()
		subvp.size = Vector2i(1280, 720)
		subvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		subvp.transparent_bg = false
	registry = load("res://scripts/fx_vnext/fx_targets.gd").new()

# ---------------------------------------------------------------- mounting

func mount(format := "", stage := "", left := "", right := "") -> bool:
	if format != "":
		mode_format = format
	if stage != "":
		stage_id = stage
	if left != "":
		pick_l = left
	if right != "":
		pick_r = right
	if screen != null and is_instance_valid(screen):
		screen.free()
	screen = load(SCREEN_SCENE).instantiate()
	# Preview-owned lifetime: lab/reference seeks past minimum_exposure must
	# freeze on the EXIT frame, never self-teardown the composition (the game
	# path leaves this meta unset and keeps legacy teardown).
	screen.set_meta("fx_preview_no_teardown", true)
	subvp.add_child(screen)
	var ok := false
	if mode_format == "1v1":
		ok = bool(screen.start(pick_l, pick_r, stage_id))
	else:
		var plan: Dictionary = VSRequest.plan(_records_for(mode_format), stage_id, mode_format.begins_with("TEAM"))
		ok = bool(screen.start_presentation(plan))
		if not ok:
			mode_format = "1v1"
			ok = bool(screen.start(pick_l, pick_r, stage_id))
	install_vector_proxies()
	registry.bind_screen(screen, mode_format, stage_id)
	last_mount_ok = ok
	last_mount_label = ("live" if ok else "fallback") + " · " + mode_format + " · " + stage_id
	return ok

func free_screen() -> void:
	if screen != null and is_instance_valid(screen):
		screen.free()
	screen = null
	registry.bind_screen(null, mode_format, stage_id)

# ---------------------------------------------------------------- transport passthrough

func seek(t: float) -> void:
	if screen != null and is_instance_valid(screen) and screen.has_method("lab_preview_seek"):
		screen.lab_preview_seek(t)

func elapsed() -> float:
	if screen != null and is_instance_valid(screen) and screen.has_method("elapsed"):
		return float(screen.elapsed())
	return 0.0

# ---------------------------------------------------------------- vector proxies

func shape_data_dir() -> String:
	var override := OS.get_environment("NRCU_FX_DATA_DIR")
	if override != "":
		return override
	return "res://nrcu_fx_data"

func install_vector_proxies() -> void:
	if screen == null or not is_instance_valid(screen):
		return
	# Duel/static vector geometry. Each proxy uses a canonical 1280×720 alpha
	# mask so the shared FX shader can expand beyond the original polygon/line.
	# Round-2 architecture addition: side-field geometry is a SHAPE/MASK PRESET
	# (default: the current hourglass silhouette), resolved per side - never a
	# hard-coded silhouette in the render path.
	var side_shapes: Dictionary = FxSideShapesScript.resolve_all(shape_data_dir())
	var static_specs := [
		["Root/SideFields/FieldLeft", str((side_shapes["left"] as Dictionary).get("mask", "")), "SIDE FIELDS", "side_field_left"],
		["Root/SideFields/FieldRight", str((side_shapes["right"] as Dictionary).get("mask", "")), "SIDE FIELDS", "side_field_right"],
		["Root/NamePlates/PlateLeft", "res://assets/vs/generated/name_plate_left_mask.png", "NAME PLATES", "name_plate_left"],
		["Root/NamePlates/PlateRight", "res://assets/vs/generated/name_plate_right_mask.png", "NAME PLATES", "name_plate_right"],
		["Root/NamePlates/AccentLeft", "res://assets/vs/generated/accent_left_mask.png", "ACCENT LINES", "accent_line_left"],
		["Root/NamePlates/AccentRight", "res://assets/vs/generated/accent_right_mask.png", "ACCENT LINES", "accent_line_right"],
	]
	for spec in static_specs:
		var source := screen.get_node_or_null(String(spec[0])) as CanvasItem
		if source != null and source.visible:
			_install_vector_proxy(source, String(spec[1]), String(spec[2]), String(spec[3]))
			if String(spec[3]).begins_with("side_field_"):
				var side := String(spec[3]).trim_prefix("side_field_")
				var resolved: Dictionary = side_shapes.get(side, {})
				source.set_meta("fx_side_shape_source", str(resolved.get("source", "")))
				source.set_meta("fx_side_shape_preset", str(resolved.get("preset_id", "")))
				source.set_meta("fx_side_shape_mask", str(resolved.get("mask", "")))

	# Multiplayer name plates/accent lines are generated at runtime, but their
	# geometry is schema-authored. Matching generated masks therefore remain
	# exact and keep the real node's colour as source tint.
	if mode_format != "1v1":
		var family_plates := screen.get_node_or_null("Root/FamilyFront/Plates")
		if family_plates != null:
			for child in family_plates.get_children():
				var child_name := String(child.name)
				var lower := child_name.to_lower()
				var slot := ""
				var kind := ""
				var role := ""
				if lower.begins_with("plate_"):
					slot = lower.trim_prefix("plate_")
					kind = "plate"
					role = "NAME PLATES"
				elif lower.begins_with("accent_"):
					slot = lower.trim_prefix("accent_")
					kind = "accent"
					role = "ACCENT LINES"
				if slot == "":
					continue
				var mask_path := "res://assets/vs/generated/%s_%s_%s_mask.png" % [mode_format.to_lower(), kind, slot]
				_install_vector_proxy(child as CanvasItem, mask_path, role, "%s_%s_%s" % [kind, mode_format.to_lower(), slot])

func _install_vector_proxy(source: CanvasItem, mask_path: String, role: String, element_id: String) -> void:
	if source == null:
		return
	var mask_texture: Texture2D = load_project_texture(mask_path)
	if mask_texture == null:
		push_warning("FX Lab vector proxy mask unavailable: " + mask_path)
		return
	var parent := source.get_parent()
	if parent == null:
		return
	var proxy := TextureRect.new()
	proxy.name = str(source.name) + "_FXProxy"
	proxy.texture = mask_texture
	proxy.position = Vector2.ZERO
	proxy.size = Vector2(1280, 720)
	proxy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	proxy.z_index = source.z_index
	var tint := Color.WHITE
	if source is Polygon2D:
		tint = (source as Polygon2D).color
	elif source is Line2D:
		tint = (source as Line2D).default_color
	proxy.set_meta("fx_source_tint", tint)
	proxy.set_meta("fx_element_id", element_id)
	proxy.set_meta("fx_role", role)
	proxy.set_meta("fx_vector_proxy", true)
	# Round-2 neutral-parity fix: the generated mask carries SHAPE/ALPHA only;
	# the canonical element colour (tint) must stay authoritative. `modulate`
	# intentionally stays WHITE so the styled layer path (which mirrors the
	# node's modulate onto its quads and applies fx_source_tint separately)
	# never double-applies the tint.
	var proxy_material := ShaderMaterial.new()
	# Side fields get a living edge: the boundary itself flows and erodes
	# from a baked signed-distance field of the same shape. The mask stays the
	# proxy texture so styling/registry semantics are unchanged. Shapes without
	# a baked SDF (e.g. SVG presets) keep the flat proxy surface.
	var sdf_path := mask_path.replace("_mask", "_sdf")
	var sdf_texture: Texture2D = null
	if element_id.begins_with("side_field_") and sdf_path != mask_path:
		sdf_texture = load_project_texture(sdf_path)
	if sdf_texture != null:
		proxy_material.shader = load("res://shaders/side_field_edge.gdshader")
		proxy_material.set_shader_parameter("sdf_tex", sdf_texture)
		var ink_texture: Texture2D = load_project_texture("res://assets/vs/fx/side_field_ink.png")
		if ink_texture != null:
			proxy_material.set_shader_parameter("ink_tex", ink_texture)
			proxy_material.set_shader_parameter("ink_strength", 1.0)
		# The two fields meet on one shared clash boundary near the VS mark.
		if element_id == "side_field_left":
			proxy_material.set_shader_parameter("field_side", 1.0)
		elif element_id == "side_field_right":
			proxy_material.set_shader_parameter("field_side", -1.0)
		proxy.set_meta("fx_living_edge", true)
	else:
		proxy_material.shader = load("res://shaders/fx_vector_proxy.gdshader")
	proxy_material.set_shader_parameter("tint", tint)
	proxy.material = proxy_material
	source.visible = false
	parent.add_child(proxy)

# ---------------------------------------------------------------- records / plan

func _records_for(format: String) -> Array:
	var count := 3
	var teams: Array = []
	match format:
		"FFA_4":
			count = 4
		"TEAM_2V2":
			count = 4
			teams = [0, 0, 1, 1]
		"TEAM_2V1":
			count = 3
			teams = [0, 0, 1]
		"TEAM_3V1":
			count = 4
			teams = [0, 0, 0, 1]
	var pool := [pick_l, pick_r, str(extras[0]), str(extras[1])]
	var records: Array = []
	for i in range(count):
		var team_id := int(teams[i]) if teams.size() > i else VSRequest.StateScript.NO_TEAM
		var kind = VSRequest.StateScript.Kind.HUMAN if i == 0 else VSRequest.StateScript.Kind.CPU
		records.append(VSRequest.record(i, str(pool[i]), team_id, kind, 0))
	return records

# ------------------------------------------------------- canonical event marks
# P0 single authority: the authorable motion anchors (a documented SUBSET of
# the motion_timing lifecycle signals — entry/hold anchors only, e.g. NOT
# fighter_lock/match_ready/cover events). Timestamps ALWAYS come from the
# running screen's actual schedule (authorable_motion_event_marks); this
# table is never reconstructed a second time from JSON here.
const AUTHORABLE_MOTION_EVENTS := ["vs_enter", "stage_reveal", "fighter_reveal", "clash_impact", "hold_enter"]

func event_marks() -> Dictionary:
	if screen != null and is_instance_valid(screen) and screen.has_method("authorable_motion_event_marks"):
		return screen.authorable_motion_event_marks()
	return {}

# ---------------------------------------------------------------- assets

static func load_project_texture(path: String) -> Texture2D:
	# Normal project assets should already be imported before this scene runs.
	# The fallback deliberately handles generated authoring masks even when an
	# import sidecar/cache is missing, avoiding the silent no-op failure mode
	# found in the earlier runtime-mask implementation.
	var absolute_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		if ResourceLoader.exists(path):
			var imported = load(path)
			return imported as Texture2D if imported is Texture2D else null
	var image := Image.new()
	if image.load(absolute_path) != OK or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)
