class_name FxLook
extends RefCounted
# NRCU FX Lab vNext — Look v0.4 model (schema: docs/vnext/schema/nrcu_fx_look_v04.schema.json).
#
# Owns the normalized Look document: fully materialized neutral defaults
# (specs/15 §1), stable layer ids, layer types SOURCE / SOURCE_COPY / FX and
# semantic validation (specs/09 §3). Pure data: no UI, no rendering.

const SCHEMA := "NRCU_FX_LOOK_V0_4"
const FxAssetsScript := preload("res://scripts/fx_vnext/fx_assets.gd")
const FxOperatorsScript := preload("res://scripts/fx_vnext/fx_operators.gd")

const TYPE_SOURCE := "SOURCE"
const TYPE_SOURCE_COPY := "SOURCE_COPY"
const TYPE_FX := "FX"
const TYPES := [TYPE_SOURCE, TYPE_SOURCE_COPY, TYPE_FX]

const PLANES := ["COMPOSITION_BACKGROUND", "TARGET_UNDERLAY", "TARGET_SOURCE", "TARGET_OVERLAY", "COMPOSITION_FOREGROUND"]
const BLEND_MODES := ["NORMAL", "ADD", "SCREEN", "MULTIPLY"]
const INPUTS := ["ORIGINAL_SOURCE", "TRANSFORMED_SOURCE", "LAYER_BELOW", "COMPOSITE_BELOW"]
const STATUSES := ["DRAFT", "PRODUCTION", "MIGRATION_REVIEW_REQUIRED"]
const DISPLACEMENT_DRIVERS := ["NOISE", "DIRECTIONAL", "WAVE", "CELLULAR", "FRINGE_DRIVER", "CUSTOM_TEXTURE"]
const EDGE_MODES := ["TRANSPARENT", "CLAMP", "MIRROR", "REPEAT"]
const TIME_SOURCES := ["PRESENTATION_TIME", "FREE_RUN"]
const LANES := ["TARGET_LOCAL", "FINAL_COMPOSITE", "DEFERRED_3D"]
const AUTHORITIES := ["TARGET", "COMPOSITION"]
const MASK_SOURCES := ["NONE", "ORIGINAL_SOURCE_ALPHA", "POST_DISPLACEMENT_ALPHA", "CUSTOM_MASK"]
const MASK_REGIONS := ["FULL", "EDGE_BAND", "OUTER_BAND", "INNER_BAND"]
const MASK_SPACES := ["SOURCE_SPACE", "LAYER_SPACE", "PRESENTATION_SPACE"]

static var _serial := 0

# ---------------------------------------------------------------- neutral defaults (specs/15 §1)

static func neutral_transform() -> Dictionary:
	return {
		"position_px": [0.0, 0.0],
		"scale": [1.0, 1.0],
		"rotation_deg": 0.0,
		"pivot": [0.5, 0.5],
		"flip_x": false,
		"flip_y": false,
	}

static func neutral_displacement() -> Dictionary:
	return {
		"enabled": false,
		"driver": "NOISE",
		"amount_px": [0.0, 0.0],
		"scale": 1.0,
		"speed": 0.0,
		"phase": 0.0,
		"seed": 1,
		"time_source": "PRESENTATION_TIME",
		"angle_deg": 0.0,
		"edge_mode": "TRANSPARENT",
		"custom_texture": null,
		"influence_mask": null,
	}

static func neutral_mask() -> Dictionary:
	return {
		"enabled": false,
		"source": "NONE",
		"region": "FULL",
		"space": "LAYER_SPACE",
		"expand_contract_px": 0.0,
		"width_px": 0.0,
		"feather_px": 0.0,
		"invert": false,
		"custom_mask": null,
	}

# Complete v0.3 treatment surface. Keeping these keys in every materialized FX
# layer makes old looks lossless and prevents a sparse document from silently
# selecting a different shader default after a schema upgrade.
static func neutral_fx() -> Dictionary:
	return {
		"pure_continuous": false, "size": 1.0, "intensity": 1.0, "pattern_scale": 1.0,
		"fringe": 0.0, "rgb": 0.0, "flow": 0.0, "dither": 0.0,
		"base_mode": 0.0, "base_opacity": 1.0, "base_grade_amount": 0.0,
		"grade_black_point": 0.0, "grade_white_point": 1.0, "grade_gamma": 1.0,
		"grade_contrast": 1.0, "grade_brightness": 0.0, "grade_saturation": 1.0,
		"source_pixel_size": 0.0, "source_pixel_units": 1.0,
		"mono_threshold": 0.75, "mono_mode": 1.0, "mono_bayer_level": 2.0,
		"mono_pixel": 2.0, "mono_space": 1.0,
		"dither_threshold": 0.75, "dither_black_point": 0.0, "dither_white_point": 1.0,
		"dither_gamma": 1.35, "dither_contrast": 1.6, "dither_brightness": 0.0,
		"dither_mode": 1.0, "dither_bayer_level": 2.0, "dither_pixel": 2.0,
		"dither_levels": 6.0, "dither_space": 1.0,
		"edge_source_mode": 2.0, "edge_alpha_weight": 1.2, "edge_luma_weight": 1.0,
		"edge_threshold": 0.08, "edge_width": 12.0,
		"wind_reach": 54.0, "wind_trail": 1.0, "wind_cutoff": 0.22,
		"split_separation": 10.0, "wind_displace": 1.0, "signal_gain": 1.35,
		"color_blur": 0.0, "signal_softness": 0.08, "signal_posterize": 0.0,
		"fringe_coverage_mode": 0.0, "fringe_coverage_threshold": 0.12,
		"fringe_bayer_level": 2.0, "fringe_pixel": 2.0, "fringe_space": 1.0,
		"fringe_coverage_gain": 1.0, "rgb_gradient": 0.0,
		"rgb_gradient_balance": 0.0, "rgb_gradient_contrast": 1.0,
		"fringe_color_a": [0.25, 0.95, 1.0, 1.0], "fringe_color_b": [1.0, 0.4, 0.85, 1.0],
		"fringe_bleed": 0.65, "fringe_blend_mode": 0.0, "geometry_units": 1.0,
		"effect_mask_enabled": false, "effect_mask_invert": false,
		"effect_mask_threshold": 0.5, "effect_mask_softness": 0.10,
		"effect_mask_base": false, "edge_mask_path": "", "treatment_mask_path": "",
		"driver_mode": 0.0, "driver_sampling_mode": 0.0, "driver_pixel_size": 2.0,
		"FIELD_STRENGTH": 0.42, "FIELD_SPEED": 0.55, "OUTWARDNESS": 0.55,
		"FIELD_BREAKUP": 0.85, "COORD_NUDGE": 0.18, "FIELD_SIZE": 1.0,
		"FIELD_CENTER_X": 1.25, "FIELD_CENTER_Y": 1.45,
		"LEGACY_SCALE": 5.0, "LEGACY_SPEED": 0.3, "LEGACY_RADIAL": 0.45,
		"DRIVER_CENTER_X": 1.5, "DRIVER_CENTER_Y": 1.5, "DRIVER_SCALE": 1.0,
		"DRIVER_STRETCH": 0.0, "DRIVER_ANGLE": 0.0, "DRIVER_SPEED": 1.0,
		"DRIVER_DETAIL": 0.5, "DRIVER_FLOW": 0.5,
		"flow_strength": 1.8, "flow_center_x": 0.5, "flow_center_y": 0.5,
		"rgb_shift_amount": 14.0, "rgb_shift_angle": 0.0, "rgb_shift_units": 1.0,
		"rgb_shift_alpha": 0.0, "temporal_hold": 0.0,
		"palette_strategy": 0.0, "palette_lock_a": false, "palette_lock_b": false,
		"palette_swap": false, "palette_source_color": [0.5, 0.5, 0.5, 1.0],
		"palette_hue_offset": 0.0, "palette_saturation": 1.0, "palette_value": 1.0,
		"final_tint_amount": 0.0, "final_tint_color": [1.0, 1.0, 1.0, 1.0],
		# Gold tranche operators are explicit canonical data, not aliases for
		# fringe/RGB/dither. The renderer maps these names to dedicated shader
		# branches and keeps the supplied clock contract intact.
		"operator": "NONE", "operator_secondary": "NONE", "operator_strength": 0.0, "operator_scale": 1.0,
		"operator_speed": 1.0, "operator_threshold": 0.5, "operator_softness": 0.1,
		"operator_axis_x": 1.0, "operator_axis_y": 0.0, "operator_center_x": 0.5, "operator_center_y": 0.5, "operator_anchor": "CUSTOM", "operator_progress": 0.5, "operator_progress_start": 0.0, "operator_progress_end": 1.0, "operator_progress_mode": "STATIC", "operator_polarity": 0.0, "operator_pattern_mode": 0.0, "operator_pattern_family": 0.0, "operator_distortion": 0.0, "operator_mix_mode": 0.0, "operator_scope": "ALL",
		"operator_time_source": "PRESENTATION_TIME", "operator_event_start": 0.0, "operator_duration": 0.5,
		"operator_color_a": [0.25, 0.95, 1.0, 1.0], "operator_color_b": [1.0, 0.35, 0.82, 1.0],
		"time_source": "PRESENTATION_TIME",
	}

