class_name FxMigration
extends RefCounted
# NRCU FX Lab vNext — v0.3 → vNext migration (specs/08).
#
# Additive and reversible: v0.3 source documents are never mutated; migration
# produces v0.4 Looks (SOURCE + "Legacy v0.3 Treatment" FX layer) plus v2
# assignment documents. Semantics that cannot be represented exactly are NOT
# approximated silently — the migrated Look is marked
# `MIGRATION_REVIEW_REQUIRED` and every mismatch is explained in
# `metadata.migration_notes` (specs/08 §5).
#
# Mapping reference (v0.3 look state -> v0.4 layer fx dict):
#   fx_on.{dither,rgb,fringe} + fx_amount.* -> fx.dither / fx.rgb / fx.fringe
#   fx_intensity, fx_size, pattern_scale, pure_continuous
#   edge_* / wind_* / split_separation / signal_* / color_blur
#   fringe_* (bleed/blend/coverage/pixel/space/bayer) -> coverage_* / fringe_*
#   rgb_shift_* -> rgb_shift / rgb_angle / rgb_alpha
#   dither_* (mode/levels/pixel/space/bayer/black/white/gamma/contrast/brightness)
#   col_a / col_b -> fringe_color_a / fringe_color_b
#
# Legacy limits (review-required when engaged): flow distortion, effect mask,
# base/grade/palette/mono semantics, v0.3 motion tracks, custom mask assets.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")

const V03_LOOK_SCHEMA := "NRCU_FX_LOOK_V0_3"
const V03_ASSIGNMENTS_SCHEMA := "NRCU_VS_FX_ASSIGNMENTS_V1"
const LEGACY_LAYER_NAME := "Legacy v0.3 Treatment"

# ---------------------------------------------------------------- looks

func migrate_looks_document(doc: Dictionary) -> Dictionary:
	if not (doc.get("looks") is Dictionary):
		return {"ok": false, "looks": {}, "reviews": {}, "errors": ["v0.3 document has no looks object"]}
	var looks: Dictionary = {}
	var reviews: Dictionary = {}
	var errors: Array = []
	for look_id in (doc["looks"] as Dictionary).keys():
		var raw = (doc["looks"] as Dictionary)[look_id]
		if not (raw is Dictionary):
			errors.append("look %s: not an object" % str(look_id))
			continue
		var result := migrate_look(str(look_id), raw)
		if not bool(result["ok"]):
			errors.append_array(result["errors"])
			continue
		looks[str(look_id)] = result["look"]
		if bool(result["review_required"]):
			reviews[str(look_id)] = result["notes"]
	return {"ok": errors.is_empty(), "looks": looks, "reviews": reviews, "errors": errors}

func migrate_look(look_id: String, v03: Dictionary) -> Dictionary:
	var errors: Array = []
	if str(v03.get("look_schema", "")) != V03_LOOK_SCHEMA:
		return {"ok": false, "errors": ["look %s: unexpected schema %s" % [look_id, str(v03.get("look_schema", ""))]]}
	var state: Dictionary = (v03.get("state", {}) as Dictionary).duplicate(true) if v03.get("state") is Dictionary else {}
	for root_key in ["edge_mask_path", "treatment_mask_path", "custom_mask", "palette_source_color", "fringe_color_a", "fringe_color_b"]:
		if v03.has(root_key) and not state.has(root_key):
			state[root_key] = v03[root_key]
	if state.is_empty():
		return {"ok": false, "errors": ["look %s: empty state" % look_id]}

	var review_notes := _review_notes(look_id, v03, state)

	# --- v0.4 documents: SOURCE + Legacy FX layer (specs/08 §2).
	var doc := FxLookScript.new_look(look_id, look_id)
	var fx_layer := FxLookScript.new_layer("FX", LEGACY_LAYER_NAME)
	fx_layer["input"] = "ORIGINAL_SOURCE"
	fx_layer["plane"] = "TARGET_SOURCE"
	fx_layer["fx"] = _fx_from_state(state)
	fx_layer["motion"] = _motion_from_v03(v03)
	doc["layers"].append(fx_layer)
	var source_layer: Dictionary = doc["layers"][0]
	source_layer["name"] = "Source"
	doc["status"] = "MIGRATION_REVIEW_REQUIRED" if not review_notes.is_empty() else "PRODUCTION"
	doc["metadata"] = {
		"migrated_from": {
			"schema": V03_LOOK_SCHEMA,
			"look_id": look_id,
			"source_status": str(v03.get("status", "")),
			"time_source": str(v03.get("time_source", "")),
		},
		"migration_notes": review_notes.duplicate(),
	}

	var check: Dictionary = FxLookScript.validate(doc)
	if not bool(check["ok"]):
		return {"ok": false, "errors": ["look %s: migrated document invalid: %s" % [look_id, str(check["errors"])]]}

	return {
		"ok": true,
		"look": doc,
		"review_required": not review_notes.is_empty(),
		"notes": review_notes,
		"errors": errors,
	}

