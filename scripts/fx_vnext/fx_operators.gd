class_name FxOperators
extends RefCounted
# NRCU FX Lab vNext — Phase 8 supplemental-operator contract.
#
# This is a capability registry, not a claim that every named effect is a
# standalone implementation. Existing shader/model primitives are explicitly
# marked ADAPTER_ONLY. DEFERRED_3D remains fail-closed until a real
# implementation and evidence reference exist.

const CONTRACT_VERSION := "NRCU_FX_OPERATORS_V1"
const FINAL_COMPOSITE_SHADER_PATH := "res://shaders/nrcu_fx_vnext_final_composite.gdshader"
const SCOPES := ["LOCAL", "FINAL_COMPOSITE", "DEFERRED_3D"]
const LANES := ["TARGET_LOCAL", "FINAL_COMPOSITE", "DEFERRED_3D"]
const TIME_SOURCES := ["PRESENTATION_TIME", "FREE_RUN"]
const GOLD_ROUNDTRIP_EVIDENCE := "tests/fx_vnext_gold_production_roundtrip_test.gd"
const GOLD_OPERATOR_IDS := ["speedlines_field", "pattern_transition", "vacuum_burst", "noise_erosion_border", "pixel_sort_smear"]
const COST_CLASSES := ["NONE", "LOW", "MEDIUM", "HIGH", "DEFERRED"]
const STATUSES := ["ADAPTER_ONLY", "SUPPORTED", "UNSUPPORTED", "DEFERRED"]

# Stable order is part of the contract. Do not derive this from Dictionary
# iteration or from the order in which a shader happens to expose uniforms.
const NAMED_OPERATOR_IDS := [
	"source_copy",
	"transform",
	"displacement",
	"mask",
	"base_treatment",
	"grade",
	"source_pixelation",
	"mono_stamp",
	"dither",
	"palette",
	"edge",
	"fringe",
	"rgb",
	"flow",
	"motion_envelope",
	"manga_impact",
	"speedlines_field",
	"pattern_transition",
	"vacuum_burst",
	"pixel_sort_smear",
	"perimeter_flux",
	"noise_erosion_border",
	"contour_pulse",
	"silhouette_extrude",
	"print_misregistration",
	"halftone_reveal",
	"dither_inversion",
	"slice_tear",
	"hit_flash",
	"mesh_smear",
	"multi_impact_field",
	"slash_arc",
	"world_outline_depth",
	"world_outline_depth_normal",
	"final_composite",
	"deferred_3d",
]

const COST_WEIGHT_BY_CLASS := {
	"NONE": 0.0,
	"LOW": 0.5,
	"MEDIUM": 1.0,
	"HIGH": 2.0,
	"DEFERRED": 0.0,
}

static var _registry_cache: Dictionary = {}

static func operator_ids() -> Array:
	return NAMED_OPERATOR_IDS.duplicate()

static func named_operator_ids() -> Array:
	return operator_ids()

static func registry() -> Dictionary:
	if _registry_cache.is_empty():
		_registry_cache = _build_registry()
	return _registry_cache.duplicate(true)

static func entries() -> Array:
	var out: Array = []
	for operator_id in NAMED_OPERATOR_IDS:
		out.append(registry()[str(operator_id)])
	return out

static func has_operator(operator_id: String) -> bool:
	return registry().has(operator_id)

static func operator_entry(operator_id: String) -> Dictionary:
	return registry().get(operator_id, {}).duplicate(true)