static func neutral_motion() -> Dictionary:
	return {
		"enabled": {"dither": false, "fringe": false, "flow": false, "rgb": false},
		"tracks": {
			"dither": _neutral_motion_track(), "fringe": _neutral_motion_track(),
			"flow": _neutral_motion_track(), "rgb": _neutral_motion_track(),
		},
	}

static func _neutral_motion_track() -> Dictionary:
	return {"anchor": "manual", "anchor_time": 0.0, "delay": 0.0, "attack": 0.10,
		"hold": 0.08, "release": 0.25, "sustain": 0.0,
		"attack_curve": "cubic_out", "release_curve": "sine_in_out"}

static func new_layer(type: String, name: String) -> Dictionary:
	var layer := {
		"layer_id": next_layer_id(type),
		"name": name if name != "" else type.capitalize(),
		"type": type,
		"enabled": true,
		"locked": false,
		"opacity": 1.0,
		"blend_mode": "NORMAL",
		"plane": "TARGET_SOURCE" if type == TYPE_SOURCE else "TARGET_OVERLAY",
		"authority": "TARGET",
		# Lane is explicit metadata. Existing planes remain on the target-local
		# renderer path; FINAL_COMPOSITE is not inferred from plane names.
		"lane": "TARGET_LOCAL",
		"transform": neutral_transform(),
		"displacement": neutral_displacement(),
		"mask": neutral_mask(),
		"fx": neutral_fx(),
		"motion": neutral_motion(),
	}
	if type == TYPE_FX:
		layer["input"] = "ORIGINAL_SOURCE"
	return layer

static func new_look(look_id: String, name: String, status := "DRAFT") -> Dictionary:
	return {
		"schema": SCHEMA,
		"look_id": look_id,
		"name": name,
		"revision": 1,
		"status": status,
		"metadata": {"migrated_from": null},
		"layers": [new_layer(TYPE_SOURCE, "Source")],
	}

# ---------------------------------------------------------------- materialize

static func materialize(doc: Dictionary) -> Dictionary:
	# Canonical normalized form: every persisted Look is fully materialized.
	var out := doc.duplicate(true)
	var layers: Array = out.get("layers", [])
	var fixed_layers: Array = []
	for raw in layers:
		if not (raw is Dictionary):
			continue
		var layer: Dictionary = (raw as Dictionary).duplicate(true)
		layer["layer_id"] = str(layer.get("layer_id", next_layer_id(str(layer.get("type", "layer")).to_lower())))
		layer["name"] = str(layer.get("name", "Layer"))
		layer["type"] = str(layer.get("type", TYPE_FX))
		layer["enabled"] = bool(layer.get("enabled", true))
		layer["locked"] = bool(layer.get("locked", false))
		layer["opacity"] = float(layer.get("opacity", 1.0))
		layer["blend_mode"] = str(layer.get("blend_mode", "NORMAL"))
		layer["plane"] = str(layer.get("plane", "TARGET_SOURCE" if layer["type"] == TYPE_SOURCE else "TARGET_OVERLAY"))
		layer["lane"] = str(layer.get("lane", FxOperatorsScript.lane_for_plane(str(layer["plane"]))))
		# FINAL_COMPOSITE is a composition-owned pass. Preserve an explicit
		# authority when present, but make sparse historical Gold documents
		# canonical without silently turning target-local layers global.
		layer["authority"] = str(layer.get("authority", "COMPOSITION" if layer["lane"] == "FINAL_COMPOSITE" else "TARGET"))
		layer["transform"] = _coerce_transform(_materialize_into(neutral_transform(), layer.get("transform", {})))
		layer["displacement"] = _coerce_displacement(_materialize_into(neutral_displacement(), layer.get("displacement", {})))
		layer["mask"] = _coerce_mask(_materialize_into(neutral_mask(), layer.get("mask", {})))
		if not (layer.get("fx") is Dictionary):
			layer["fx"] = neutral_fx()
		else:
			layer["fx"] = _materialize_into(neutral_fx(), layer["fx"])
		if not (layer.get("motion") is Dictionary):
			layer["motion"] = neutral_motion()
		else:
			layer["motion"] = _coerce_motion(_materialize_into(neutral_motion(), layer["motion"]))
		if layer["type"] == TYPE_FX:
			layer["input"] = str(layer.get("input", "ORIGINAL_SOURCE"))
		else:
			layer.erase("input")
		fixed_layers.append(layer)
	# LG-04: the mandatory SOURCE layer is pinned at root index 0 — plane
	# pinning alone does not fix dependency order. Stable for the rest.
	var source_index := -1
	for i in range(fixed_layers.size()):
		if str((fixed_layers[i] as Dictionary).get("type", "")) == TYPE_SOURCE:
			source_index = i
			break
	if source_index > 0:
		var source_layer: Dictionary = fixed_layers[source_index]
		fixed_layers.remove_at(source_index)
		fixed_layers.push_front(source_layer)
	out["layers"] = fixed_layers
	out["schema"] = str(out.get("schema", SCHEMA))
	out["look_id"] = str(out.get("look_id", ""))
	out["name"] = str(out.get("name", ""))
	out["revision"] = int(out.get("revision", 1))
	out["status"] = str(out.get("status", "DRAFT"))
	if not (out.get("metadata") is Dictionary):
		out["metadata"] = {}
	if not out["metadata"].has("migrated_from"):
		out["metadata"]["migrated_from"] = null
	return out

static func _materialize_into(neutral: Dictionary, incoming) -> Dictionary:
	var out := neutral.duplicate(true)
	if incoming is Dictionary:
		for key in (incoming as Dictionary).keys():
			if out.has(key) or str(key).begins_with("x_"):
				out[key] = (incoming as Dictionary)[key]
	return out

static func _is_extension_key(key: String) -> bool:
	if not key.begins_with("x_") or key.length() <= 2:
		return false
	for character in key.substr(2):
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") and character != "_":
			return false
	return true

static func input_aliases() -> Dictionary:
	return {"rgb_shift": "rgb_shift_amount", "rgb_angle": "rgb_shift_angle", "rgb_alpha": "rgb_shift_alpha", "fringe_blend": "fringe_blend_mode", "fx_size": "size", "fx_intensity": "intensity"}

static func reject_aliases(doc: Dictionary) -> Dictionary:
	# Raw-form scan only: legacy aliases and malformed x_ keys fail closed
	# WITHOUT structural validation, so sparse-but-materializable input
	# (neutral defaults filled by materialize()) is still accepted.
	var errors: Array = []
	_collect_input_errors(doc, "look", input_aliases(), errors)
	return {"ok": errors.is_empty(), "errors": errors}

static func validate_input(doc: Dictionary) -> Dictionary:
	var result: Dictionary = validate(doc)
	var errors: Array = result.get("errors", []).duplicate()
	_collect_input_errors(doc, "look", input_aliases(), errors)
	errors.append_array(_validate_migrated_from(doc))
	return {"ok": errors.is_empty(), "errors": errors}

static func _validate_migrated_from(doc: Dictionary) -> Array:
	var errors: Array = []
	var metadata = doc.get("metadata", null)
	if not (metadata is Dictionary):
		return errors
	if not (metadata as Dictionary).has("migrated_from"):
		return errors
	var origin = (metadata as Dictionary)["migrated_from"]
	if origin == null or origin is String:
		return errors
	if not (origin is Dictionary):
		return ["metadata.migrated_from: expected null, string, or versioned object"]
	var allowed := ["schema", "look_id", "source_status", "time_source"]
	for key in (origin as Dictionary).keys():
		if not str(key) in allowed:
			errors.append("metadata.migrated_from.%s: unknown field" % str(key))
	if str((origin as Dictionary).get("schema", "")) == "":
		errors.append("metadata.migrated_from.schema: must not be empty")
	if str((origin as Dictionary).get("look_id", "")) == "":
		errors.append("metadata.migrated_from.look_id: must not be empty")
	return errors

static func _collect_input_errors(value, path: String, aliases: Dictionary, errors: Array) -> void:
	if not (value is Dictionary):
		return
	for raw_key in (value as Dictionary).keys():
		var key := str(raw_key)
		if aliases.has(key):
			errors.append("%s.%s: legacy alias; use %s" % [path, key, aliases[key]])
		elif key.begins_with("x_") and not _is_extension_key(key):
			errors.append("%s.%s: invalid extension key" % [path, key])
		var child = (value as Dictionary)[raw_key]
		if child is Dictionary:
			_collect_input_errors(child, path + "." + key, aliases, errors)
		elif child is Array:
			for item in child:
				if item is Dictionary:
					_collect_input_errors(item, path + "." + key, aliases, errors)