func _fx_from_state(state: Dictionary) -> Dictionary:
	var fx: Dictionary = FxLookScript.neutral_fx()
	var fx_on: Dictionary = state.get("fx_on", {}) if state.get("fx_on") is Dictionary else {}
	var amount: Dictionary = state.get("fx_amount", {}) if state.get("fx_amount") is Dictionary else {}
	for domain: String in ["dither", "fringe", "flow", "rgb"]:
		fx[domain] = float(amount.get(domain, 1.0)) if bool(fx_on.get(domain, false)) else 0.0

	# Preserve the complete scalar v0.3 surface. These names are deliberately
	# identical to the vNEXT shader/model keys; a missing key here silently
	# reverts to the shader default and changes an otherwise valid saved look.
	for key: String in [
		"size", "intensity", "pattern_scale", "source_pixel_size", "source_pixel_units",
		"base_mode", "base_opacity", "base_grade_amount", "grade_black_point", "grade_white_point",
		"grade_gamma", "grade_contrast", "grade_brightness", "grade_saturation",
		"mono_threshold", "mono_mode", "mono_bayer_level", "mono_pixel", "mono_space",
		"dither_threshold", "dither_black_point", "dither_white_point", "dither_gamma",
		"dither_contrast", "dither_brightness", "dither_mode", "dither_bayer_level", "dither_pixel",
		"dither_levels", "dither_space", "edge_source_mode", "edge_alpha_weight", "edge_luma_weight",
		"edge_threshold", "edge_width", "wind_reach", "wind_trail", "wind_cutoff", "split_separation",
		"wind_displace", "signal_gain", "color_blur", "signal_softness", "signal_posterize",
		"fringe_coverage_mode", "fringe_coverage_threshold", "fringe_bayer_level", "fringe_pixel",
		"fringe_space", "fringe_coverage_gain", "rgb_gradient", "rgb_gradient_balance",
		"rgb_gradient_contrast", "fringe_bleed", "fringe_blend_mode", "geometry_units",
		"effect_mask_threshold", "effect_mask_softness", "driver_mode", "driver_sampling_mode",
		"driver_pixel_size", "FIELD_STRENGTH", "FIELD_SPEED", "OUTWARDNESS", "FIELD_BREAKUP",
		"COORD_NUDGE", "FIELD_SIZE", "FIELD_CENTER_X", "FIELD_CENTER_Y", "LEGACY_SCALE",
		"LEGACY_SPEED", "LEGACY_RADIAL", "DRIVER_CENTER_X", "DRIVER_CENTER_Y", "DRIVER_SCALE",
		"DRIVER_STRETCH", "DRIVER_ANGLE", "DRIVER_SPEED", "DRIVER_DETAIL", "DRIVER_FLOW",
		"flow_strength", "flow_center_x", "flow_center_y", "rgb_shift_amount", "rgb_shift_angle",
		"rgb_shift_units", "rgb_shift_alpha", "temporal_hold", "palette_strategy", "palette_hue_offset",
		"palette_saturation", "palette_value"]:
		if state.has(key):
			fx[key] = float(state[key])
	fx["size"] = float(state.get("fx_size", fx["size"]))
	fx["intensity"] = float(state.get("fx_intensity", fx["intensity"]))
	# Legacy v0.3 spellings are consumed into their canonical v0.4 keys when
	# the canonical key is absent; they are never re-emitted (validate_input
	# rejects legacy aliases in persisted documents).
	for pair in [["rgb_shift", "rgb_shift_amount"], ["rgb_angle", "rgb_shift_angle"], ["rgb_alpha", "rgb_shift_alpha"], ["fringe_blend", "fringe_blend_mode"]]:
		if not state.has(pair[1]) and state.has(pair[0]):
			fx[pair[1]] = float(state[pair[0]])

	fx["pure_continuous"] = bool(state.get("pure_continuous", false))
	fx["effect_mask_enabled"] = bool(state.get("effect_mask_enabled", false))
	fx["effect_mask_invert"] = bool(state.get("effect_mask_invert", false))
	fx["effect_mask_base"] = bool(state.get("effect_mask_base", false))
	fx["edge_mask_path"] = str(state.get("edge_mask_path", ""))
	fx["treatment_mask_path"] = str(state.get("treatment_mask_path", ""))
	fx["palette_lock_a"] = bool(state.get("palette_lock_a", false))
	fx["palette_lock_b"] = bool(state.get("palette_lock_b", false))
	# v0.3 stores the result of SWAP in col_a/col_b, but accept an explicit
	# flag from newer exports too. Both representations remain reversible.
	fx["palette_swap"] = bool(state.get("palette_swap", state.get("palette_swapped", false)))
	fx["palette_source_color"] = _color_array(state.get("palette_source_color", [0.5, 0.5, 0.5, 1.0]))
	fx["fringe_color_a"] = _color_array(state.get("col_a", [0.25, 0.95, 1.0, 1.0]))
	fx["fringe_color_b"] = _color_array(state.get("col_b", [1.0, 0.4, 0.85, 1.0]))

	var legacy_time_source := str(state.get("time_source", "PRESENTATION TIME")).to_upper().replace(" ", "_")
	fx["time_source"] = "FREE_RUN" if legacy_time_source == "FREE_RUN" else "PRESENTATION_TIME"
	return fx

