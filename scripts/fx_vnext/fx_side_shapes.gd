class_name FxSideShapes
extends RefCounted
# Side-field geometry as a SHAPE/MASK PRESET (Round-2 architecture addition).
#
# The diagonal fields (identical to the game layout polygons in
# vs_layout_1280x720.json) are THE DEFAULT PRESET; the old hourglass stays a
# selectable legacy preset. The rendering/target
# system only ever consumes a mask reference per side, so another project-local
# side-field mask/shape can be selected later without reworking the renderer or
# the fx target registry. No shape editor exists in this round by design.
#
# Optional project-local selection file: <data_dir>/side_shapes.json
#   {
#     "left":  "CURRENT_HOURGLASS" | "ORGANIC_LOBE" | "res://..." | "user://...",
#     "right": "CURRENT_HOURGLASS" | "ORGANIC_LOBE" | "res://..." | "user://...",
#     "mirror": true            # right falls back to the left selection when unset
#   }
# Unknown, external or missing masks NEVER break the mount: they fall back to the
# default preset with a recorded warning (surfaced via resolve_side()).

const DEFAULT_PRESET := "CLASH_DIAGONAL_FIELDS"

const PRESETS := {
	"CURRENT_HOURGLASS": {
		"left": "res://assets/vs/generated/side_field_left_mask_legacy.png",
		"right": "res://assets/vs/generated/side_field_right_mask_legacy.png",
	},
	"CLASH_DIAGONAL_FIELDS": {
		"left": "res://assets/vs/generated/side_field_left_mask.png",
		"right": "res://assets/vs/generated/side_field_right_mask.png",
	},
	"ORGANIC_LOBE": {
		"left": "res://assets/vs/generated/organic_lobe_left_mask.svg",
		"right": "res://assets/vs/generated/organic_lobe_right_mask.svg",
	},
}

static func selection_path(data_dir: String) -> String:
	return data_dir.path_join("side_shapes.json")

static func load_selection(data_dir: String) -> Dictionary:
	var f := FileAccess.open(selection_path(data_dir), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

static func write_selection(data_dir: String, selection: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	var f := FileAccess.open(selection_path(data_dir), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(selection, "  "))
	f.close()
	return true

static func resolve_side(side: String, selection: Dictionary) -> Dictionary:
	# -> {ok, mask, preset_id, source: preset|explicit|fallback, warning?}
	var key := side
	if side == "right" and not selection.has("right") and bool(selection.get("mirror", false)) and selection.has("left"):
		key = "left"
	var raw := str(selection.get(key, DEFAULT_PRESET)).strip_edges()
	if PRESETS.has(raw):
		var preset: Dictionary = PRESETS[raw]
		var preset_mask := str(preset.get(side, preset.get("left", "")))
		if preset_mask == "":
			return _fallback(side, "preset %s has no mask for side %s" % [raw, side])
		return {"ok": true, "mask": preset_mask, "preset_id": raw, "source": "preset"}
	if raw.begins_with("res://") or raw.begins_with("user://"):
		if FileAccess.file_exists(raw) or ResourceLoader.exists(raw):
			return {"ok": true, "mask": raw, "preset_id": "", "source": "explicit"}
		return _fallback(side, "selected mask does not exist: " + raw)
	return _fallback(side, "not a known preset and not project-local: " + raw)

static func _fallback(side: String, warning: String) -> Dictionary:
	var preset: Dictionary = PRESETS[DEFAULT_PRESET]
	return {
		"ok": true,
		"mask": str(preset.get(side, preset.get("left", ""))),
		"preset_id": DEFAULT_PRESET,
		"source": "fallback",
		"warning": warning,
	}

static func resolve_all(data_dir: String) -> Dictionary:
	var selection := load_selection(data_dir)
	return {
		"left": resolve_side("left", selection),
		"right": resolve_side("right", selection),
		"selection": selection,
	}

static func preset_table_ok() -> Array:
	# Validates that every preset mask is a loadable project-local asset.
	var errors: Array = []
	for preset_id in PRESETS.keys():
		for side in (PRESETS[preset_id] as Dictionary).keys():
			var ref := str((PRESETS[preset_id] as Dictionary)[side])
			if not (FileAccess.file_exists(ref) or ResourceLoader.exists(ref)):
				errors.append("%s.%s missing: %s" % [str(preset_id), str(side), ref])
	return errors