# Type canonicalization: JSON loading yields floats for every number, code paths
# yield ints. Canonical form fixes the numeric type per schema field so that
# serialization roundtrips are strictly stable (Godot's recursive container
# equality is type-strict for numbers).
static func _coerce_transform(obj: Dictionary) -> Dictionary:
	obj["position_px"] = _float_pair(obj.get("position_px", [0.0, 0.0]))
	obj["scale"] = _float_pair(obj.get("scale", [1.0, 1.0]))
	obj["rotation_deg"] = float(obj.get("rotation_deg", 0.0))
	obj["pivot"] = _float_pair(obj.get("pivot", [0.5, 0.5]))
	obj["flip_x"] = bool(obj.get("flip_x", false))
	obj["flip_y"] = bool(obj.get("flip_y", false))
	return obj

static func _coerce_displacement(obj: Dictionary) -> Dictionary:
	obj["enabled"] = bool(obj.get("enabled", false))
	obj["driver"] = str(obj.get("driver", "NOISE"))
	obj["amount_px"] = _float_pair(obj.get("amount_px", [0.0, 0.0]))
	obj["scale"] = float(obj.get("scale", 1.0))
	obj["speed"] = float(obj.get("speed", 0.0))
	obj["phase"] = float(obj.get("phase", 0.0))
	obj["seed"] = int(obj.get("seed", 1))
	obj["time_source"] = str(obj.get("time_source", "PRESENTATION_TIME"))
	obj["angle_deg"] = float(obj.get("angle_deg", 0.0))
	obj["edge_mode"] = str(obj.get("edge_mode", "TRANSPARENT"))
	if obj.get("custom_texture") != null:
		obj["custom_texture"] = str(obj["custom_texture"])
	if obj.get("influence_mask") is Dictionary:
		obj["influence_mask"] = _coerce_mask((obj["influence_mask"] as Dictionary).duplicate(true))
	return obj

static func _coerce_mask(obj: Dictionary) -> Dictionary:
	obj["enabled"] = bool(obj.get("enabled", false))
	obj["source"] = str(obj.get("source", "NONE"))
	obj["region"] = str(obj.get("region", "FULL"))
	obj["space"] = str(obj.get("space", "LAYER_SPACE"))
	obj["expand_contract_px"] = float(obj.get("expand_contract_px", 0.0))
	obj["width_px"] = float(obj.get("width_px", 0.0))
	obj["feather_px"] = float(obj.get("feather_px", 0.0))
	obj["invert"] = bool(obj.get("invert", false))
	if obj.get("custom_mask") != null:
		obj["custom_mask"] = str(obj["custom_mask"])
	return obj

static func _coerce_motion(obj: Dictionary) -> Dictionary:
	var out: Dictionary = neutral_motion()
	var enabled: Dictionary = obj.get("enabled", {}) if obj.get("enabled") is Dictionary else {}
	for key in ["dither", "fringe", "flow", "rgb"]:
		out["enabled"][key] = bool(enabled.get(key, false))
	var tracks: Dictionary = obj.get("tracks", {}) if obj.get("tracks") is Dictionary else {}
	# Accept the compact legacy shape {dither:{...}, ...} as an additive input.
	for key in ["dither", "fringe", "flow", "rgb"]:
		var incoming = tracks.get(key, obj.get(key, {}))
		if incoming is Dictionary:
			var merged: Dictionary = _materialize_into(_neutral_motion_track(), incoming)
			merged["anchor"] = str(merged.get("anchor", "manual"))
			merged["anchor_time"] = float(merged.get("anchor_time", 0.0))
			for numeric in ["delay", "attack", "hold", "release", "sustain"]:
				merged[numeric] = float(merged.get(numeric, 0.0))
			out["tracks"][key] = merged
	return out

static func swap_palette_in(doc: Dictionary, layer_id: String) -> bool:
	var layer: Dictionary = find_layer(doc, layer_id)
	if layer.is_empty() or not (layer.get("fx") is Dictionary):
		return false
	var fx: Dictionary = layer["fx"]
	var a = fx.get("fringe_color_a", neutral_fx()["fringe_color_a"])
	var b = fx.get("fringe_color_b", neutral_fx()["fringe_color_b"])
	fx["fringe_color_a"] = b
	fx["fringe_color_b"] = a
	return true

static func palette_strategy_name(strategy: float) -> String:
	var names := ["DOMINANT + DISTANT", "COMPLEMENT", "SPLIT COMPLEMENT", "ANALOGOUS", "TRIADIC", "MONOCHROME"]
	var index: int = clampi(int(strategy), 0, names.size() - 1)
	return names[index]

static func _palette_adjust(color: Color, delta: float, hue_offset: float, sat_factor: float, value_factor: float) -> Color:
	return Color.from_hsv(fposmod(color.h + delta + hue_offset / 360.0, 1.0), clampf(color.s * sat_factor, 0.0, 1.0), clampf(color.v * value_factor, 0.0, 1.0), color.a)

static func resolve_palette(dominant: Color, distant: Color, strategy: int, hue_offset: float, sat_factor: float, value_factor: float, lock_a: bool, lock_b: bool, current_a: Color, current_b: Color) -> Dictionary:
	var a := dominant
	var b := distant
	match clampi(strategy, 0, 5):
		1: a = _palette_adjust(dominant, 0.0, hue_offset, sat_factor, value_factor); b = _palette_adjust(dominant, 0.5, hue_offset, sat_factor, value_factor)
		2: a = _palette_adjust(dominant, 5.0 / 12.0, hue_offset, sat_factor, value_factor); b = _palette_adjust(dominant, 7.0 / 12.0, hue_offset, sat_factor, value_factor)
		3: a = _palette_adjust(dominant, -1.0 / 12.0, hue_offset, sat_factor, value_factor); b = _palette_adjust(dominant, 1.0 / 12.0, hue_offset, sat_factor, value_factor)
		4: a = _palette_adjust(dominant, 1.0 / 3.0, hue_offset, sat_factor, value_factor); b = _palette_adjust(dominant, 2.0 / 3.0, hue_offset, sat_factor, value_factor)
		5: a = _palette_adjust(dominant, 0.0, hue_offset, sat_factor * 0.9, value_factor * 1.25); b = _palette_adjust(dominant, 0.0, hue_offset, sat_factor * 0.75, value_factor * 0.55)
		_: a = _palette_adjust(dominant, 0.0, hue_offset, sat_factor, value_factor); b = _palette_adjust(distant, 0.0, hue_offset, sat_factor, value_factor)
	return {"a": current_a if lock_a else a, "b": current_b if lock_b else b}

static func _color_from_array(value) -> Color:
	if value is Color:
		return value
	if value is Array and (value as Array).size() >= 3:
		var c: Array = value
		return Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0)
	return Color(1, 1, 1, 1)

static func _color_to_array(color: Color) -> Array:
	return [color.r, color.g, color.b, color.a]

static func generate_palette(doc: Dictionary, layer_id: String, dominant: Color, distant: Color) -> Dictionary:
	var layer := find_layer(doc, layer_id)
	if layer.is_empty() or not (layer.get("fx") is Dictionary):
		return {"ok": false, "errors": ["layer %s: missing fx" % layer_id]}
	var fx: Dictionary = layer["fx"]
	var colors := resolve_palette(dominant, distant, int(fx.get("palette_strategy", 0)), float(fx.get("palette_hue_offset", 0.0)), float(fx.get("palette_saturation", 1.0)), float(fx.get("palette_value", 1.0)), bool(fx.get("palette_lock_a", false)), bool(fx.get("palette_lock_b", false)), _color_from_array(fx.get("fringe_color_a", [1, 1, 1, 1])), _color_from_array(fx.get("fringe_color_b", [1, 1, 1, 1])))
	fx["fringe_color_a"] = _color_to_array(colors["a"])
	fx["fringe_color_b"] = _color_to_array(colors["b"])
	return {"ok": true, "doc": doc}

static func _float_pair(vec) -> Array:
	var out := [0.0, 0.0]
	if vec is Array and (vec as Array).size() >= 2:
		out[0] = float((vec as Array)[0])
		out[1] = float((vec as Array)[1])
	return out

# ---------------------------------------------------------------- validation