static func validate_registry() -> Dictionary:
	var errors: Array = []
	var required := [
		"operator_id", "scope", "time_source", "time_source_support",
		"neutral_proven", "authoring_reachable", "persistence_proven",
		"runtime_observable", "cost_class", "test_evidence_reference",
		"semantic_notes", "status", "lane",
	]
	var rows := registry()
	if rows.size() != NAMED_OPERATOR_IDS.size():
		errors.append("registry size does not match stable operator id list")
	for operator_id in NAMED_OPERATOR_IDS:
		var row: Dictionary = rows.get(str(operator_id), {})
		for key in required:
			if not row.has(key):
				errors.append("%s missing %s" % [str(operator_id), key])
		if str(row.get("operator_id", "")) != str(operator_id):
			errors.append("operator id mismatch: %s" % str(operator_id))
		if str(row.get("scope", "")) not in SCOPES:
			errors.append("invalid scope: %s" % str(operator_id))
		if str(row.get("lane", "")) not in LANES:
			errors.append("invalid lane: %s" % str(operator_id))
		var expected_lane := "TARGET_LOCAL" if str(row.get("scope", "")) == "LOCAL" else str(row.get("scope", ""))
		if str(row.get("lane", "")) != expected_lane:
			errors.append("scope/lane mismatch: %s" % str(operator_id))
		if str(row.get("time_source", "")) not in TIME_SOURCES:
			errors.append("invalid default time source: %s" % str(operator_id))
		if not (row.get("time_source_support", []) is Array) or (row.get("time_source_support", []) as Array).is_empty():
			errors.append("missing time-source support: %s" % str(operator_id))
		else:
			for source in row.get("time_source_support", []):
				if str(source) not in TIME_SOURCES:
					errors.append("invalid time-source support: %s" % str(operator_id))
		if str(row.get("status", "")) not in STATUSES:
			errors.append("invalid status: %s" % str(operator_id))
		if str(row.get("scope", "")) == "LOCAL" and str(row.get("status", "")) not in ["ADAPTER_ONLY", "UNSUPPORTED"]:
			errors.append("local operator has an invalid status: %s" % str(operator_id))
		if str(row.get("scope", "")) == "FINAL_COMPOSITE":
			var expected_final_status := "SUPPORTED" if ((operator_id == "final_composite" and final_composite_supported()) or (operator_id in GOLD_OPERATOR_IDS and bool(row.get("authoring_reachable", false)) and bool(row.get("persistence_proven", false)) and bool(row.get("runtime_observable", false)))) else "UNSUPPORTED"
			if str(row.get("status", "")) != expected_final_status:
				errors.append("final-composite operator status is not truthful: %s" % operator_id)
		if str(row.get("scope", "")) == "DEFERRED_3D" and str(row.get("status", "")) != "DEFERRED":
			errors.append("3D operator must be classified DEFERRED: %s" % str(operator_id))
		if str(row.get("status", "")) == "SUPPORTED" and operator_id != "final_composite" and operator_id not in GOLD_OPERATOR_IDS:
			errors.append("only final_composite may be SUPPORTED: %s" % operator_id)
		if str(row.get("status", "")) in ["UNSUPPORTED", "DEFERRED"] and bool(row.get("runtime_observable", false)):
			errors.append("unsupported/deferred operator claims runtime proof: %s" % str(operator_id))
		if str(row.get("cost_class", "")) not in COST_CLASSES:
			errors.append("invalid cost class: %s" % str(operator_id))
		for flag in ["neutral_proven", "authoring_reachable", "persistence_proven", "runtime_observable"]:
			if not (row.get(flag) is bool):
				errors.append("non-boolean capability flag %s: %s" % [flag, str(operator_id)])
		if str(row.get("semantic_notes", "")).strip_edges() == "":
			errors.append("missing semantic notes: %s" % str(operator_id))
		if str(row.get("test_evidence_reference", "")).strip_edges() == "":
			errors.append("missing evidence reference: %s" % str(operator_id))
		if GOLD_OPERATOR_IDS.has(str(operator_id)) and bool(row.get("persistence_proven", false)):
			var evidence := str(row.get("test_evidence_reference", ""))
			if not evidence.contains(GOLD_ROUNDTRIP_EVIDENCE):
				errors.append("gold persistence flag lacks production roundtrip evidence: %s" % str(operator_id))
	return {"ok": errors.is_empty(), "errors": errors}

static func cost_for_operator(operator_id: String) -> float:
	var entry := operator_entry(operator_id)
	return float(COST_WEIGHT_BY_CLASS.get(str(entry.get("cost_class", "NONE")), 0.0)) if not entry.is_empty() else 0.0

static func final_composite_supported() -> bool:
	# Capability is tied to the dedicated shader resource. There is no plane
	# alias or fallback path that can make a target-local quad count as final.
	if not ResourceLoader.exists(FINAL_COMPOSITE_SHADER_PATH):
		return false
	return load(FINAL_COMPOSITE_SHADER_PATH) is Shader