func _motion_from_v03(v03: Dictionary) -> Dictionary:
	var out: Dictionary = FxLookScript.neutral_motion()
	var enabled: Dictionary = v03.get("motion_enabled", {}) if v03.get("motion_enabled") is Dictionary else {}
	var incoming: Dictionary = v03.get("motion", {}) if v03.get("motion") is Dictionary else {}
	for domain: String in ["dither", "fringe", "flow", "rgb"]:
		out["enabled"][domain] = bool(enabled.get(domain, false))
		var raw = incoming.get(domain, {})
		if not (raw is Dictionary):
			continue
		var track: Dictionary = out["tracks"][domain]
		for key: String in ["anchor", "anchor_time", "delay", "attack", "hold", "release", "sustain", "attack_curve", "release_curve"]:
			if (raw as Dictionary).has(key):
				track[key] = (raw as Dictionary)[key]
		for key: String in ["anchor_time", "delay", "attack", "hold", "release", "sustain"]:
			track[key] = float(track.get(key, 0.0))
		track["anchor"] = str(track.get("anchor", "manual"))
		track["attack_curve"] = str(track.get("attack_curve", "cubic_out"))
		track["release_curve"] = str(track.get("release_curve", "sine_in_out"))
	return out

func _color_array(value) -> Array:
	var out := [0.25, 0.95, 1.0, 1.0]
	if value is Array and (value as Array).size() >= 3:
		var src: Array = value
		out[0] = float(src[0])
		out[1] = float(src[1])
		out[2] = float(src[2])
		if src.size() > 3:
			out[3] = float(src[3])
	return out

func _review_notes(look_id: String, v03: Dictionary, state: Dictionary) -> Array:
	var notes: Array = []
	var fx_on: Dictionary = state.get("fx_on", {})
	var amount: Dictionary = state.get("fx_amount", {})

	# Flow is now carried into the vNEXT driver domain. Keep the existing
	# review marker for engaged legacy distortion because its source-space
	# sampling needs a visual parity check even though no data is discarded.
	if bool(fx_on.get("flow", false)) and float(amount.get("flow", 1.0)) > 0.0001:
		notes.append("flow distortion (strength %.2f) migrated to the vNEXT flow domain; verify source-space parity" % float(state.get("flow_strength", 0.0)))

	# Flow, base treatment, mono, palette, dither, RGB and motion envelopes
	# are represented directly in the vNEXT layer schema. Only legacy assets or
	# coordinate systems that still need a human decision remain review notes.

	# Custom mask assets.
	for key in ["edge_mask_path", "treatment_mask_path"]:
		var path_text := str(v03.get(key, ""))
		if path_text != "":
			notes.append("custom mask asset '%s' was not imported; reattach it in the Inspector" % path_text)

	# Spatial pixel units: v0.3 'source' space differs from v0.4 presentation
	# px when the source scale is not 1:1 — note it for awareness.
	if absf(float(state.get("geometry_units", 1.0)) - 1.0) > 0.0001:
		notes.append("v0.3 geometry unit setting differs from the v0.4 presentation-px default")
	return notes

# ---------------------------------------------------------------- assignments

func migrate_assignments(v01: Dictionary) -> Dictionary:
	# specs/08 §3: keep selector meaning; add neutral v2 fields.
	var errors: Array = []
	if str(v01.get("schema", "")) != V03_ASSIGNMENTS_SCHEMA:
		return {"ok": false, "doc": {}, "errors": ["assignments: unexpected schema %s" % str(v01.get("schema", ""))]}
	var doc: Dictionary = FxResolverScript.new_assignments()
	for raw in v01.get("bindings", []):
		if not (raw is Dictionary):
			errors.append("bindings: entry is not an object")
			continue
		var binding: Dictionary = raw
		var selector := FxResolverScript.normalize_selector(binding.get("selector", {}))
		if selector.is_empty():
			errors.append("binding for look %s has an empty selector" % str(binding.get("look_id", "")))
			continue
		FxResolverScript.upsert_binding(doc, selector, str(binding.get("look_id", "")), "migrated from v0.3")
	var check: Dictionary = FxResolverScript.validate_assignments(doc)
	if not bool(check["ok"]):
		errors.append_array(check["errors"])
	return {"ok": errors.is_empty(), "doc": doc, "errors": errors}