static func validate(doc: Dictionary) -> Dictionary:
	var errors: Array = []
	if str(doc.get("schema", "")) != SCHEMA:
		errors.append("schema: expected %s, got %s" % [SCHEMA, str(doc.get("schema", ""))])
	if str(doc.get("look_id", "")) == "":
		errors.append("look_id: must not be empty")
	elif not is_valid_look_id(str(doc.get("look_id", ""))):
		# R3 §23 security finding: an id with path separators or control characters
		# would escape the looks/ directory or destabilize file paths.
		errors.append("look_id: illegal id %s" % str(doc.get("look_id", "")))
	if str(doc.get("name", "")) == "":
		errors.append("name: must not be empty")
	var revision := int(doc.get("revision", 0))
	if revision < 1:
		errors.append("revision: must be >= 1")
	if str(doc.get("status", "")) not in STATUSES:
		errors.append("status: invalid value %s" % str(doc.get("status", "")))
	var layers: Array = doc.get("layers", [])
	if layers.is_empty():
		errors.append("layers: at least one layer required")
	var source_count := 0
	var seen_ids: Dictionary = {}
	for raw in layers:
		if not (raw is Dictionary):
			errors.append("layers: entry is not an object")
			continue
		var layer: Dictionary = raw
		var layer_id := str(layer.get("layer_id", ""))
		var type := str(layer.get("type", ""))
		if layer_id.length() < 8:
			errors.append("layer_id: too short: %s" % layer_id)
		if seen_ids.has(layer_id):
			errors.append("layer_id: duplicate: %s" % layer_id)
		seen_ids[layer_id] = true
		if type not in TYPES:
			errors.append("layer type: invalid %s" % type)
			continue
		if type == TYPE_SOURCE:
			source_count += 1
			if str(layer.get("plane", "")) != "TARGET_SOURCE":
				errors.append("SOURCE layer must use TARGET_SOURCE plane (layer %s)" % layer_id)
		if type == TYPE_FX:
			if str(layer.get("input", "")) not in INPUTS:
				errors.append("FX layer requires a valid input (layer %s)" % layer_id)
		elif layer.has("input"):
			errors.append("non-FX layer must not carry input (layer %s)" % layer_id)
		if str(layer.get("plane", "")) not in PLANES:
			errors.append("plane: invalid %s (layer %s)" % [str(layer.get("plane", "")), layer_id])
		var authority := str(layer.get("authority", "TARGET"))
		if authority not in AUTHORITIES:
			errors.append("authority: invalid %s (layer %s)" % [authority, layer_id])
		elif str(layer.get("lane", "")) == "FINAL_COMPOSITE" and authority != "COMPOSITION":
			errors.append("FINAL_COMPOSITE layer must use COMPOSITION authority (layer %s)" % layer_id)
		elif str(layer.get("lane", "")) != "FINAL_COMPOSITE" and authority != "TARGET":
			errors.append("target-local layer must use TARGET authority (layer %s)" % layer_id)
		var lane_result: Dictionary = FxOperatorsScript.validate_layer_lane(layer)
		errors.append_array(lane_result.get("errors", []))
		if not bool(lane_result.get("ok", false)) and lane_result.get("errors", []).is_empty():
			errors.append("lane: invalid (layer %s)" % layer_id)
		if str(lane_result.get("lane", "")) == "FINAL_COMPOSITE" and type != TYPE_FX:
			errors.append("FINAL_COMPOSITE lane requires an FX layer (layer %s)" % layer_id)
		if str(layer.get("blend_mode", "")) not in BLEND_MODES:
			errors.append("blend_mode: invalid %s (layer %s)" % [str(layer.get("blend_mode", "")), layer_id])
		var opacity := float(layer.get("opacity", -1.0))
		if not is_finite(opacity) or opacity < 0.0 or opacity > 1.0:
			errors.append("opacity out of range (layer %s)" % layer_id)
		errors.append_array(_validate_transform(layer.get("transform", {}), layer_id))
		errors.append_array(_validate_displacement(layer.get("displacement", {}), layer_id))
		errors.append_array(_validate_mask(layer.get("mask", {}), layer_id))
		errors.append_array(_validate_fx(layer.get("fx", {}), layer_id, str(layer.get("lane", ""))))
		errors.append_array(_validate_motion(layer.get("motion", {}), layer_id))
	if source_count != 1:
		errors.append("layers: exactly one SOURCE layer required (found %d)" % source_count)
	elif layers.is_empty() or not (layers[0] is Dictionary) or str((layers[0] as Dictionary).get("type", "")) != TYPE_SOURCE:
		errors.append("layers: SOURCE must be at root index 0")
	errors.append_array(validate_topology(doc))
	return {"ok": errors.is_empty(), "errors": errors}

# LG-03: render-topology constraints live in the MODEL, not only in renderer
# construction — Production must reject what the renderer would reject.
# Mirrors FxLayerRenderer SUPPORTED_INPUTS/SUPPORTED_BLENDS/OFFSET_INPUTS.
static func validate_topology(doc: Dictionary) -> Array:
	var errors: Array = []
	var layers: Array = doc.get("layers", [])
	var viewport_consumers := 0
	var has_transformed_consumer := false
	for raw in layers:
		if not (raw is Dictionary):
			continue
		var layer: Dictionary = raw
		if not bool(layer.get("enabled", true)):
			continue
		if str(layer.get("type", "")) != "FX":
			continue
		var input := str(layer.get("input", "ORIGINAL_SOURCE"))
		var blend := str(layer.get("blend_mode", "NORMAL"))
		var lid := str(layer.get("layer_id", ""))
		if input not in ["ORIGINAL_SOURCE", "TRANSFORMED_SOURCE", "LAYER_BELOW", "COMPOSITE_BELOW"]:
			errors.append("topology: unsupported input %s (layer %s)" % [input, lid])
		if blend not in ["NORMAL", "ADD", "SCREEN", "MULTIPLY"]:
			errors.append("topology: unsupported blend %s (layer %s)" % [blend, lid])
		if input in ["LAYER_BELOW", "COMPOSITE_BELOW"]:
			viewport_consumers += 1
		if input == "TRANSFORMED_SOURCE":
			has_transformed_consumer = true
	if viewport_consumers > 1:
		errors.append("topology: only one offscreen-input consumer per target is supported yet")
	if has_transformed_consumer and viewport_consumers > 0:
		errors.append("topology: mixing TRANSFORMED_SOURCE with LAYER_BELOW/COMPOSITE_BELOW needs nested stages (unsupported yet)")
	return errors