static func clock_contract() -> Dictionary:
	return {
		"time_sources": TIME_SOURCES.duplicate(),
		"raw_builtin_allowed": false,
		"supplied_uniform": "supplied_time",
		"final_presentation_uniform": "presentation_time",
		"final_free_run_uniform": "free_run_time",
		"presentation_name": "PRESENTATION_TIME",
		"free_run_name": "FREE_RUN",
	}

static func neutral_contract_ok() -> bool:
	for operator_id in NAMED_OPERATOR_IDS:
		var entry: Dictionary = registry()[str(operator_id)]
		if not (entry.get("neutral_proven", false) is bool):
			return false
		if not bool(entry.get("neutral_proven", false)):
			return false
		if str(entry.get("scope", "")) not in SCOPES:
			return false
		if str(entry.get("status", "")) in ["UNSUPPORTED", "DEFERRED"] and bool(entry.get("runtime_observable", false)):
			return false
	return true

# Existing planes intentionally remain on the existing target-local renderer
# path. A plane name is not permission to claim final-frame composition.
static func lane_for_plane(plane: String, requested_lane := "") -> String:
	if requested_lane != "":
		return requested_lane
	if plane in ["COMPOSITION_BACKGROUND", "TARGET_UNDERLAY", "TARGET_SOURCE", "TARGET_OVERLAY", "COMPOSITION_FOREGROUND"]:
		return "TARGET_LOCAL"
	return ""

static func lane_for_layer(layer: Dictionary) -> String:
	return lane_for_plane(str(layer.get("plane", "TARGET_SOURCE")), str(layer.get("lane", "")))

static func validate_layer_lane(layer: Dictionary) -> Dictionary:
	var plane := str(layer.get("plane", "TARGET_SOURCE"))
	var requested := str(layer.get("lane", ""))
	var lane := lane_for_plane(plane, requested)
	var errors: Array = []
	var supported := true
	if lane == "":
		errors.append("lane: missing or invalid for plane %s" % plane)
		supported = false
	elif lane not in LANES:
		errors.append("lane: invalid %s" % lane)
		supported = false
	# COMPOSITION_BACKGROUND remains a source-local placement plane and cannot
	# masquerade as a post-composition pass. COMPOSITION_FOREGROUND is the
	# explicit ownership plane for full-frame FINAL_COMPOSITE authority.
	if plane == "COMPOSITION_BACKGROUND" and lane == "FINAL_COMPOSITE":
		errors.append("plane %s cannot be represented as FINAL_COMPOSITE" % plane)
		supported = false
	if lane == "FINAL_COMPOSITE":
		if str(layer.get("authority", "")) != "COMPOSITION":
			errors.append("FINAL_COMPOSITE requires COMPOSITION authority")
			supported = false
		if not final_composite_supported():
			errors.append("FINAL_COMPOSITE lane is unsupported: dedicated full-frame shader path is unavailable")
			supported = false
	elif lane == "DEFERRED_3D":
		errors.append("DEFERRED_3D lane is deferred: no 3D operator path")
		supported = false
	return {"ok": errors.is_empty(), "supported": supported, "lane": lane, "plane": plane, "errors": errors}

