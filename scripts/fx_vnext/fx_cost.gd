extends RefCounted
# NRCU FX Lab vNext — layer/look cost estimator (specs/02 §11).
#
# Non-blocking, deterministic relative cost estimate. Factors mirror the spec
# list: source-copy pass, overscan/full-frame planes, blur radius, displacement,
# custom texture/mask sampling, COMPOSITE_BELOW input, procedural drivers and
# the FX stage amounts. Pure logic: no rendering, no UI.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxOperatorsScript := preload("res://scripts/fx_vnext/fx_operators.gd")
const FxCompositionScript := preload("res://scripts/fx_vnext/fx_composition.gd")

static func layer_cost(layer: Dictionary) -> Dictionary:
	var factors: Array = []
	var cost := 1.0
	factors.append("base 1.0")

	var type := str(layer.get("type", ""))
	if type == "SOURCE_COPY":
		cost += 0.5
		factors.append("source copy pass +0.5")
	elif type == "FX":
		cost += 0.5
		factors.append("fx stage +0.5")
		var fx: Dictionary = layer.get("fx", {})
		var fringe := float(fx.get("fringe", 0.0))
		if fringe > 0.001:
			cost += 2.0 * fringe
			factors.append("fringe +%.2f" % (2.0 * fringe))
		var dither := float(fx.get("dither", 0.0))
		if dither > 0.001:
			cost += 0.5 * dither
			factors.append("dither +%.2f" % (0.5 * dither))
		var rgb := float(fx.get("rgb", 0.0))
		if rgb > 0.001:
			cost += 0.3 * rgb
			factors.append("rgb tear +%.2f" % (0.3 * rgb))
		var blur := float(fx.get("color_blur", 0.0))
		if blur > 0.001:
			cost += 0.7 * blur
			factors.append("blur radius +%.2f" % (0.7 * blur))
		var input := str(layer.get("input", "ORIGINAL_SOURCE"))
		if input == "COMPOSITE_BELOW":
			cost += 2.5
			factors.append("composite-below flatten +2.5")
		elif input == "LAYER_BELOW":
			cost += 1.0
			factors.append("layer-below pass +1.0")

	var displacement: Dictionary = layer.get("displacement", {})
	if bool(displacement.get("enabled", false)):
		cost += 0.6
		factors.append("displacement driver +0.6")
		if displacement.get("custom_texture") != null:
			cost += 0.2
			factors.append("custom driver texture +0.2")

	var mask: Dictionary = layer.get("mask", {})
	if bool(mask.get("enabled", false)):
		cost += 0.4
		factors.append("mask silhouette scan +0.4")
		if mask.get("custom_mask") != null:
			cost += 0.3
			factors.append("custom mask sampling +0.3")
		var feather := float(mask.get("feather_px", 0.0))
		if feather > 0.0:
			cost += minf(0.3, feather * 0.01)
			factors.append("mask feather +%.2f" % minf(0.3, feather * 0.01))

	var plane := str(layer.get("plane", "TARGET_SOURCE"))
	if plane == "COMPOSITION_BACKGROUND" or plane == "COMPOSITION_FOREGROUND":
		cost += 0.8
		factors.append("full-frame composition plane +0.8")

	var fx_size := float((layer.get("fx", {}) as Dictionary).get("size", 1.0))
	if fx_size > 1.0:
		cost *= fx_size
		factors.append("fx size factor ×%.2f" % fx_size)

	var operator_ids: Array = FxOperatorsScript.operator_ids_for_layer(layer)
	var operator_costs: Dictionary = FxOperatorsScript.operator_costs_for_layer(layer)
	var operator_cost := 0.0
	for operator_id in _sorted_keys(operator_costs):
		operator_cost += float(operator_costs[operator_id])
	if operator_cost > 0.0:
		cost += operator_cost
		factors.append("named operators +%.2f" % operator_cost)
	var lane_result: Dictionary = FxOperatorsScript.validate_layer_lane(layer)
	var lane := str(lane_result.get("lane", ""))
	var lane_supported := bool(lane_result.get("supported", false))
	var lane_status := "SUPPORTED" if lane_supported else ("UNSUPPORTED" if lane in ["FINAL_COMPOSITE", ""] else "DEFERRED")
	# Unsupported/deferred lanes have no rendered work to charge. The status is
	# still surfaced so a zero cost cannot be mistaken for a supported pass.
	var lane_cost := 0.0
	var lane_costs: Dictionary = {}
	if lane != "":
		lane_costs[lane] = lane_cost
	if not lane_supported:
		factors.append("lane %s %s (no rendered cost)" % [lane if lane != "" else "INVALID", lane_status])
	return {
		"layer_id": str(layer.get("layer_id", "")),
		"cost": cost,
		"factors": factors,
		"operator_ids": operator_ids,
		"operator_cost": operator_cost,
		"operator_costs": operator_costs,
		"lane": lane,
		"lane_supported": lane_supported,
		"lane_status": lane_status,
		"lane_cost": lane_cost,
		"lane_costs": lane_costs,
	}