static func _validate_fx(fx, layer_id: String, lane: String = "") -> Array:
	var errors: Array = []
	if not (fx is Dictionary):
		return ["fx: missing (layer %s)" % layer_id]
	var f: Dictionary = fx
	for key in ["size", "intensity", "pattern_scale", "fringe", "rgb", "flow", "dither",
		"base_mode", "base_opacity", "base_grade_amount", "grade_black_point", "grade_white_point",
		"grade_gamma", "grade_contrast", "grade_brightness", "grade_saturation", "source_pixel_size",
		"source_pixel_units", "mono_threshold", "mono_mode", "mono_bayer_level", "mono_pixel", "mono_space",
		"dither_threshold", "dither_black_point", "dither_white_point", "dither_gamma", "dither_contrast",
		"dither_brightness", "dither_mode", "dither_bayer_level", "dither_pixel", "dither_levels", "dither_space",
		"edge_source_mode", "edge_alpha_weight", "edge_luma_weight", "edge_threshold", "edge_width",
		"wind_reach", "wind_trail", "wind_cutoff", "split_separation", "wind_displace", "signal_gain",
		"color_blur", "signal_softness", "signal_posterize", "fringe_coverage_mode", "fringe_coverage_threshold",
		"fringe_bayer_level", "fringe_pixel", "fringe_space", "fringe_coverage_gain", "rgb_gradient",
		"rgb_gradient_balance", "rgb_gradient_contrast", "fringe_bleed", "fringe_blend_mode", "geometry_units",
		"effect_mask_threshold", "effect_mask_softness", "driver_mode", "driver_sampling_mode", "driver_pixel_size",
		"FIELD_STRENGTH", "FIELD_SPEED", "OUTWARDNESS", "FIELD_BREAKUP", "COORD_NUDGE", "FIELD_SIZE",
		"FIELD_CENTER_X", "FIELD_CENTER_Y", "LEGACY_SCALE", "LEGACY_SPEED", "LEGACY_RADIAL", "DRIVER_CENTER_X",
		"DRIVER_CENTER_Y", "DRIVER_SCALE", "DRIVER_STRETCH", "DRIVER_ANGLE", "DRIVER_SPEED", "DRIVER_DETAIL",
		"DRIVER_FLOW", "flow_strength", "flow_center_x", "flow_center_y", "rgb_shift_amount", "rgb_shift_angle",
		"rgb_shift_units", "rgb_shift_alpha", "temporal_hold", "palette_strategy", "palette_hue_offset",
		"palette_saturation", "palette_value", "final_tint_amount",
		"operator_strength", "operator_scale", "operator_speed", "operator_threshold", "operator_softness", "operator_mix",
		"operator_axis_x", "operator_axis_y", "operator_center_x", "operator_center_y", "operator_progress", "operator_progress_start", "operator_progress_end", "operator_polarity", "operator_pattern_mode", "operator_pattern_family", "operator_distortion", "operator_mix_mode", "operator_event_start", "operator_duration"]:
		if f.has(key) and not _finite_number(f.get(key, null)):
			errors.append("fx.%s: non-finite (layer %s)" % [key, layer_id])
	for key in ["palette_lock_a", "palette_lock_b", "palette_swap"]:
		if f.has(key) and not (f.get(key) is bool):
			errors.append("fx.%s: expected bool (layer %s)" % [key, layer_id])
	if str(f.get("operator_scope", "ALL")) not in ["ALL", "ECHO_ONLY", "PRIMARY_ONLY", "EXCLUDE_PRIMARY"]:
		errors.append("fx.operator_scope: invalid (layer %s)" % layer_id)
	if str(f.get("operator_anchor", "CUSTOM")) not in ["VS_MARK", "TARGET_CENTER", "LEFT_FIGHTER", "RIGHT_FIGHTER", "CUSTOM"]:
		errors.append("fx.operator_anchor: invalid (layer %s)" % layer_id)
	if str(f.get("operator_progress_mode", "STATIC")) not in ["STATIC", "EVENT_LINEAR"]:
		errors.append("fx.operator_progress_mode: invalid (layer %s)" % layer_id)
	if f.has("palette_source_color"):
		var source_color = f.get("palette_source_color", null)
		if not (source_color is Array) or (source_color as Array).size() < 3 or not _finite_numbers(source_color as Array):
			errors.append("fx.palette_source_color: expected finite color (layer %s)" % layer_id)
	for key in ["fringe_color_a", "fringe_color_b", "final_tint_color", "operator_color_a", "operator_color_b"]:
		if not f.has(key):
			continue
		var color = f.get(key, null)
		if not (color is Array) or (color as Array).size() < 3 or not _finite_numbers(color as Array):
			errors.append("fx.%s: expected finite color (layer %s)" % [key, layer_id])
	if f.has("time_source") and str(f.get("time_source", "")) not in TIME_SOURCES:
		errors.append("fx.time_source: invalid (layer %s)" % layer_id)
	if f.has("operator") and str(f.get("operator", "")) not in ["NONE", "speedlines_field", "pattern_transition", "noise_erosion_border", "pixel_sort_smear", "vacuum_burst"]:
		errors.append("fx.operator: invalid (layer %s)" % layer_id)
	if f.has("operator_secondary") and str(f.get("operator_secondary", "")) not in ["NONE", "speedlines_field", "pattern_transition", "vacuum_burst"]:
		errors.append("fx.operator_secondary: invalid (layer %s)" % layer_id)
	if f.has("operator_time_source") and str(f.get("operator_time_source", "")) not in TIME_SOURCES:
		errors.append("fx.operator_time_source: invalid (layer %s)" % layer_id)
	var operator_id := str(f.get("operator", "NONE"))
	var secondary_id := str(f.get("operator_secondary", "NONE"))
	if operator_id != "NONE":
		var expected_lane := str(FxOperatorsScript.operator_entry(operator_id).get("lane", ""))
		if expected_lane != "" and lane != "" and lane != expected_lane:
			errors.append("fx.operator: %s requires lane %s (layer %s has %s)" % [operator_id, expected_lane, layer_id, lane])
	if secondary_id != "NONE":
		if lane != "FINAL_COMPOSITE":
			errors.append("fx.operator_secondary: %s requires lane FINAL_COMPOSITE (layer %s)" % [secondary_id, layer_id])
		if not (operator_id == "speedlines_field" and secondary_id == "vacuum_burst"):
			errors.append("fx.operator_secondary: unsupported Gold pair %s + %s (layer %s)" % [operator_id, secondary_id, layer_id])
	# MK-02/MK-04: treatment-mask and edge-mask asset intents are validated
	# here; a missing required asset fails closed at apply time.
	if bool(f.get("effect_mask_enabled", false)):
		if str(f.get("treatment_mask_path", "")).strip_edges() == "":
			errors.append("fx.treatment_mask_path: required when effect_mask_enabled (layer %s)" % layer_id)
		else:
			errors.append_array(_validate_asset_path(f["treatment_mask_path"], "fx.treatment_mask_path", layer_id))
	# Dormant treatment path (effect disabled): kept as-is, never validated
	# here — reactivation revalidates (researcher 12-10 §2).
	# MK-02: the custom edge source is not wired to any live shader path
	# (renderer drives procedural modes 0/1/2 only) — persisting a custom
	# edge asset would pretend a semantic that never renders.
	if str(f.get("edge_mask_path", "")).strip_edges() != "":
		errors.append("fx.edge_mask_path: unsupported — custom edge source is not wired (layer %s)" % layer_id)
	if f.has("edge_source_mode") and not _finite_number(f.get("edge_source_mode", null)):
		errors.append("fx.edge_source_mode: non-finite (layer %s)" % layer_id)
	elif float(f.get("edge_source_mode", 2.0)) < 0.0 or float(f.get("edge_source_mode", 2.0)) > 2.0:
		errors.append("fx.edge_source_mode: supported modes are 0/1/2 (layer %s)" % layer_id)
	return errors

static func _validate_motion(motion, layer_id: String) -> Array:
	var errors: Array = []
	if not (motion is Dictionary):
		return ["motion: missing (layer %s)" % layer_id]
	if (motion as Dictionary).is_empty():
		return []
	var m: Dictionary = motion
	var enabled: Dictionary = m.get("enabled", {}) if m.get("enabled") is Dictionary else {}
	var tracks: Dictionary = m.get("tracks", {}) if m.get("tracks") is Dictionary else {}
	for key in ["dither", "fringe", "flow", "rgb"]:
		if not (enabled.get(key, false) is bool):
			errors.append("motion.enabled.%s: expected bool (layer %s)" % [key, layer_id])
		var track: Dictionary = tracks.get(key, {}) if tracks.get(key, {}) is Dictionary else {}
		# Researcher B: only manual / fixed / authority-known events author.
		# An unknown name (e.g. a clash_impct typo) must fail closed here,
		# never silently behave like fixed anchor_time in production.
		var anchor := str(track.get("anchor", "manual"))
		if anchor != "manual" and anchor != "fixed" and not (anchor in FxScreenRuntime.AUTHORABLE_MOTION_EVENTS):
			errors.append("motion.%s.anchor: unknown event '%s' (layer %s)" % [key, anchor, layer_id])
		for numeric in ["anchor_time", "delay", "attack", "hold", "release", "sustain"]:
			if not _finite_number(track.get(numeric, null)):
				errors.append("motion.%s.%s: non-finite (layer %s)" % [key, numeric, layer_id])
		# TM-07: durations non-negative and sustain bounded — the runtime
		# silently clamps these, so persisted values must agree upfront.
		for numeric in ["anchor_time", "delay", "hold"]:
			if _finite_number(track.get(numeric, null)) and float(track[numeric]) < 0.0:
				errors.append("motion.%s.%s: must be >= 0 (layer %s)" % [key, numeric, layer_id])
		for numeric in ["attack", "release"]:
			if _finite_number(track.get(numeric, null)) and float(track[numeric]) <= 0.0:
				errors.append("motion.%s.%s: must be > 0 (layer %s)" % [key, numeric, layer_id])
		if _finite_number(track.get("sustain", null)) and (float(track["sustain"]) < 0.0 or float(track["sustain"]) > 1.0):
			errors.append("motion.%s.sustain: must be in [0, 1] (layer %s)" % [key, layer_id])
	return errors

static func _validate_transform(transform, layer_id: String) -> Array:
	var errors: Array = []
	if not (transform is Dictionary):
		errors.append("transform: missing (layer %s)" % layer_id)
		return errors
	var t: Dictionary = transform
	for key in ["position_px", "scale", "pivot"]:
		var vec = t.get(key, null)
		if not (vec is Array) or (vec as Array).size() != 2:
			errors.append("transform.%s: expected vec2 (layer %s)" % [key, layer_id])
		elif not _finite_numbers(vec):
			errors.append("transform.%s: non-finite value (layer %s)" % [key, layer_id])
	if t.get("scale") is Array and (t["scale"] as Array).size() == 2:
		var scale: Array = t["scale"]
		if float(scale[0]) <= 0.0 or float(scale[1]) <= 0.0:
			errors.append("transform.scale: must be > 0 (layer %s)" % layer_id)
	if t.get("pivot") is Array and (t["pivot"] as Array).size() == 2:
		var pivot: Array = t["pivot"]
		for i in range(2):
			var v := float(pivot[i])
			if v < 0.0 or v > 1.0:
				errors.append("transform.pivot: out of [0,1] (layer %s)" % layer_id)
	if not _finite_number(t.get("rotation_deg", null)):
		errors.append("transform.rotation_deg: non-finite (layer %s)" % layer_id)
	return errors