static func operator_ids_for_layer(layer: Dictionary) -> Array:
	var ids: Array = []
	if lane_for_layer(layer) == "FINAL_COMPOSITE":
		ids.append("final_composite")
	var layer_type := str(layer.get("type", ""))
	if layer_type == "SOURCE_COPY":
		ids.append("source_copy")
	elif layer_type != "FX":
		return ids
	var transform: Dictionary = layer.get("transform", {}) if layer.get("transform", {}) is Dictionary else {}
	if not _neutral_transform(transform):
		ids.append("transform")
	var displacement: Dictionary = layer.get("displacement", {}) if layer.get("displacement", {}) is Dictionary else {}
	if bool(displacement.get("enabled", false)):
		ids.append("displacement")
		if str(displacement.get("driver", "")) == "FRINGE_DRIVER":
			ids.append("flow")
	var mask: Dictionary = layer.get("mask", {}) if layer.get("mask", {}) is Dictionary else {}
	if bool(mask.get("enabled", false)):
		ids.append("mask")
	var fx: Dictionary = layer.get("fx", {}) if layer.get("fx", {}) is Dictionary else {}
	var named_operator := str(fx.get("operator", "NONE"))
	if named_operator != "" and named_operator != "NONE":
		ids.append(named_operator)
	var secondary_operator := str(fx.get("operator_secondary", "NONE"))
	if secondary_operator != "" and secondary_operator != "NONE":
		ids.append(secondary_operator)
	if _active_base(fx):
		ids.append("base_treatment")
	if _active_grade(fx):
		ids.append("grade")
	if float(fx.get("source_pixel_size", 0.0)) > 0.001:
		ids.append("source_pixelation")
	if float(fx.get("base_mode", 0.0)) > 0.5 or _active_mono(fx):
		ids.append("mono_stamp")
	if float(fx.get("dither", 0.0)) > 0.001:
		ids.append("dither")
	if _active_palette(fx):
		ids.append("palette")
	if float(fx.get("fringe", 0.0)) > 0.001:
		ids.append("edge")
		ids.append("fringe")
	if float(fx.get("rgb", 0.0)) > 0.001:
		ids.append("rgb")
	if float(fx.get("flow", fx.get("fx_flow", 0.0))) > 0.001:
		ids.append("flow")
	var motion: Dictionary = layer.get("motion", {}) if layer.get("motion", {}) is Dictionary else {}
	var enabled: Dictionary = motion.get("enabled", {}) if motion.get("enabled", {}) is Dictionary else {}
	for domain in ["dither", "fringe", "flow", "rgb"]:
		if bool(enabled.get(domain, false)):
			ids.append("motion_envelope")
			break
	ids.sort()
	var unique: Array = []
	for operator_id in ids:
		if not unique.has(operator_id):
			unique.append(operator_id)
	return unique

static func operator_costs_for_layer(layer: Dictionary) -> Dictionary:
	var costs: Dictionary = {}
	for operator_id in operator_ids_for_layer(layer):
		costs[str(operator_id)] = cost_for_operator(str(operator_id))
	return costs