static func look_cost(doc: Dictionary) -> Dictionary:
	var layers: Array = []
	var total := 0.0
	var operator_cost_total := 0.0
	var lane_cost_total := 0.0
	var operator_costs: Dictionary = {}
	var lane_costs: Dictionary = {}
	var unsupported_lanes: Array = []
	for raw in doc.get("layers", []):
		if not (raw is Dictionary) or not bool((raw as Dictionary).get("enabled", true)):
			continue
		var entry := layer_cost(raw)
		layers.append(entry)
		total += float(entry["cost"])
		operator_cost_total += float(entry.get("operator_cost", 0.0))
		lane_cost_total += float(entry.get("lane_cost", 0.0))
		for operator_id in (entry.get("operator_costs", {}) as Dictionary).keys():
			operator_costs[str(operator_id)] = float(operator_costs.get(str(operator_id), 0.0)) + float((entry["operator_costs"] as Dictionary)[operator_id])
		for lane in (entry.get("lane_costs", {}) as Dictionary).keys():
			lane_costs[str(lane)] = float(lane_costs.get(str(lane), 0.0)) + float((entry["lane_costs"] as Dictionary)[lane])
		if not bool(entry.get("lane_supported", false)) and str(entry.get("lane", "")) not in unsupported_lanes:
			unsupported_lanes.append(str(entry.get("lane", "")))
	operator_costs = _sorted_dictionary(operator_costs)
	lane_costs = _sorted_dictionary(lane_costs)
	unsupported_lanes.sort()
	var level := "LOW"
	if total > 6.0:
		level = "HIGH"
	elif total > 3.0:
		level = "MEDIUM"
	return {
		"layers": layers,
		"total": total,
		"level": level,
		"operator_cost_total": operator_cost_total,
		"operator_costs": operator_costs,
		"lane_cost_total": lane_cost_total,
		"lane_costs": lane_costs,
		"unsupported_lanes": unsupported_lanes,
	}

static func composition_cost(doc: Dictionary) -> Dictionary:
	var check := FxCompositionScript.validate(doc)
	if not bool(check.get("ok", false)):
		return {"passes": [], "total": 0.0, "level": "INVALID", "operator_costs": {}, "errors": check.get("errors", [])}
	var passes: Array = []
	var total := 0.0
	var operator_costs: Dictionary = {}
	for raw_pass in (check.get("doc", {}) as Dictionary).get("final_passes", []):
		var composition_pass: Dictionary = raw_pass
		if not bool(composition_pass.get("enabled", true)) or str(composition_pass.get("operator", "NONE")) == "NONE":
			continue
		var layer_array: Array = FxCompositionScript.to_layers({"composition_id": "cost", "revision": 1, "status": "DRAFT", "final_passes": [composition_pass]})
		if layer_array.is_empty():
			continue
		var entry := layer_cost(layer_array[0])
		entry["pass_id"] = str(composition_pass.get("pass_id", ""))
		entry["full_frame"] = true
		passes.append(entry)
		total += float(entry.get("cost", 0.0)) + 0.8
		for operator_id in (entry.get("operator_costs", {}) as Dictionary).keys():
			operator_costs[str(operator_id)] = float(operator_costs.get(str(operator_id), 0.0)) + float((entry["operator_costs"] as Dictionary)[operator_id])
	var level := "LOW"
	if total > 6.0:
		level = "HIGH"
	elif total > 3.0:
		level = "MEDIUM"
	return {"passes": passes, "total": total, "level": level, "operator_costs": _sorted_dictionary(operator_costs), "errors": []}

static func _sorted_keys(values: Dictionary) -> Array:
	var keys: Array = values.keys()
	keys.sort()
	return keys

static func _sorted_dictionary(values: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in _sorted_keys(values):
		out[str(key)] = values[key]
	return out