static func _validate_displacement(displacement, layer_id: String) -> Array:
	var errors: Array = []
	if not (displacement is Dictionary):
		errors.append("displacement: missing (layer %s)" % layer_id)
		return errors
	var d: Dictionary = displacement
	if str(d.get("driver", "")) not in DISPLACEMENT_DRIVERS:
		errors.append("displacement.driver: invalid (layer %s)" % layer_id)
	if str(d.get("edge_mode", "")) not in EDGE_MODES:
		errors.append("displacement.edge_mode: invalid (layer %s)" % layer_id)
	if str(d.get("time_source", "")) not in TIME_SOURCES:
		errors.append("displacement.time_source: invalid (layer %s)" % layer_id)
	if not (d.get("amount_px") is Array) or not _finite_numbers(d.get("amount_px", [0, 0])):
		errors.append("displacement.amount_px: invalid (layer %s)" % layer_id)
	if not _finite_number(d.get("scale", null)) or float(d.get("scale", 0.0)) <= 0.0:
		errors.append("displacement.scale: must be > 0 (layer %s)" % layer_id)
	for key in ["speed", "phase", "angle_deg"]:
		if not _finite_number(d.get(key, null)):
			errors.append("displacement.%s: non-finite (layer %s)" % [key, layer_id])
	if d.get("custom_texture") != null and str(d.get("driver", "")) == "CUSTOM_TEXTURE":
		errors.append_array(_validate_asset_path(d["custom_texture"], "displacement.custom_texture", layer_id))
	# UI-07/08: CUSTOM_TEXTURE without a texture would silently render the
	# procedural field — fail closed like MK-03/treatment-mask.
	if str(d.get("driver", "")) == "CUSTOM_TEXTURE" and (d.get("custom_texture") == null or str(d.get("custom_texture")).strip_edges() == ""):
		errors.append("displacement.custom_texture: required when driver is CUSTOM_TEXTURE (layer %s)" % layer_id)
	if d.get("influence_mask") != null and d["influence_mask"] is Dictionary:
		errors.append_array(_validate_mask(d["influence_mask"], layer_id))
	return errors

static func _validate_mask(mask, layer_id: String) -> Array:
	var errors: Array = []
	if not (mask is Dictionary):
		errors.append("mask: missing (layer %s)" % layer_id)
		return errors
	var m: Dictionary = mask
	if str(m.get("source", "")) not in MASK_SOURCES:
		errors.append("mask.source: invalid (layer %s)" % layer_id)
	if str(m.get("region", "")) not in MASK_REGIONS:
		errors.append("mask.region: invalid (layer %s)" % layer_id)
	if str(m.get("space", "")) not in MASK_SPACES:
		errors.append("mask.space: invalid (layer %s)" % layer_id)
	if str(m.get("space", "")) == "FOLLOW_LAYER":
		errors.append("mask.space: FOLLOW_LAYER is not a persisted value (layer %s)" % layer_id)
	for key in ["expand_contract_px", "width_px", "feather_px"]:
		if not _finite_number(m.get(key, null)):
			errors.append("mask.%s: non-finite (layer %s)" % [key, layer_id])
		elif float(m[key]) < 0.0 and key != "expand_contract_px":
			errors.append("mask.%s: must be >= 0 (layer %s)" % [key, layer_id])
	if m.get("custom_mask") != null and bool(m.get("enabled", false)) and str(m.get("source", "")) == "CUSTOM_MASK":
		errors.append_array(_validate_asset_path(m["custom_mask"], "mask.custom_mask", layer_id))
	# MK-03: an enabled CUSTOM_MASK without an asset must fail closed here —
	# the shader/runtime must never silently fall back to full-mask behavior.
	if bool(m.get("enabled", false)) and str(m.get("source", "")) == "CUSTOM_MASK":
		if m.get("custom_mask") == null or str(m.get("custom_mask")).strip_edges() == "":
			errors.append("mask.custom_mask: required when source is CUSTOM_MASK (layer %s)" % layer_id)
	# MK-01: enabled with source NONE samples no field — documented no-op
	# passthrough (the shader returns 1.0), not a hazard, so it validates.
	# Authors should disable the mask instead; see MASK_CONTRACT.md P1.
	return errors

static func _validate_asset_path(path, label: String, layer_id: String) -> Array:
	var errors: Array = []
	var text := str(path)
	if text.begins_with("res://") or text.begins_with("user://"):
		# Project-local and app-local references are valid only when the asset is
		# present. Persisting a missing user:// ref would make the materialization
		# look valid while the renderer silently samples an empty texture.
		if not FileAccess.file_exists(text) and not ResourceLoader.exists(text):
			errors.append("%s: asset does not exist: %s (layer %s)" % [label, text, layer_id])
			return errors
		# UI-07/08: existence is not loadability. A present-but-corrupt or
		# non-texture file must fail closed here (same rules as FxAssets
		# asset_health), never survive to silent renderer fallback.
		if not FxAssetsScript.is_image_path(text) or FxAssetsScript.load_texture(text) == null:
			errors.append("%s: asset not loadable as Texture2D: %s (layer %s)" % [label, text, layer_id])
	elif text.contains("://"):
		errors.append("%s: must be project-local (layer %s)" % [label, layer_id])
	elif text.begins_with("/") or text.contains(":\\"):
		errors.append("%s: absolute paths are invalid (layer %s)" % [label, layer_id])
	elif text.begins_with("res://"):
		# specs/09 §3: project-local AND loadable.
		if not FileAccess.file_exists(text) and not ResourceLoader.exists(text):
			errors.append("%s: asset does not exist: %s (layer %s)" % [label, text, layer_id])
	return errors

# UI-05: single source of authoring metadata for canonical fx fields.
# Normal macros AND expert controls consume this table, so ranges/units/types
# cannot drift apart again. Kinds: amount/int (slider), option (names),
# check (bool), color (palette page), asset (dedicated picker row),
# compat (persisted, no creative control by contract).
static func field_meta() -> Dictionary:
	return {
		"fringe": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"rgb": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"flow": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"dither": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"intensity": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"size": {"kind": "amount", "min": 0.1, "max": 8.0, "step": 0.05},
		"pattern_scale": {"kind": "amount", "min": 0.1, "max": 8.0, "step": 0.05},
		"pure_continuous": {"kind": "check"},
		"base_mode": {"kind": "option", "options": ["COLOUR", "MONO STAMP"]},
		"base_opacity": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.05},
		"base_grade_amount": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.05},
		"grade_black_point": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"grade_white_point": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"grade_gamma": {"kind": "amount", "min": 0.2, "max": 4.0, "step": 0.05},
		"grade_contrast": {"kind": "amount", "min": 0.0, "max": 3.0, "step": 0.05},
		"grade_brightness": {"kind": "amount", "min": -1.0, "max": 1.0, "step": 0.05},
		"grade_saturation": {"kind": "amount", "min": 0.0, "max": 3.0, "step": 0.05},
		"source_pixel_size": {"kind": "amount", "min": 0.0, "max": 64.0, "step": 1.0, "unit": "px"},
		"source_pixel_units": {"kind": "option", "options": ["SOURCE PX", "PRESENTATION PX"]},
		"mono_threshold": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"mono_mode": {"kind": "option", "options": ["HARD", "BAYER", "CLUSTERED", "RANDOM", "CHECKER", "INVERSE HALFTONE"]},
		"mono_bayer_level": {"kind": "int", "min": 1.0, "max": 5.0, "step": 1.0},
		"mono_pixel": {"kind": "amount", "min": 0.0, "max": 32.0, "step": 1.0, "unit": "px"},
		"mono_space": {"kind": "option", "options": ["SOURCE", "ELEMENT", "SCREEN"]},
		"dither_threshold": {"kind": "compat", "note": "CT-10 LEGACY_DEAD_SURFACE"},
		"dither_black_point": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"dither_white_point": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"dither_gamma": {"kind": "amount", "min": 0.2, "max": 4.0, "step": 0.05},
		"dither_contrast": {"kind": "amount", "min": 0.0, "max": 3.0, "step": 0.05},
		"dither_brightness": {"kind": "amount", "min": -1.0, "max": 1.0, "step": 0.05},
		"dither_mode": {"kind": "option", "options": ["HARD", "BAYER", "CLUSTERED", "RANDOM", "CHECKER", "HALFTONE"]},
		"dither_bayer_level": {"kind": "int", "min": 1.0, "max": 5.0, "step": 1.0},
		"dither_pixel": {"kind": "amount", "min": 0.0, "max": 16.0, "step": 0.5, "unit": "px"},
		"dither_levels": {"kind": "int", "min": 2.0, "max": 16.0, "step": 1.0},
		"dither_space": {"kind": "option", "options": ["SOURCE", "ELEMENT", "SCREEN"]},
	}