static func _build_registry() -> Dictionary:
	var rows: Array = [
		_row("source_copy", "LOCAL", ["PRESENTATION_TIME"], true, true, true, true, "LOW", "tests/fx_vnext_operator_foundation_test.gd#registry", "SOURCE_COPY is a current vNext quad adapter; standalone operator parity is not claimed."),
		_row("transform", "LOCAL", ["PRESENTATION_TIME"], true, true, true, true, "LOW", "tests/fx_vnext_operator_foundation_test.gd#registry", "Transform is wired through the shared layer shader as a local adapter."),
		_row("displacement", "LOCAL", ["PRESENTATION_TIME", "FREE_RUN"], true, true, true, true, "MEDIUM", "tests/fx_vnext_temporal_model_test.gd#TM-03", "Displacement accepts the supplied presentation/free-run clock; this is not a final-composite proof."),
		_row("mask", "LOCAL", ["PRESENTATION_TIME"], true, true, true, true, "MEDIUM", "tests/fx_vnext_asset_truth_test.gd", "Mask semantics are local source/layer/presentation-space adapters with fail-closed asset validation."),
		_row("base_treatment", "LOCAL", ["PRESENTATION_TIME"], true, true, true, true, "MEDIUM", "tests/fx_vnext_capability_parity_test.gd", "Base treatment is exposed by the existing FX shader adapter; no independent operator boundary is claimed."),
		_row("grade", "LOCAL", ["PRESENTATION_TIME"], true, true, true, true, "LOW", "tests/fx_vnext_capability_parity_test.gd", "Grade fields are persisted and shader-visible through the current local adapter."),
		_row("source_pixelation", "LOCAL", ["PRESENTATION_TIME"], true, true, true, true, "LOW", "tests/fx_vnext_capability_parity_test.gd", "Source pixelation is a local shader stage, not a standalone post-composite pass."),
		_row("mono_stamp", "LOCAL", ["PRESENTATION_TIME"], true, true, true, true, "MEDIUM", "tests/fx_vnext_capability_parity_test.gd", "Mono stamp is currently represented by base-mode shader parameters."),
		_row("dither", "LOCAL", ["PRESENTATION_TIME", "FREE_RUN"], true, true, true, true, "MEDIUM", "tests/fx_vnext_operator_foundation_test.gd#clock", "Dither remains target-local; time-dependent paths must use supplied clocks and never raw TIME."),
		_row("palette", "LOCAL", ["PRESENTATION_TIME"], true, true, true, true, "LOW", "tests/fx_vnext_palette_contract_test.gd", "Palette authoring/persistence is current vNext behavior; its visible result is still an adapter composition."),
		_row("edge", "LOCAL", ["PRESENTATION_TIME", "FREE_RUN"], true, true, true, true, "MEDIUM", "tests/fx_vnext_capability_parity_test.gd", "Edge extraction is local to the source texture and shares the current fringe adapter."),
		_row("fringe", "LOCAL", ["PRESENTATION_TIME", "FREE_RUN"], true, true, true, true, "MEDIUM", "tests/fx_vnext_capability_parity_test.gd", "Fringe/driver motion is a local adapter; runtime evidence does not prove final-frame scope."),
		_row("rgb", "LOCAL", ["PRESENTATION_TIME", "FREE_RUN"], true, true, true, true, "MEDIUM", "tests/fx_vnext_capability_parity_test.gd", "RGB separation is applied on a target-local sampled quad."),
		_row("flow", "LOCAL", ["PRESENTATION_TIME", "FREE_RUN"], true, true, true, true, "MEDIUM", "tests/fx_vnext_capability_parity_test.gd", "Flow/driver motion is local and clocked by supplied uniforms."),
		_row("motion_envelope", "LOCAL", ["PRESENTATION_TIME"], true, true, true, true, "LOW", "tests/fx_vnext_temporal_model_test.gd#TM-03", "Motion envelopes modulate local adapter amounts; event authority remains presentation-owned."),
		_row("manga_impact", "FINAL_COMPOSITE", ["PRESENTATION_TIME", "FREE_RUN"], true, false, false, false, "NONE", "tests/fx_vnext_operator_foundation_test.gd#supplemental_registry", "Global final-frame manga impact candidate; no dedicated implementation or runtime evidence exists in this repository.", "UNSUPPORTED"),
		_row("speedlines_field", "FINAL_COMPOSITE", ["PRESENTATION_TIME", "FREE_RUN"], true, true, true, true, "MEDIUM", GOLD_ROUNDTRIP_EVIDENCE + "#KINETIC_RUSH", "Dedicated radial speedlines field in the FINAL_COMPOSITE shader; driven by supplied presentation/free-run clocks and production roundtrip evidence.", "SUPPORTED"),
		_row("pattern_transition", "FINAL_COMPOSITE", ["PRESENTATION_TIME", "FREE_RUN"], true, true, true, true, "MEDIUM", GOLD_ROUNDTRIP_EVIDENCE + "#PATTERN_CUT", "Dedicated geometric pattern transition over the captured final frame; driven by supplied clocks and production roundtrip evidence.", "SUPPORTED"),
		_row("vacuum_burst", "FINAL_COMPOSITE", ["PRESENTATION_TIME", "FREE_RUN"], true, true, true, true, "HIGH", GOLD_ROUNDTRIP_EVIDENCE + "#VACUUM_CLASH", "Dedicated radial screen-space vacuum warp and burst ring in FINAL_COMPOSITE with production roundtrip evidence.", "SUPPORTED"),
		_row("perimeter_flux", "LOCAL", ["PRESENTATION_TIME", "FREE_RUN"], true, false, false, false, "NONE", "tests/fx_vnext_operator_foundation_test.gd#supplemental_registry", "Frame/UV/circle-distance graphic candidate on a local input; it is not a source-silhouette perimeter solution.", "UNSUPPORTED"),
		_row("noise_erosion_border", "LOCAL", ["PRESENTATION_TIME", "FREE_RUN"], true, true, true, true, "MEDIUM", GOLD_ROUNDTRIP_EVIDENCE + "#LIVING_CONTOUR", "Dedicated local alpha-silhouette distance border with supplied-clock noise erosion; no rectangle/radial fallback; production roundtrip is proven while visual status remains adapter-only.", "ADAPTER_ONLY"),
		_row("pixel_sort_smear", "LOCAL", ["PRESENTATION_TIME", "FREE_RUN"], true, true, true, true, "MEDIUM", GOLD_ROUNDTRIP_EVIDENCE + "#SIGNAL_MELT", "Dedicated local-input directional luminance-run smear; it samples the resolved layer input rather than RGB separation or dither; production roundtrip is proven while visual status remains adapter-only.", "ADAPTER_ONLY"),
		_row("contour_pulse", "LOCAL", ["PRESENTATION_TIME", "FREE_RUN"], true, false, false, false, "NONE", "tests/fx_vnext_operator_foundation_test.gd#supplemental_registry", "Local source-alpha contour pulse candidate; no implemented contour-aware pass or evidence exists here.", "UNSUPPORTED"),
		_row("silhouette_extrude", "LOCAL", ["PRESENTATION_TIME", "FREE_RUN"], true, false, false, false, "NONE", "tests/fx_vnext_operator_foundation_test.gd#supplemental_registry", "Local source-alpha silhouette extrusion candidate; no implemented contour-aware pass or evidence exists here.", "UNSUPPORTED"),
		_row("print_misregistration", "FINAL_COMPOSITE", ["PRESENTATION_TIME", "FREE_RUN"], true, false, false, false, "NONE", "tests/fx_vnext_operator_foundation_test.gd#supplemental_registry", "Global final-frame print misregistration candidate; no dedicated implementation or runtime evidence exists in this repository.", "UNSUPPORTED"),
		_row("halftone_reveal", "LOCAL", ["PRESENTATION_TIME", "FREE_RUN"], true, false, false, false, "NONE", "tests/fx_vnext_operator_foundation_test.gd#supplemental_registry", "Local resolved-input halftone reveal candidate; no dedicated implementation or runtime evidence exists in this repository.", "UNSUPPORTED"),
		_row("dither_inversion", "FINAL_COMPOSITE", ["PRESENTATION_TIME", "FREE_RUN"], true, false, false, false, "NONE", "tests/fx_vnext_operator_foundation_test.gd#supplemental_registry", "Global final-frame dither inversion candidate; no dedicated implementation or runtime evidence exists in this repository.", "UNSUPPORTED"),
		_row("slice_tear", "FINAL_COMPOSITE", ["PRESENTATION_TIME", "FREE_RUN"], true, false, false, false, "NONE", "tests/fx_vnext_operator_foundation_test.gd#supplemental_registry", "Global final-frame slice tear candidate; no dedicated implementation or runtime evidence exists in this repository.", "UNSUPPORTED"),
		_row("hit_flash", "DEFERRED_3D", ["PRESENTATION_TIME"], true, false, false, false, "DEFERRED", "tests/fx_vnext_operator_foundation_test.gd#deferred_3d", "DEFERRED_3D_FORWARD_PLUS family: no 3D/Forward+ implementation, fake 2D port, or production-ready claim.", "DEFERRED"),
		_row("mesh_smear", "DEFERRED_3D", ["PRESENTATION_TIME"], true, false, false, false, "DEFERRED", "tests/fx_vnext_operator_foundation_test.gd#deferred_3d", "DEFERRED_3D_FORWARD_PLUS family: no 3D/Forward+ implementation, fake 2D port, or production-ready claim.", "DEFERRED"),
		_row("multi_impact_field", "DEFERRED_3D", ["PRESENTATION_TIME"], true, false, false, false, "DEFERRED", "tests/fx_vnext_operator_foundation_test.gd#deferred_3d", "DEFERRED_3D_FORWARD_PLUS family: no 3D/Forward+ implementation, fake 2D port, or production-ready claim.", "DEFERRED"),
		_row("slash_arc", "DEFERRED_3D", ["PRESENTATION_TIME"], true, false, false, false, "DEFERRED", "tests/fx_vnext_operator_foundation_test.gd#deferred_3d", "DEFERRED_3D_FORWARD_PLUS family: no 3D/Forward+ implementation, fake 2D port, or production-ready claim.", "DEFERRED"),
		_row("world_outline_depth", "DEFERRED_3D", ["PRESENTATION_TIME"], true, false, false, false, "DEFERRED", "tests/fx_vnext_operator_foundation_test.gd#deferred_3d", "DEFERRED_3D_FORWARD_PLUS family: no 3D/Forward+ implementation, fake 2D port, or production-ready claim.", "DEFERRED"),
		_row("world_outline_depth_normal", "DEFERRED_3D", ["PRESENTATION_TIME"], true, false, false, false, "DEFERRED", "tests/fx_vnext_operator_foundation_test.gd#deferred_3d", "DEFERRED_3D_FORWARD_PLUS family: no 3D/Forward+ implementation, fake 2D port, or production-ready claim.", "DEFERRED"),
		_row("final_composite", "FINAL_COMPOSITE", ["PRESENTATION_TIME", "FREE_RUN"], true, final_composite_supported(), final_composite_supported(), final_composite_supported(), "LOW", "tests/fx_vnext_final_composite_test.gd#runtime", "Dedicated BackBufferCopy + full-canvas shader pass; neutral by default and clocked by supplied presentation/free-run uniforms."),
		_row("deferred_3d", "DEFERRED_3D", ["PRESENTATION_TIME"], true, false, false, false, "DEFERRED", "tests/fx_vnext_operator_foundation_test.gd#registry", "No 3D/depth-aware operator path exists in this renderer; deferred rather than implied."),
	]
	var out: Dictionary = {}
	for row in rows:
		out[str(row["operator_id"])] = row
	return out