static func field_meta_more() -> Dictionary:
	return {
		"edge_source_mode": {"kind": "option", "options": ["ALPHA", "LUMA", "BOTH"]},
		"edge_alpha_weight": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"edge_luma_weight": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"edge_threshold": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"edge_width": {"kind": "amount", "min": 0.0, "max": 48.0, "step": 0.5, "unit": "px"},
		"wind_reach": {"kind": "amount", "min": 0.0, "max": 120.0, "step": 1.0, "unit": "px"},
		"wind_trail": {"kind": "amount", "min": 0.0, "max": 2.0, "step": 0.05},
		"wind_cutoff": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"split_separation": {"kind": "amount", "min": 0.0, "max": 64.0, "step": 0.5, "unit": "px"},
		"wind_displace": {"kind": "amount", "min": 0.0, "max": 2.0, "step": 0.05},
		"signal_gain": {"kind": "amount", "min": 0.0, "max": 8.0, "step": 0.05},
		"color_blur": {"kind": "amount", "min": 0.0, "max": 64.0, "step": 0.5, "unit": "px"},
		"signal_softness": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"signal_posterize": {"kind": "amount", "min": 0.0, "max": 8.0, "step": 1.0},
		"fringe_coverage_mode": {"kind": "option", "options": ["SMOOTH", "BAYER", "CLUSTERED", "RANDOM", "CHECKER", "HALFTONE"]},
		"fringe_coverage_threshold": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"fringe_bayer_level": {"kind": "int", "min": 1.0, "max": 5.0, "step": 1.0},
		"fringe_pixel": {"kind": "amount", "min": 0.0, "max": 32.0, "step": 1.0, "unit": "px"},
		"fringe_space": {"kind": "option", "options": ["SOURCE", "ELEMENT", "SCREEN"]},
		"fringe_coverage_gain": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"rgb_gradient": {"kind": "amount", "min": -1.0, "max": 1.0, "step": 0.05},
		"rgb_gradient_balance": {"kind": "amount", "min": -1.0, "max": 1.0, "step": 0.05},
		"rgb_gradient_contrast": {"kind": "amount", "min": 0.0, "max": 3.0, "step": 0.05},
		"fringe_color_a": {"kind": "color"},
		"fringe_color_b": {"kind": "color"},
		"fringe_bleed": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.05},
		"fringe_blend_mode": {"kind": "option", "options": ["MIX", "ADD", "SCREEN"]},
		"geometry_units": {"kind": "option", "options": ["SOURCE PX", "PRESENTATION PX"]},
		"effect_mask_enabled": {"kind": "check"},
		"effect_mask_invert": {"kind": "check"},
		"effect_mask_threshold": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"effect_mask_softness": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"effect_mask_base": {"kind": "check"},
		"edge_mask_path": {"kind": "rejected", "note": "unwired custom edge source"},
		"treatment_mask_path": {"kind": "asset"},
		"driver_mode": {"kind": "option", "options": ["WHISP", "LEGACY FBM", "VORONOI", "PHASOR", "ISOLINE", "SPIRAL", "CURL SMOKE", "WAVEFRONT", "CELLULAR WIND", "RIDGE FLOW", "SOURCE WARP", "DATAMOSH RIVER", "MAGNETIC FIELD", "LIQUID SCANNER"]},
		"driver_sampling_mode": {"kind": "option", "options": ["FULL", "PIXELATED"]},
		"driver_pixel_size": {"kind": "amount", "min": 1.0, "max": 16.0, "step": 1.0, "unit": "px"},
		"FIELD_STRENGTH": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"FIELD_SPEED": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"OUTWARDNESS": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.05},
		"FIELD_BREAKUP": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.05},
		"COORD_NUDGE": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.05},
		"FIELD_SIZE": {"kind": "amount", "min": 0.1, "max": 4.0, "step": 0.05},
		"FIELD_CENTER_X": {"kind": "amount", "min": 0.0, "max": 3.0, "step": 0.05},
		"FIELD_CENTER_Y": {"kind": "amount", "min": 0.0, "max": 3.0, "step": 0.05},
		"LEGACY_SCALE": {"kind": "amount", "min": 0.0, "max": 20.0, "step": 0.1},
		"LEGACY_SPEED": {"kind": "amount", "min": 0.0, "max": 2.0, "step": 0.05},
		"LEGACY_RADIAL": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.05},
		"DRIVER_CENTER_X": {"kind": "amount", "min": 0.0, "max": 3.0, "step": 0.05},
		"DRIVER_CENTER_Y": {"kind": "amount", "min": 0.0, "max": 3.0, "step": 0.05},
		"DRIVER_SCALE": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"DRIVER_STRETCH": {"kind": "amount", "min": 0.0, "max": 2.0, "step": 0.05},
		"DRIVER_ANGLE": {"kind": "amount", "min": -180.0, "max": 180.0, "step": 1.0, "unit": "deg"},
		"DRIVER_SPEED": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"DRIVER_DETAIL": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.05},
		"DRIVER_FLOW": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.05},
		"flow_strength": {"kind": "amount", "min": 0.0, "max": 8.0, "step": 0.1},
		"flow_center_x": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"flow_center_y": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"rgb_shift_amount": {"kind": "amount", "min": 0.0, "max": 64.0, "step": 0.5, "unit": "px"},
		"rgb_shift_angle": {"kind": "amount", "min": -180.0, "max": 180.0, "step": 1.0, "unit": "deg"},
		"rgb_shift_units": {"kind": "option", "options": ["SOURCE PX", "PRESENTATION PX"]},
		"rgb_shift_alpha": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.05},
		"temporal_hold": {"kind": "amount", "min": 0.0, "max": 8.0, "step": 0.1, "unit": "s"},
		"palette_strategy": {"kind": "option", "options": ["DOMINANT + DISTANT", "COMPLEMENT", "SPLIT COMPLEMENT", "ANALOGOUS", "TRIADIC", "MONOCHROME"]},
		"palette_lock_a": {"kind": "check"},
		"palette_lock_b": {"kind": "check"},
		"palette_swap": {"kind": "check"},
		"palette_source_color": {"kind": "color"},
		"palette_hue_offset": {"kind": "amount", "min": -180.0, "max": 180.0, "step": 1.0, "unit": "deg"},
		"palette_saturation": {"kind": "amount", "min": 0.0, "max": 3.0, "step": 0.05},
		"palette_value": {"kind": "amount", "min": 0.0, "max": 2.0, "step": 0.05},
		"final_tint_amount": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01, "unit": "final"},
		"final_tint_color": {"kind": "color", "scope": "FINAL_COMPOSITE"},
		"operator": {"kind": "option", "options": ["NONE", "speedlines_field", "pattern_transition", "noise_erosion_border", "pixel_sort_smear", "vacuum_burst"]},
		"operator_secondary": {"kind": "option", "options": ["NONE", "speedlines_field", "pattern_transition", "vacuum_burst"]},
		"operator_strength": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"operator_scale": {"kind": "amount", "min": 0.25, "max": 4.0, "step": 0.05},
		"operator_speed": {"kind": "amount", "min": 0.0, "max": 4.0, "step": 0.05},
		"operator_threshold": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"operator_softness": {"kind": "amount", "min": 0.001, "max": 1.0, "step": 0.01},
		"operator_mix": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"operator_mix_mode": {"kind": "option", "options": ["LINES", "DISTORTION", "COMBINED"]},
		"operator_center_x": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"operator_center_y": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"operator_progress": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"operator_polarity": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"operator_axis_x": {"kind": "amount", "min": -1.0, "max": 1.0, "step": 0.01},
		"operator_axis_y": {"kind": "amount", "min": -1.0, "max": 1.0, "step": 0.01},
		"operator_pattern_mode": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 1.0},
		"operator_pattern_family": {"kind": "amount", "min": 0.0, "max": 2.0, "step": 1.0},
		"operator_distortion": {"kind": "amount", "min": 0.0, "max": 1.0, "step": 0.01},
		"operator_scope": {"kind": "option", "options": ["ALL", "ECHO_ONLY", "PRIMARY_ONLY", "EXCLUDE_PRIMARY"]},
		"operator_time_source": {"kind": "option", "options": ["PRESENTATION_TIME", "FREE_RUN"]},
		"operator_color_a": {"kind": "color"},
		"operator_color_b": {"kind": "color"},
		"time_source": {"kind": "option", "options": ["PRESENTATION_TIME", "FREE_RUN"]},
	}

static func field_meta_all() -> Dictionary:
	var out := field_meta()
	var more := field_meta_more()
	for key in more.keys():
		out[key] = more[key]
	return out