static func _row(operator_id: String, scope: String, time_sources: Array, neutral_proven: bool, authoring_reachable: bool, persistence_proven: bool, runtime_observable: bool, cost_class: String, evidence: String, notes: String, status_override := "") -> Dictionary:
	var status := status_override
	if status == "":
		status = "SUPPORTED" if scope == "FINAL_COMPOSITE" and authoring_reachable else ("ADAPTER_ONLY" if authoring_reachable else ("UNSUPPORTED" if scope == "FINAL_COMPOSITE" else "DEFERRED"))
	return {
		"operator_id": operator_id,
		"scope": scope,
		"lane": "TARGET_LOCAL" if scope == "LOCAL" else scope,
		"time_source": str(time_sources[0]) if not time_sources.is_empty() else "PRESENTATION_TIME",
		"time_source_support": time_sources.duplicate(),
		"time_sources": time_sources.duplicate(),
		"neutral_proven": neutral_proven,
		"authoring_reachable": authoring_reachable,
		"persistence_proven": persistence_proven,
		"runtime_observable": runtime_observable,
		"cost_class": cost_class,
		"test_evidence_reference": evidence,
		"semantic_notes": notes,
		"status": status,
	}

static func _neutral_transform(transform: Dictionary) -> bool:
	var position_neutral: bool = transform.get("position_px", [0.0, 0.0]) == [0.0, 0.0]
	var scale_neutral: bool = transform.get("scale", [1.0, 1.0]) == [1.0, 1.0]
	var rotation_neutral: bool = float(transform.get("rotation_deg", 0.0)) == 0.0
	var pivot_neutral: bool = transform.get("pivot", [0.5, 0.5]) == [0.5, 0.5]
	var flips_neutral: bool = not bool(transform.get("flip_x", false)) and not bool(transform.get("flip_y", false))
	return position_neutral and scale_neutral and rotation_neutral and pivot_neutral and flips_neutral

static func _active_base(fx: Dictionary) -> bool:
	return float(fx.get("base_opacity", 1.0)) != 1.0 or float(fx.get("base_grade_amount", 0.0)) != 0.0 or float(fx.get("base_mode", 0.0)) != 0.0

static func _active_grade(fx: Dictionary) -> bool:
	return float(fx.get("grade_black_point", 0.0)) != 0.0 or float(fx.get("grade_white_point", 1.0)) != 1.0 or float(fx.get("grade_gamma", 1.0)) != 1.0 or float(fx.get("grade_contrast", 1.0)) != 1.0 or float(fx.get("grade_brightness", 0.0)) != 0.0 or float(fx.get("grade_saturation", 1.0)) != 1.0

static func _active_mono(fx: Dictionary) -> bool:
	return float(fx.get("mono_threshold", 0.75)) != 0.75 or float(fx.get("mono_pixel", 2.0)) != 2.0 or float(fx.get("mono_space", 1.0)) != 1.0

static func _active_palette(fx: Dictionary) -> bool:
	return float(fx.get("palette_strategy", 0.0)) != 0.0 or bool(fx.get("palette_swap", false)) or float(fx.get("palette_hue_offset", 0.0)) != 0.0 or float(fx.get("palette_saturation", 1.0)) != 1.0 or float(fx.get("palette_value", 1.0)) != 1.0 or bool(fx.get("palette_lock_a", false)) or bool(fx.get("palette_lock_b", false))