static func is_valid_look_id(look_id: String) -> bool:
	# Conservative file-safe id: letters, digits, underscore, dash; 1..80 chars;
	# must not start with a dot. R3 §23.
	if look_id.length() < 1 or look_id.length() > 80:
		return false
	if look_id.begins_with("."):
		return false
	for i in range(look_id.length()):
		var c := look_id[i]
		var is_ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
		if not is_ok:
			return false
	return true

static func _finite_number(value) -> bool:
	if value == null or value is bool:
		return false
	if value is Array or value is Dictionary:
		return false
	if value is String:
		# float("x") is 0.0 in GDScript: a non-numeric string must NOT pass as a
		# finite number (R3 §12 finding).
		var text := (value as String).strip_edges()
		if not text.is_valid_float():
			return false
		return is_finite(text.to_float())
	var f := float(value)
	return is_finite(f)

static func _sanitize_fx_values(fx: Dictionary) -> Dictionary:
	# R3 §12: every fx field must survive materialization as FINITE data or fall
	# back to its neutral. Numeric strings coerce; containers that are valid
	# numeric vectors (colour pairs) stay; everything else resets to the neutral
	# (or is dropped when the key is not part of the schema).
	var neutral: Dictionary = neutral_fx()
	var out: Dictionary = {}
	for key in fx.keys():
		var value = fx[key]
		var keep := false
		if value is float or value is int:
			keep = is_finite(float(value))
		elif value is String and (value as String).strip_edges().is_valid_float():
			var as_float := (value as String).to_float()
			keep = is_finite(as_float)
			if keep:
				value = as_float
		elif value is Array:
			keep = _finite_numbers(value)
		if keep:
			out[key] = value
		elif neutral.has(key):
			out[key] = neutral[key]
	return out

static func _finite_numbers(values: Array) -> bool:
	for value in values:
		if not _finite_number(value):
			return false
	return true

# ---------------------------------------------------------------- editing helpers

static func find_layer(doc: Dictionary, layer_id: String) -> Dictionary:
	for layer in doc.get("layers", []):
		if layer is Dictionary and str(layer.get("layer_id", "")) == layer_id:
			return layer
	return {}

# LG-02/LG-04/LG-05: document-level layer graph operations. Visual order IS
# document order, so moves mutate raw indices directly; SOURCE is pinned at
# root index 0 and refuses every reorder; drops never change planes.
static func move_layer_in(doc: Dictionary, layer_id: String, direction: int) -> bool:
	var layers: Array = doc.get("layers", [])
	var index := -1
	for i in range(layers.size()):
		if str((layers[i] as Dictionary).get("layer_id", "")) == layer_id:
			index = i
			break
	if index == -1:
		return false
	if str((layers[index] as Dictionary).get("type", "")) == TYPE_SOURCE:
		return false
	var target := index + direction
	if target < 0 or target >= layers.size():
		return false
	if str((layers[target] as Dictionary).get("type", "")) == TYPE_SOURCE:
		return false
	var moved: Dictionary = layers[index]
	layers.remove_at(index)
	layers.insert(target, moved)
	return true

static func reorder_layer_in(doc: Dictionary, drag_id: String, target_id: String) -> bool:
	if drag_id == target_id:
		return false
	var layers: Array = doc.get("layers", [])
	var from := -1
	var to := -1
	for i in range(layers.size()):
		var lid := str((layers[i] as Dictionary).get("layer_id", ""))
		if lid == drag_id:
			from = i
		if lid == target_id:
			to = i
	if from == -1 or to == -1:
		return false
	if str((layers[from] as Dictionary).get("type", "")) == TYPE_SOURCE:
		return false
	if str((layers[to] as Dictionary).get("type", "")) == TYPE_SOURCE:
		# SOURCE is pinned at 0: dropping "onto" it lands directly after.
		to = 1
		if from == 1:
			return false
	var moved: Dictionary = layers[from]
	layers.remove_at(from)
	if to > from:
		to -= 1
	layers.insert(to, moved)
	return true

static func set_layer_plane(doc: Dictionary, layer_id: String, plane: String) -> bool:
	var layer := find_layer(doc, layer_id)
	if layer.is_empty():
		return false
	if str(layer.get("type", "")) == TYPE_SOURCE:
		return false
	layer["plane"] = plane
	return true

static func source_layer(doc: Dictionary) -> Dictionary:
	for layer in doc.get("layers", []):
		if layer is Dictionary and str(layer.get("type", "")) == TYPE_SOURCE:
			return layer
	return {}

static func duplicate_layer_in(doc: Dictionary, layer_id: String, new_name := "") -> Dictionary:
	var layers: Array = doc.get("layers", [])
	for index in range(layers.size()):
		var layer: Dictionary = layers[index]
		if str(layer.get("layer_id", "")) != layer_id:
			continue
		var copy: Dictionary = layer.duplicate(true)
		copy["layer_id"] = next_layer_id(str(layer.get("type", "fx")).to_lower())
		copy["name"] = new_name if new_name != "" else str(layer.get("name", "Layer")) + " Copy"
		layers.insert(index + 1, copy)
		return copy
	return {}

static func reset_layer_in(doc: Dictionary, layer_id: String) -> bool:
	var layer := find_layer(doc, layer_id)
	if layer.is_empty():
		return false
	var type := str(layer.get("type", TYPE_FX))
	layer["enabled"] = true
	layer["locked"] = false
	layer["opacity"] = 1.0
	layer["blend_mode"] = "NORMAL"
	layer["transform"] = neutral_transform()
	layer["displacement"] = neutral_displacement()
	layer["mask"] = neutral_mask()
	layer["fx"] = neutral_fx()
	layer["motion"] = neutral_motion()
	if type == TYPE_FX:
		layer["input"] = "ORIGINAL_SOURCE"
	else:
		layer.erase("input")
	return true

static func set_look_status(doc: Dictionary, status: String) -> void:
	if status in STATUSES:
		doc["status"] = status

static func bump_revision(doc: Dictionary) -> int:
	doc["revision"] = int(doc.get("revision", 1)) + 1
	return int(doc["revision"])

# ---------------------------------------------------------------- ids / serialization

static func next_layer_id(prefix: String) -> String:
	_serial += 1
	return "layer-%s-%04d-%s" % [prefix.to_lower(), _serial, _hex(4)]

static func _hex(length: int) -> String:
	var out := ""
	for i in range(length):
		out += "0123456789abcdef"[randi() % 16]
	return out

static func to_json(doc: Dictionary) -> String:
	return JSON.stringify(doc, "  ", true)

static func from_json(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

static func is_serialized_normalized(doc: Dictionary) -> bool:
	# Numeric-type tolerant comparison: `revision: 1` and `revision: 1.0` are the
	# same normalized value (Godot's recursive container equality is type-strict,
	# JSON loading widens all numbers to float).
	if equivalent(materialize(doc), doc):
		return true
	# Lane metadata was added after the v0.4 production shape. An older document
	# that omits lane is still normalized when every omitted lane resolves to the
	# existing TARGET_LOCAL path; FINAL_COMPOSITE is never inferred.
	var normalized := materialize(doc)
	var legacy := doc.duplicate(true)
	var normalized_without_lane := normalized.duplicate(true)
	_strip_default_lanes(legacy)
	_strip_default_lanes(normalized_without_lane)
	return equivalent(normalized_without_lane, legacy) or _legacy_v03_shape_is_normalized(doc)

static func _strip_default_lanes(doc: Dictionary) -> void:
	for raw in doc.get("layers", []):
		if not (raw is Dictionary):
			continue
		var layer: Dictionary = raw
		if str(layer.get("lane", "")) == "TARGET_LOCAL":
			layer.erase("lane")

static func _legacy_v03_shape_is_normalized(doc: Dictionary) -> bool:
	# vNEXT 0.1/0.2 looks used the serialized `fx_size`/`fx_intensity`
	# aliases. They were already canonical for that schema; accepting them here
	# keeps old planning documents loadable while materialize() upgrades them.
	var layers = doc.get("layers", [])
	if not (layers is Array) or (layers as Array).is_empty():
		return false
	var saw_legacy: bool = false
	for layer_value in layers:
		if not (layer_value is Dictionary):
			return false
		var layer: Dictionary = layer_value
		var fx = layer.get("fx", {})
		if fx is Dictionary and ((fx as Dictionary).has("fx_size") or (fx as Dictionary).has("fx_intensity")):
			saw_legacy = true
	return saw_legacy

static func equivalent(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for key in da.keys():
			if not db.has(key):
				return false
			if not equivalent(da[key], db[key]):
				return false
		return true
	if a is Array and b is Array:
		var aa: Array = a
		var ba: Array = b
		if aa.size() != ba.size():
			return false
		for i in range(aa.size()):
			if not equivalent(aa[i], ba[i]):
				return false
		return true
	if a == null or b == null:
		return a == null and b == null
	if a is bool or b is bool:
		return (a is bool) and (b is bool) and a == b
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	return a == b
