extends RefCounted
class_name FxRecipes
# NRCU FX Lab vNext — Phase 7 first-class Hero Recipe registry.
#
# Recipes are authoring data, not Production Looks and not replacements for the
# generic one-layer templates. Every recipe definition names its target intent,
# authored canonical fields and macro/Advanced access. Instantiation is pure:
# the caller supplies an instance key and all resulting layer ids are derived
# from that key (never from the process-global FxLook id counter or RNG).

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")

const PRIMARY_FLAME_ENERGY := "PRIMARY_FLAME_ENERGY"
const ORGANIC_SIDE_FIELD := "ORGANIC_SIDE_FIELD"
const EDGE_HALO := "EDGE_HALO"
const RGB_TEAR := "RGB_TEAR"
const DITHER_TREATMENT := "DITHER_TREATMENT"
const KINETIC_RUSH := "KINETIC_RUSH"
const PATTERN_CUT := "PATTERN_CUT"
const LIVING_CONTOUR := "LIVING_CONTOUR"
const SIGNAL_MELT := "SIGNAL_MELT"
const VACUUM_CLASH := "VACUUM_CLASH"
const CLASH_OVERDRIVE := "CLASH_OVERDRIVE"
const HERO_RECIPE_IDS := [PRIMARY_FLAME_ENERGY, ORGANIC_SIDE_FIELD]
const CURATED_RECIPE_IDS := [EDGE_HALO, RGB_TEAR, DITHER_TREATMENT]
const GOLD_RECIPE_IDS := [LIVING_CONTOUR, SIGNAL_MELT, KINETIC_RUSH, VACUUM_CLASH, PATTERN_CUT, CLASH_OVERDRIVE]
const RECIPE_IDS := HERO_RECIPE_IDS + GOLD_RECIPE_IDS + CURATED_RECIPE_IDS
const FxCompositionScript := preload("res://scripts/fx_vnext/fx_composition.gd")
const COMPOSITION_RECIPE_IDS := [KINETIC_RUSH, PATTERN_CUT, VACUUM_CLASH, CLASH_OVERDRIVE]

# Gold macro option domains are deliberately keyed by recipe, macro, and
# canonical field. A value from one operator domain must never be reused as a
# value in another domain (for example, PULL/PUSH is not a pattern family).
const MACRO_OPTION_MAPS := {
	"KINETIC_RUSH": {
		"DISTORTION": {"fx.operator_mix_mode": {"LINES": 0.0, "DISTORTION": 1.0, "COMBINED": 2.0}},
	},
	"SIGNAL_MELT": {
		"CHROMATIC_SPLIT": {"fx.operator_mix_mode": {"LINES": 0.0, "DISTORTION": 1.0, "COMBINED": 2.0}},
	},
	"CLASH_OVERDRIVE": {
		"DISTORTION": {"fx.operator_mix_mode": {"LINES": 0.0, "DISTORTION": 1.0, "COMBINED": 2.0}},
	},
	"PATTERN_CUT": {
		"PATTERN": {"fx.operator_pattern_family": {"GRID": 0.0, "DIAGONAL": 1.0, "ANGULAR": 2.0}},
	},
	"VACUUM_CLASH": {
		"POLARITY": {"fx.operator_polarity": {"PULL": 0.0, "PUSH": 1.0}},
	},
}
const MACRO_TOKEN_DOMAINS := {
	"anchor": ["CUSTOM", "TARGET_CENTER", "VS_MARK", "LEFT_FIGHTER", "RIGHT_FIGHTER"],
	"clock": ["PRESENTATION_TIME", "FREE_RUN"],
	"mode": ["LINES", "DISTORTION", "COMBINED"],
}

static func recipe_ids() -> Array:
	return RECIPE_IDS.duplicate()

static func list() -> Array:
	var out: Array = []
	for recipe_id in RECIPE_IDS:
		out.append(get_recipe(str(recipe_id)))
	return out

static func has_recipe(recipe_id: String) -> bool:
	return RECIPE_IDS.has(recipe_id)

static func macro_options(recipe_id: String, macro_id: String, source: String) -> Array:
	if MACRO_TOKEN_DOMAINS.has(source):
		return (MACRO_TOKEN_DOMAINS[source] as Array).duplicate()
	if source != "option":
		return []
	var recipe_map: Dictionary = MACRO_OPTION_MAPS.get(recipe_id, {})
	var macro_map: Dictionary = recipe_map.get(macro_id, {}) if recipe_map.get(macro_id, {}) is Dictionary else {}
	for raw_options in macro_map.values():
		if raw_options is Dictionary:
			return (raw_options as Dictionary).keys()
	return []

static func get_recipe(recipe_id: String) -> Dictionary:
	var definition := _definition(recipe_id)
	return definition.duplicate(true)

static func target_compatibility(recipe_id: String, target_context: Dictionary) -> Dictionary:
	# This is the single fail-closed target authority used by the public Lab add
	# action. A missing/unknown role is never treated as a wildcard, and the
	# recipe's declared planes are checked against its own generated canonical
	# layers before a caller is allowed to mutate a session.
	var recipe := _definition(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "errors": ["unknown recipe: " + recipe_id], "recipe_id": recipe_id}
	if not (target_context is Dictionary):
		return {"ok": false, "errors": ["target context is required"], "recipe_id": recipe_id}
	var compatibility: Dictionary = recipe.get("target_compatibility", {}) if recipe.get("target_compatibility", {}) is Dictionary else {}
	var role := str(target_context.get("element_role", "")).strip_edges()
	var errors: Array = []
	var target_roles: Array = compatibility.get("target_roles", []) if compatibility.get("target_roles", []) is Array else []
	var element_roles: Array = compatibility.get("element_roles", target_roles) if compatibility.get("element_roles", target_roles) is Array else []
	if role == "":
		errors.append("target context has no element_role")
	else:
		if not target_roles.has(role):
			errors.append("recipe %s does not target role %s" % [recipe_id, role])
		if not element_roles.has(role):
			errors.append("recipe %s does not support element role %s" % [recipe_id, role])
	var requires_fighter := bool(compatibility.get("requires_fighter", false))
	var fighter_id := str(target_context.get("fighter_id", "")).strip_edges()
	if requires_fighter and fighter_id == "":
		errors.append("recipe %s requires a fighter target" % recipe_id)
	var allowed_planes: Array = compatibility.get("allowed_planes", []) if compatibility.get("allowed_planes", []) is Array else []
	if allowed_planes.is_empty():
		errors.append("recipe %s declares no allowed planes" % recipe_id)
	for raw_spec in recipe.get("layers", []):
		var spec: Dictionary = raw_spec
		var authored: Dictionary = spec.get("authored_fields", {}) if spec.get("authored_fields", {}) is Dictionary else {}
		var plane := str(authored.get("layer.plane", ""))
		if plane == "" or not allowed_planes.has(plane):
			errors.append("recipe %s layer %s is outside allowed planes" % [recipe_id, str(spec.get("instance_key", "layer"))])
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"recipe_id": recipe_id,
		"target_key": str(target_context.get("target_key", "")),
		"target_role": role,
		"fighter_id": fighter_id,
		"requires_fighter": requires_fighter,
		"allowed_planes": allowed_planes.duplicate(),
	}

static func instantiate(recipe_id: String, instance_key: String) -> Dictionary:
	var recipe := _definition(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "errors": ["unknown recipe: " + recipe_id], "layers": []}
	var key := instance_key.strip_edges()
	if key == "":
		return {"ok": false, "errors": ["instance_key must not be empty"], "layers": []}
	var layers: Array = []
	var errors: Array = []
	for raw_spec in recipe.get("layers", []):
		var spec: Dictionary = raw_spec
		var layer := FxLookScript.new_layer(str(spec.get("type", FxLookScript.TYPE_FX)), str(spec.get("name", "Recipe Layer")))
		layer["layer_id"] = deterministic_layer_id(recipe_id, key, str(spec.get("instance_key", "layer")))
		var authored: Dictionary = spec.get("authored_fields", {})
		for field_path in authored.keys():
			if not _set_field(layer, str(field_path), authored[field_path]):
				errors.append("%s.%s: unsupported canonical field" % [str(spec.get("instance_key", "layer")), str(field_path)])
		# Re-materialize each layer so callers receive exactly the same canonical
		# shape as a normal FxSession edit, including float coercion and complete
		# neutral defaults.
		var materialized := FxLookScript.materialize({"layers": [layer]})
		var fixed_layers: Array = materialized.get("layers", [])
		if fixed_layers.is_empty():
			errors.append("%s: failed to materialize" % str(spec.get("instance_key", "layer")))
		else:
			# A few Gold fields predate the shared neutral table. Restore only the
			# recipe's declared canonical values after generic materialization so the
			# recipe remains lossless without adding a second creative state store.
			var fixed_layer: Dictionary = fixed_layers[0]
			_restore_authored_fields(fixed_layer, spec)
			layers.append(fixed_layer)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "layers": layers}
	var result := {
		"ok": true,
		"errors": [],
		"recipe_id": recipe_id,
		"instance_key": key,
		"recipe_instance_id": key,
		"layers": layers,
		"layer_ids": layers.map(func(layer): return str((layer as Dictionary).get("layer_id", ""))),
		"pass_ids": [],
	}
	result["membership"] = {
		"recipe_id": recipe_id,
		"recipe_instance_id": key,
		"layer_ids": result["layer_ids"].duplicate(),
		"pass_ids": [],
	}
	if COMPOSITION_RECIPE_IDS.has(recipe_id):
		result["composition"] = instantiate_composition(recipe_id, key, layers)
		result["pass_ids"] = (result["composition"].get("pass_ids", []) as Array).duplicate()
		(result["membership"] as Dictionary)["pass_ids"] = result["pass_ids"].duplicate()
	return result

static func is_composition_recipe(recipe_id: String) -> bool:
	return COMPOSITION_RECIPE_IDS.has(recipe_id)

static func instantiate_composition(recipe_id: String, instance_key: String, canonical_layers := []) -> Dictionary:
	if not COMPOSITION_RECIPE_IDS.has(recipe_id):
		return {"ok": false, "errors": ["recipe is not composition-owned: " + recipe_id], "doc": {}}
	var layers: Array = canonical_layers
	if layers.is_empty():
		var result := instantiate(recipe_id, instance_key)
		if not bool(result.get("ok", false)):
			return {"ok": false, "errors": result.get("errors", []), "doc": {}}
		layers = result.get("layers", [])
	var doc := FxCompositionScript.new_document("COMP_%s_%s" % [recipe_id, instance_key], str(_definition(recipe_id).get("name", recipe_id)))
	var passes: Array = []
	for index in range(layers.size()):
		var layer: Dictionary = layers[index]
		var fx: Dictionary = (layer.get("fx", {}) as Dictionary).duplicate(true)
		var operator_id := str(fx.get("operator", "NONE"))
		passes.append({
			"pass_id": deterministic_layer_id(recipe_id, instance_key, "composition_pass_%d" % index),
			"name": str(layer.get("name", operator_id)),
			"operator": operator_id,
			"enabled": bool(layer.get("enabled", true)),
			"event_start": float(fx.get("operator_event_start", 0.0)),
			"duration": float(fx.get("operator_duration", 0.0)),
			"lane": "FINAL_COMPOSITE",
			"plane": "COMPOSITION_FOREGROUND",
			"authority": "COMPOSITION",
			"fx": fx,
		})
	# Explicit terminal identity keeps the authored sequence inspectable while
	# the renderer skips it as a no-op; creative passes own their neutral return.
	passes.append({"pass_id": deterministic_layer_id(recipe_id, instance_key, "composition_neutral"), "name": "Neutral Release", "operator": "NONE", "enabled": true, "event_start": 0.0, "duration": 0.0, "lane": "FINAL_COMPOSITE", "plane": "COMPOSITION_FOREGROUND", "authority": "COMPOSITION", "fx": {}})
	doc["final_passes"] = passes
	var check := FxCompositionScript.validate(doc)
	return {"ok": bool(check.get("ok", false)), "errors": check.get("errors", []), "doc": check.get("doc", doc), "pass_ids": passes.map(func(final_pass): return str((final_pass as Dictionary).get("pass_id", "")))}

static func instantiate_look(recipe_id: String, look_id: String, look_name: String, instance_key: String) -> Dictionary:
	var result := instantiate(recipe_id, instance_key)
	var recipe := _definition(recipe_id)
	if not bool(result.get("ok", false)):
		return result
	var look := FxLookScript.new_look(look_id, look_name)
	look["layers"].append_array(result["layers"])
	# Keep the Recipe contract beside the canonical Look. Macros are intent
	# controls over these same fields; they are not a hidden second state store.
	look["metadata"]["recipe_id"] = recipe_id
	look["metadata"]["recipe_macros"] = recipe.get("macros", []).duplicate(true)
	look["metadata"]["recipe_target_compatibility"] = recipe.get("target_compatibility", {}).duplicate(true)
	look["metadata"]["source_semantics"] = recipe.get("source_semantics", {}).duplicate(true)
	# Provenance is membership-only. Creative values stay in canonical layers
	# (and composition passes); this index only records which ids belong to the
	# recipe instance so later macros cannot fan out to sibling instances.
	look["metadata"]["recipe_instances"] = [(result.get("membership", {}) as Dictionary).duplicate(true)]
	look = FxLookScript.materialize(look)
	for raw_layer in result.get("layers", []):
		var recipe_layer: Dictionary = raw_layer
		var canonical_layer: Dictionary = FxLookScript.find_layer(look, str(recipe_layer.get("layer_id", "")))
		if not canonical_layer.is_empty():
			for raw_spec in recipe.get("layers", []):
				var spec: Dictionary = raw_spec
				if deterministic_layer_id(recipe_id, instance_key, str(spec.get("instance_key", ""))) == str(recipe_layer.get("layer_id", "")):
					_restore_authored_fields(canonical_layer, spec)
					break
	var validation := FxLookScript.validate_input(look)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "errors": validation.get("errors", []), "layers": result["layers"], "look": look}
	result["look"] = look
	return result

static func apply_macro(doc: Dictionary, recipe_id: String, arg3, arg4, arg5 = null) -> bool:
	var result: Dictionary = apply_macro_result(doc, recipe_id, arg3, arg4, arg5)
	return bool(result.get("ok", false) and result.get("changed", false))

static func apply_macro_result(doc: Dictionary, recipe_id: String, arg3, arg4, arg5 = null) -> Dictionary:
	# New callers pass (recipe_id, recipe_instance_id, macro_id, value). The
	# legacy four-argument form remains for existing single-instance Looks, but
	# it is resolved through membership metadata when available.
	var recipe := _definition(recipe_id)
	if recipe.is_empty() or not (doc is Dictionary):
		return {"ok": false, "changed": false, "errors": ["unknown recipe or invalid document"]}
	var explicit_instance := arg5 != null
	var instance_selector = arg3
	var macro_id := ""
	var macro_value
	if explicit_instance:
		# Also accept the append-compatible form (macro_id, value,
		# recipe_instance_id) so integrations can migrate without a flag day.
		if _has_macro(recipe, str(arg3)):
			macro_id = str(arg3)
			macro_value = arg4
			instance_selector = arg5
		else:
			macro_id = str(arg4)
			macro_value = arg5
	else:
		macro_id = str(arg3)
		macro_value = arg4
	var macro: Dictionary = _find_macro(recipe, macro_id)
	if macro.is_empty():
		return {"ok": false, "changed": false, "errors": ["unknown macro: " + macro_id]}

	var membership := _resolve_membership(doc, recipe_id, instance_selector, explicit_instance)
	if bool(membership.get("ambiguous", false)):
		return {"ok": false, "changed": false, "errors": ["recipe macro instance is ambiguous"]}
	var selected_layer_ids: Dictionary = _id_set(membership.get("layer_ids", []))
	var selected_pass_ids: Dictionary = _id_set(membership.get("pass_ids", []))
	if explicit_instance and selected_layer_ids.is_empty() and selected_pass_ids.is_empty():
		return {"ok": false, "changed": false, "errors": ["recipe macro instance has no canonical targets"]}

	var mapping: Dictionary = macro.get("mapping", {})
	if mapping.is_empty():
		return {"ok": false, "changed": false, "errors": ["macro has no canonical mapping"]}
	var staged_layers: Array = (doc.get("layers", []) as Array).duplicate(true)
	var staged_passes: Array = (doc.get("final_passes", []) as Array).duplicate(true)
	var layer_changed := false
	var pass_changed := false
	var changed_layer_indexes: Array = []
	var changed_pass_indexes: Array = []
	for index in range(staged_layers.size()):
		if not (staged_layers[index] is Dictionary):
			continue
		var layer: Dictionary = staged_layers[index]
		var layer_id := str(layer.get("layer_id", ""))
		if explicit_instance and not selected_layer_ids.has(layer_id):
			continue
		if not explicit_instance and not selected_layer_ids.is_empty() and not selected_layer_ids.has(layer_id):
			continue
		var layer_changed_here := false
		for raw_path in mapping.keys():
			var path := str(raw_path)
			var rule: Dictionary = mapping[raw_path] if mapping[raw_path] is Dictionary else {}
			if not _macro_rule_targets(layer, rule, recipe_id, instance_selector):
				continue
			var source := str(rule.get("source", "value"))
			var mapped = _macro_mapped_value(layer, path, rule, source, macro_value, recipe_id, macro_id)
			if mapped == null or not _set_field(layer, path, mapped):
				return {"ok": false, "changed": false, "errors": ["unsupported or invalid macro mapping: " + path]}
			layer_changed_here = true
		if not layer_changed_here:
			continue
		layer_changed = true
		changed_layer_indexes.append(index)
		staged_layers[index] = layer
	for index in range(staged_passes.size()):
		if not (staged_passes[index] is Dictionary):
			continue
		var final_pass: Dictionary = staged_passes[index]
		var pass_id := str(final_pass.get("pass_id", ""))
		if explicit_instance and not selected_pass_ids.has(pass_id):
			continue
		if not explicit_instance and not selected_pass_ids.is_empty() and not selected_pass_ids.has(pass_id):
			continue
		var pass_changed_here := false
		for raw_path in mapping.keys():
			var path := str(raw_path)
			var rule: Dictionary = mapping[raw_path] if mapping[raw_path] is Dictionary else {}
			if not _macro_rule_targets(final_pass, rule, recipe_id, instance_selector):
				continue
			var source := str(rule.get("source", "value"))
			var mapped = _macro_mapped_value(final_pass, path, rule, source, macro_value, recipe_id, macro_id)
			if mapped == null or not _set_field(final_pass, path, mapped):
				return {"ok": false, "changed": false, "errors": ["unsupported or invalid macro mapping: " + path]}
			pass_changed_here = true
		if not pass_changed_here:
			continue
		pass_changed = true
		changed_pass_indexes.append(index)
		staged_passes[index] = final_pass
	if not layer_changed and not pass_changed:
		return {"ok": true, "changed": false, "errors": ["macro resolved no canonical target"]}
	var live_layers: Array = doc.get("layers", [])
	for index in changed_layer_indexes:
		_replace_dictionary_in_place(live_layers[index] as Dictionary, staged_layers[index] as Dictionary)
	if doc.has("final_passes"):
		var live_passes: Array = doc.get("final_passes", [])
		for index in changed_pass_indexes:
			_replace_dictionary_in_place(live_passes[index] as Dictionary, staged_passes[index] as Dictionary)
	var targets: Array = []
	for index in changed_layer_indexes:
		targets.append({"kind": "layer", "index": index, "id": str((staged_layers[index] as Dictionary).get("layer_id", ""))})
	for index in changed_pass_indexes:
		targets.append({"kind": "pass", "index": index, "id": str((staged_passes[index] as Dictionary).get("pass_id", ""))})
	return {"ok": true, "changed": true, "errors": [], "targets": targets}

static func macro_state(doc: Dictionary, recipe_id: String, instance_selector, macro_id: String) -> Dictionary:
	var recipe := _definition(recipe_id)
	var macro := _find_macro(recipe, macro_id)
	if recipe.is_empty() or macro.is_empty():
		return {"ok": false, "mixed": false, "errors": ["unknown Recipe or macro"]}
	var membership := _resolve_membership(doc, recipe_id, instance_selector, true)
	var selected_layer_ids: Dictionary = _id_set(membership.get("layer_ids", []))
	var selected_pass_ids: Dictionary = _id_set(membership.get("pass_ids", []))
	if selected_layer_ids.is_empty() and selected_pass_ids.is_empty():
		return {"ok": false, "mixed": false, "errors": ["macro instance has no canonical targets"]}
	var values: Array = []
	var tokens: Array = []
	var targets: Array = []
	var mapping: Dictionary = macro.get("mapping", {})
	for raw_layer in doc.get("layers", []):
		if not (raw_layer is Dictionary):
			continue
		var layer: Dictionary = raw_layer
		if not selected_layer_ids.has(str(layer.get("layer_id", ""))):
			continue
		for raw_path in mapping.keys():
			var path := str(raw_path)
			var rule: Dictionary = mapping[raw_path] if mapping[raw_path] is Dictionary else {}
			if not _macro_rule_targets(layer, rule, recipe_id, instance_selector):
				continue
			var projected := _macro_reverse_value(layer, path, rule, recipe_id, macro_id)
			if projected.has("token"):
				tokens.append(str(projected.get("token", "")))
			else:
				values.append(float(projected.get("value", 0.0)))
			targets.append({"kind": "layer", "id": str(layer.get("layer_id", "")), "path": path})
	for raw_pass in doc.get("final_passes", []):
		if not (raw_pass is Dictionary):
			continue
		var final_pass: Dictionary = raw_pass
		if not selected_pass_ids.has(str(final_pass.get("pass_id", ""))):
			continue
		for raw_path in mapping.keys():
			var path := str(raw_path)
			var rule: Dictionary = mapping[raw_path] if mapping[raw_path] is Dictionary else {}
			if not _macro_rule_targets(final_pass, rule, recipe_id, instance_selector):
				continue
			var projected := _macro_reverse_value(final_pass, path, rule, recipe_id, macro_id)
			if projected.has("token"):
				tokens.append(str(projected.get("token", "")))
			else:
				values.append(float(projected.get("value", 0.0)))
			targets.append({"kind": "pass", "id": str(final_pass.get("pass_id", "")), "path": path})
	if values.is_empty() and tokens.is_empty():
		return {"ok": false, "mixed": false, "errors": ["macro has no readable canonical target"]}
	var mixed := false
	var normalized := 0.0
	if not values.is_empty():
		normalized = values[0]
		for value in values:
			if not is_equal_approx(float(value), normalized):
				mixed = true
	if not tokens.is_empty():
		var token := str(tokens[0])
		for current in tokens:
			if str(current) != token:
				mixed = true
		return {"ok": true, "mixed": mixed, "token": "MIXED" if mixed else token, "value": normalized, "values": values, "targets": targets}
	return {"ok": true, "mixed": mixed, "token": "MIXED" if mixed else "", "value": normalized, "values": values, "targets": targets}

static func _macro_reverse_value(container: Dictionary, path: String, rule: Dictionary, recipe_id: String, macro_id: String) -> Dictionary:
	var raw = _get_field(container, path)
	var source := str(rule.get("source", "value"))
	if source == "anchor" or source == "clock":
		return {"token": str(raw)}
	if source == "option" or source == "mode":
		var options := _macro_option_map(recipe_id, macro_id, path)
		for raw_token in options.keys():
			if is_equal_approx(float(options[raw_token]), float(raw)):
				return {"token": str(raw_token)}
		return {"token": "MIXED"}
	var numeric := float(raw) if raw != null else 0.0
	if rule.has("threshold"):
		return {"value": 1.0 if numeric >= float(rule.get("threshold", 0.5)) else 0.0}
	if rule.has("scale"):
		numeric /= float(rule.get("scale", 1.0))
	var min_value := float(rule.get("min", 0.0))
	var max_value := float(rule.get("max", 1.0))
	return {"value": clampf(inverse_lerp(min_value, max_value, numeric), 0.0, 1.0)}

static func _replace_dictionary_in_place(target: Dictionary, source: Dictionary) -> void:
	for raw_key in target.keys():
		if not source.has(raw_key):
			target.erase(raw_key)
	for raw_key in source.keys():
		if target.has(raw_key) and target[raw_key] is Dictionary and source[raw_key] is Dictionary:
			_replace_dictionary_in_place(target[raw_key] as Dictionary, source[raw_key] as Dictionary)
		else:
			target[raw_key] = source[raw_key].duplicate(true) if source[raw_key] is Array or source[raw_key] is Dictionary else source[raw_key]

static func _has_macro(recipe: Dictionary, macro_id: String) -> bool:
	return not _find_macro(recipe, macro_id).is_empty()

static func _find_macro(recipe: Dictionary, macro_id: String) -> Dictionary:
	for raw_macro in recipe.get("macros", []):
		if str((raw_macro as Dictionary).get("id", "")) == macro_id:
			return (raw_macro as Dictionary).duplicate(true)
	return {}

static func _resolve_membership(doc: Dictionary, recipe_id: String, selector, explicit_instance: bool) -> Dictionary:
	if selector is Dictionary:
		var supplied: Dictionary = (selector as Dictionary).duplicate(true)
		if supplied.has("instance_id") and not supplied.has("recipe_instance_id"):
			supplied["recipe_instance_id"] = supplied["instance_id"]
		return supplied
	var selector_id := str(selector).strip_edges()
	if selector_id.begins_with(recipe_id + ":"):
		selector_id = selector_id.substr(recipe_id.length() + 1)
	var matching: Array = []
	var metadata = doc.get("metadata", {})
	if metadata is Dictionary:
		matching.append_array(_membership_entries((metadata as Dictionary).get("recipe_instances", [])))
	matching.append_array(_membership_entries(doc.get("recipe_instances", [])))
	var resolved: Dictionary = {}
	var matching_instance_ids: Dictionary = {}
	for raw_entry in matching:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry
		if str(entry.get("recipe_id", recipe_id)) != recipe_id:
			continue
		var entry_id := str(entry.get("recipe_instance_id", entry.get("instance_id", "")))
		if not explicit_instance and entry_id != "":
			matching_instance_ids[entry_id] = true
		if explicit_instance and entry_id != selector_id:
			continue
		for key in ["layer_ids", "pass_ids"]:
			var ids: Array = entry.get(key, []) if entry.get(key, []) is Array else []
			var current: Array = resolved.get(key, [])
			for raw_id in ids:
				if str(raw_id) not in current:
					current.append(str(raw_id))
			resolved[key] = current
		if explicit_instance:
			break
	if not explicit_instance and matching_instance_ids.size() > 1:
		return {"ambiguous": true}
	if explicit_instance and resolved.is_empty():
		return _derived_membership(recipe_id, selector_id)
	if not resolved.is_empty():
		return resolved
	if explicit_instance:
		return _derived_membership(recipe_id, selector_id)
	return {}

static func _membership_entries(raw_entries) -> Array:
	if raw_entries is Array:
		return (raw_entries as Array).duplicate(true)
	if raw_entries is Dictionary:
		var out: Array = []
		for raw_key in (raw_entries as Dictionary).keys():
			var entry = (raw_entries as Dictionary)[raw_key]
			if entry is Dictionary:
				var copy: Dictionary = (entry as Dictionary).duplicate(true)
				if not copy.has("recipe_instance_id"):
					copy["recipe_instance_id"] = str(raw_key)
				out.append(copy)
		return out
	return []

static func _derived_membership(recipe_id: String, instance_id: String) -> Dictionary:
	var out := {"recipe_id": recipe_id, "recipe_instance_id": instance_id, "layer_ids": [], "pass_ids": []}
	var recipe := _definition(recipe_id)
	if recipe.is_empty():
		return out
	for raw_spec in recipe.get("layers", []):
		var spec: Dictionary = raw_spec
		(out["layer_ids"] as Array).append(deterministic_layer_id(recipe_id, instance_id, str(spec.get("instance_key", "layer"))))
	if COMPOSITION_RECIPE_IDS.has(recipe_id):
		for index in range((recipe.get("layers", []) as Array).size()):
			(out["pass_ids"] as Array).append(deterministic_layer_id(recipe_id, instance_id, "composition_pass_%d" % index))
		(out["pass_ids"] as Array).append(deterministic_layer_id(recipe_id, instance_id, "composition_neutral"))
	return out

static func _id_set(ids) -> Dictionary:
	var out: Dictionary = {}
	if ids is Array:
		for raw_id in ids:
			out[str(raw_id)] = true
	return out

static func _macro_rule_targets(container: Dictionary, rule: Dictionary, recipe_id := "", instance_selector = null) -> bool:
	# The terminal identity pass is structural bookkeeping, never a creative
	# macro target. It must remain byte/canonically neutral unless a future rule
	# opts into an explicit structural capability.
	var fx: Dictionary = container.get("fx", {}) if container.get("fx", {}) is Dictionary else {}
	var operator_id := str(container.get("operator", fx.get("operator", "")))
	if operator_id == "NONE":
		return false
	var instance_keys: Array = rule.get("instance_keys", []) if rule.get("instance_keys", []) is Array else []
	if not instance_keys.is_empty():
		var selector_id := str(instance_selector)
		for raw_key in instance_keys:
			if recipe_id != "" and deterministic_layer_id(recipe_id, selector_id, str(raw_key)) == str(container.get("layer_id", "")):
				return true
		return false
	var operators: Array = rule.get("operators", []) if rule.get("operators", []) is Array else []
	if operators.is_empty():
		return true
	return operator_id in operators

static func _macro_mapped_value(_layer: Dictionary, path: String, rule: Dictionary, source: String, value, recipe_id: String, macro_id: String):
	if source == "anchor":
		var anchor := str(value)
		return anchor if anchor in ["CUSTOM", "TARGET_CENTER", "VS_MARK", "LEFT_FIGHTER", "RIGHT_FIGHTER"] else null
	if source == "clock":
		var clock := str(value)
		return clock if clock in ["PRESENTATION_TIME", "FREE_RUN"] else null
	if source == "option" or source == "mode":
		var options := _macro_option_map(recipe_id, macro_id, path)
		if options.is_empty():
			return null
		if value is String:
			return float(options[value]) if options.has(str(value)) else null
		var numeric = _number_or_null(value)
		if numeric == null:
			return null
		for raw_canonical in options.values():
			if is_equal_approx(float(raw_canonical), float(numeric)):
				return float(raw_canonical)
		return null
	var number = _number_or_null(value)
	if number == null:
		return null
	var normalized := clampf(float(number), 0.0, 1.0)
	var mapped := normalized
	if rule.has("threshold"):
		var threshold = _number_or_null(rule.get("threshold"))
		if threshold == null:
			return null
		# Threshold mappings are discrete and inclusive at the declared boundary.
		mapped = 1.0 if normalized >= float(threshold) else 0.0
	elif rule.has("min") or rule.has("max"):
		var min_value = _number_or_null(rule.get("min", 0.0))
		var max_value = _number_or_null(rule.get("max", 1.0))
		if min_value == null or max_value == null:
			return null
		mapped = lerpf(float(min_value), float(max_value), normalized)
	if rule.has("axis"):
		var axis := str(rule.get("axis", ""))
		var angle := normalized * TAU
		if axis == "x":
			mapped = cos(angle)
		elif axis == "y":
			mapped = sin(angle)
		else:
			return null
	if rule.has("scale"):
		var scale = _number_or_null(rule.get("scale"))
		if scale == null:
			return null
		# Scale is a post-map gain. Thus scale=0.45 at value=1.0 is 0.45,
		# while min/max remains an explicit range before that gain.
		mapped *= float(scale)
	return mapped

static func _macro_option_map(recipe_id: String, macro_id: String, path: String) -> Dictionary:
	var recipe_map: Dictionary = MACRO_OPTION_MAPS.get(recipe_id, {})
	var macro_map: Dictionary = recipe_map.get(macro_id, {}) if recipe_map.get(macro_id, {}) is Dictionary else {}
	var options = macro_map.get(path, {})
	return (options as Dictionary).duplicate(true) if options is Dictionary else {}

static func _number_or_null(value):
	if value == null or value is bool or value is Array or value is Dictionary:
		return null
	if value is String:
		var text := (value as String).strip_edges()
		return text.to_float() if text.is_valid_float() else null
	var number := float(value)
	return number if is_finite(number) else null

static func deterministic_layer_id(recipe_id: String, instance_key: String, layer_key: String) -> String:
	# Slugs remain readable in the layer panel. The bounded digest prevents
	# collisions when two external keys normalize to the same slug while still
	# making the full identity a deterministic function of the supplied key.
	var digest_source := "%s|%s|%s" % [recipe_id, instance_key, layer_key]
	var digest := digest_source.md5_text().substr(0, 8)
	return "recipe-%s-%s-%s-%s" % [_slug(recipe_id), _slug(instance_key), _slug(layer_key), digest]

static func authored_field_paths(recipe_id: String) -> Array:
	var recipe := _definition(recipe_id)
	var seen: Dictionary = {}
	var out: Array = []
	for raw_spec in recipe.get("layers", []):
		var fields: Dictionary = (raw_spec as Dictionary).get("authored_fields", {})
		for path in fields.keys():
			var text := str(path)
			if not seen.has(text):
				seen[text] = true
				out.append(text)
	return out

static func validate_authored_fields(recipe_id: String, layers: Array) -> Dictionary:
	var recipe := _definition(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "errors": ["unknown recipe: " + recipe_id]}
	var errors: Array = []
	var specs: Array = recipe.get("layers", [])
	if layers.size() != specs.size():
		errors.append("expected %d recipe layers, got %d" % [specs.size(), layers.size()])
	for i in range(mini(layers.size(), specs.size())):
		var layer: Dictionary = layers[i]
		var spec: Dictionary = specs[i]
		var authored: Dictionary = spec.get("authored_fields", {})
		for path in authored.keys():
			var actual = _get_field(layer, str(path))
			if actual == null and authored[path] != null:
				errors.append("%s.%s: authored value missing" % [str(spec.get("instance_key", "layer")), str(path)])
			elif not FxLookScript.equivalent(actual, authored[path]):
				errors.append("%s.%s: authored value changed" % [str(spec.get("instance_key", "layer")), str(path)])
		var neutral := FxLookScript.new_layer(str(spec.get("type", FxLookScript.TYPE_FX)), "neutral")
		var changed := _diff_paths(neutral, layer)
		for path in changed:
			if not authored.has(path):
				errors.append("%s.%s: hidden creative value" % [str(spec.get("instance_key", "layer")), path])
	return {"ok": errors.is_empty(), "errors": errors}

static func validate_registry() -> Dictionary:
	var errors: Array = []
	var ids := recipe_ids()
	if ids.size() < 5:
		errors.append("recipe library must expose both Hero Recipes and at least three curated starting points")
	for recipe_id in ids:
		var recipe := _definition(str(recipe_id))
		if recipe.is_empty():
			errors.append("missing definition: " + str(recipe_id))
			continue
		if str(recipe.get("stable_id", "")) != str(recipe_id):
			errors.append("%s: stable_id mismatch" % recipe_id)
		if str(recipe.get("description", "")).strip_edges() == "":
			errors.append("%s: description missing" % recipe_id)
		if not bool(recipe.get("advanced_access", false)):
			errors.append("%s: Advanced access missing" % recipe_id)
		var compatibility: Dictionary = recipe.get("target_compatibility", {})
		if (compatibility.get("target_roles", []) as Array).is_empty():
			errors.append("%s: target compatibility missing" % recipe_id)
		var layer_keys: Dictionary = {}
		var instantiated := instantiate(str(recipe_id), "registry-validation")
		if not bool(instantiated.get("ok", false)):
			errors.append_array(instantiated.get("errors", []))
			continue
		for raw_spec in recipe.get("layers", []):
			var spec: Dictionary = raw_spec
			var layer_key := str(spec.get("instance_key", ""))
			if layer_key == "" or layer_keys.has(layer_key):
				errors.append("%s: layer instance keys must be unique" % recipe_id)
			layer_keys[layer_key] = true
			var authored: Dictionary = spec.get("authored_fields", {})
			for path in authored.keys():
				if not _is_supported_field_path(str(path)):
					errors.append("%s.%s: unsupported authored field" % [recipe_id, str(path)])
		var stack_check := validate_authored_fields(str(recipe_id), instantiated.get("layers", []))
		if not bool(stack_check.get("ok", false)):
			errors.append_array(stack_check.get("errors", []))
		var look := FxLookScript.new_look("RECIPE_%s" % recipe_id, str(recipe.get("name", recipe_id)))
		look["layers"].append_array(instantiated.get("layers", []))
		var canonical := FxLookScript.materialize(look)
		var look_check := FxLookScript.validate_input(canonical)
		if not bool(look_check.get("ok", false)):
			errors.append_array(look_check.get("errors", []))
		var macro_ids: Dictionary = {}
		for raw_macro in recipe.get("macros", []):
			var macro: Dictionary = raw_macro
			var macro_id := str(macro.get("id", ""))
			if macro_id == "" or macro_ids.has(macro_id):
				errors.append("%s: macro ids must be unique and non-empty" % recipe_id)
			macro_ids[macro_id] = true
			var fields: Array = macro.get("fields", []) if macro.get("fields", []) is Array else []
			var mapping: Dictionary = macro.get("mapping", {}) if macro.get("mapping", {}) is Dictionary else {}
			if fields.is_empty():
				errors.append("%s/%s: visible macro fields missing" % [recipe_id, macro_id])
			if mapping.is_empty():
				errors.append("%s/%s: visible macro mapping missing" % [recipe_id, macro_id])
			for path in fields:
				if not authored_field_paths(str(recipe_id)).has(str(path)):
					errors.append("%s macro references an unauthored field: %s" % [recipe_id, str(path)])
			for raw_path in mapping.keys():
				var path := str(raw_path)
				var rule: Dictionary = mapping[raw_path] if mapping[raw_path] is Dictionary else {}
				if path not in fields:
					errors.append("%s/%s mapping key is not a declared macro field: %s" % [recipe_id, macro_id, path])
				if not _is_supported_field_path(path):
					errors.append("%s/%s mapping uses unsupported field: %s" % [recipe_id, macro_id, path])
				var instance_keys: Array = rule.get("instance_keys", []) if rule.get("instance_keys", []) is Array else []
				for raw_key in instance_keys:
					if not layer_keys.has(str(raw_key)):
						errors.append("%s/%s mapping target does not resolve: %s" % [recipe_id, macro_id, str(raw_key)])
				var operators: Array = rule.get("operators", []) if rule.get("operators", []) is Array else []
				for raw_operator in operators:
					if not (recipe.get("operator_ids", []) as Array).has(str(raw_operator)):
						errors.append("%s/%s mapping operator does not resolve: %s" % [recipe_id, macro_id, str(raw_operator)])
			var sample_doc: Dictionary
			if COMPOSITION_RECIPE_IDS.has(str(recipe_id)):
				sample_doc = (instantiated.get("composition", {}) as Dictionary).get("doc", {})
			else:
				sample_doc = FxLookScript.new_look("RECIPE_SAMPLE", str(recipe.get("name", recipe_id)))
				sample_doc["layers"].append_array(instantiated.get("layers", []))
			var sample: Variant = _macro_sample_value(str(recipe_id), macro)
			var sample_result: Dictionary = apply_macro_result(sample_doc, str(recipe_id), "registry-validation", macro_id, sample)
			if not bool(sample_result.get("ok", false)) or not bool(sample_result.get("changed", false)):
				errors.append("%s/%s sample value does not mutate a declared canonical target: %s" % [recipe_id, macro_id, str(sample_result.get("errors", []))])
	return {"ok": errors.is_empty(), "errors": errors}

static func _macro_sample_value(recipe_id: String, macro: Dictionary):
	var mapping: Dictionary = macro.get("mapping", {}) if macro.get("mapping", {}) is Dictionary else {}
	for raw_rule in mapping.values():
		if not (raw_rule is Dictionary):
			continue
		var rule: Dictionary = raw_rule
		var source := str(rule.get("source", "value"))
		if source == "anchor":
			return "VS_MARK"
		if source == "clock":
			return "FREE_RUN"
		if source == "option" or source == "mode":
			var options := _macro_option_map(recipe_id, str(macro.get("id", "")), str(mapping.keys()[0]))
			if not options.is_empty():
				return str(options.keys()[0])
		return 0.75
	return 0.75

static func _definition(recipe_id: String) -> Dictionary:
	match recipe_id:
		KINETIC_RUSH:
			return _decorate({
				"stable_id": KINETIC_RUSH,
				"name": "Kinetic Rush",
				"category": "Gold Recipe",
				"description": "A full-frame radial speedline field for forward motion and clash escalation, authored as a real final-composite operator.",
				"intent": "Kinetic final-frame acceleration",
				"operator_ids": ["speedlines_field"],
				"target_compatibility": {"target_roles": ["composition"], "element_roles": ["composition"], "allowed_planes": ["COMPOSITION_FOREGROUND"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [
					{"id": "ENERGY", "label": "Energy", "fields": ["fx.operator_strength", "fx.operator_distortion"], "mapping": {"fx.operator_strength": {"source": "value"}, "fx.operator_distortion": {"source": "value", "scale": 0.45}}},
					{"id": "DENSITY", "label": "Density", "fields": ["fx.operator_scale", "fx.operator_pattern_mode"], "mapping": {"fx.operator_scale": {"source": "value", "min": 0.5, "max": 2.5}, "fx.operator_pattern_mode": {"source": "value", "threshold": 0.72}}},
					{"id": "FOCUS", "label": "Focus", "fields": ["fx.operator_anchor"], "mapping": {"fx.operator_anchor": {"source": "anchor"}}},
					{"id": "DIRECTION", "label": "Direction", "fields": ["fx.operator_axis_x", "fx.operator_axis_y"], "mapping": {"fx.operator_axis_x": {"source": "value", "axis": "x"}, "fx.operator_axis_y": {"source": "value", "axis": "y"}}},
					{"id": "DISTORTION", "label": "Distortion", "fields": ["fx.operator_mix_mode"], "mapping": {"fx.operator_mix_mode": {"source": "mode"}}},
					{"id": "MOTION", "label": "Motion", "fields": ["fx.operator_time_source"], "mapping": {"fx.operator_time_source": {"source": "clock"}}},
				],
				"source_semantics": {"input": "FINAL_COMPOSITE_CAPTURE", "approximation": "NONE"},
				"layers": [{"instance_key": "kinetic_speedlines", "name": "Kinetic Speedlines", "type": "FX", "authored_fields": {
					"layer.plane": "COMPOSITION_FOREGROUND", "layer.lane": "FINAL_COMPOSITE", "layer.authority": "COMPOSITION", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"fx.operator": "speedlines_field", "fx.operator_anchor": "VS_MARK", "fx.operator_scope": "EXCLUDE_PRIMARY", "fx.operator_strength": 0.92, "fx.operator_scale": 1.1, "fx.operator_speed": 1.5, "fx.operator_pattern_mode": 0.0, "fx.operator_mix_mode": 2.0, "fx.operator_distortion": 0.38, "fx.operator_center_x": 0.5, "fx.operator_center_y": 0.5, "fx.operator_axis_x": 1.0, "fx.operator_axis_y": 0.0, "fx.operator_time_source": "PRESENTATION_TIME", "fx.operator_event_start": 0.56, "fx.operator_duration": 0.5, "fx.final_tint_amount": 0.0,
				}}],
			})
		PATTERN_CUT:
			return _decorate({
				"stable_id": PATTERN_CUT,
				"name": "Pattern Cut",
				"category": "Gold Recipe",
				"description": "A directional gradient with geometric breakup into a darkened captured-frame cut, followed by neutral recovery. Not a two-scene crossfade.",
				"intent": "Patterned transition cut",
				"operator_ids": ["pattern_transition"],
				"target_compatibility": {"target_roles": ["composition"], "element_roles": ["composition"], "allowed_planes": ["COMPOSITION_FOREGROUND"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [
					{"id": "PROGRESS", "label": "Progress", "fields": ["fx.operator_progress_start", "fx.operator_progress_end"], "mapping": {"fx.operator_progress_start": {"source": "value", "min": 0.0, "max": 1.0}, "fx.operator_progress_end": {"source": "value", "min": 0.0, "max": 1.0}}},
					{"id": "PATTERN", "label": "Pattern", "fields": ["fx.operator_pattern_family"], "mapping": {"fx.operator_pattern_family": {"source": "option"}}},
					{"id": "DIRECTION", "label": "Direction / Rotation", "fields": ["fx.operator_axis_x", "fx.operator_axis_y"], "mapping": {"fx.operator_axis_x": {"source": "value", "axis": "x"}, "fx.operator_axis_y": {"source": "value", "axis": "y"}}},
					{"id": "SCALE", "label": "Scale", "fields": ["fx.operator_scale"], "mapping": {"fx.operator_scale": {"source": "value", "min": 0.5, "max": 3.0}}},
					{"id": "SCROLL", "label": "Pattern Scroll", "fields": ["fx.operator_speed"], "mapping": {"fx.operator_speed": {"source": "value", "min": 0.0, "max": 3.0}}},
					{"id": "FEATHER", "label": "Feather", "fields": ["fx.operator_softness"], "mapping": {"fx.operator_softness": {"source": "value", "min": 0.01, "max": 0.5}}},
					{"id": "MOTION", "label": "Motion", "fields": ["fx.operator_time_source"], "mapping": {"fx.operator_time_source": {"source": "clock"}}},
				],
				"source_semantics": {"input": "FINAL_COMPOSITE_CAPTURE", "approximation": "NONE"},
				"layers": [{"instance_key": "pattern_cut", "name": "Pattern Cut", "type": "FX", "authored_fields": {
					"layer.plane": "COMPOSITION_FOREGROUND", "layer.lane": "FINAL_COMPOSITE", "layer.authority": "COMPOSITION", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"fx.operator": "pattern_transition", "fx.operator_strength": 0.78, "fx.operator_scale": 1.0, "fx.operator_speed": 1.0, "fx.operator_softness": 0.1, "fx.operator_pattern_family": 1.0, "fx.operator_progress": 0.0, "fx.operator_progress_start": 0.0, "fx.operator_progress_end": 1.0, "fx.operator_progress_mode": "EVENT_LINEAR", "fx.operator_axis_x": 1.0, "fx.operator_axis_y": 0.18, "fx.operator_time_source": "PRESENTATION_TIME", "fx.operator_event_start": 0.0, "fx.operator_duration": 0.5, "fx.operator_color_a": [0.25, 0.95, 1.0, 1.0], "fx.operator_color_b": [1.0, 0.35, 0.82, 1.0], "fx.final_tint_amount": 0.0,
				}}],
			})
		LIVING_CONTOUR:
			return _decorate({
				"stable_id": LIVING_CONTOUR,
				"name": "Living Contour",
				"category": "Gold Recipe",
				"description": "A source-alpha-aware eroded contour with clocked noise breakup; transparent space remains transparent.",
				"intent": "Living source contour",
				"operator_ids": ["noise_erosion_border"],
				"target_compatibility": {"target_roles": ["primary", "secondary", "side_field"], "element_roles": ["primary", "secondary", "side_field"], "allowed_planes": ["TARGET_OVERLAY", "TARGET_SOURCE"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [
					{"id": "LIFE", "label": "Life", "fields": ["fx.operator_strength"], "mapping": {"fx.operator_strength": {"source": "value"}}},
					{"id": "EDGE_DEPTH", "label": "Edge Depth", "fields": ["mask.width_px", "mask.feather_px"], "mapping": {"mask.width_px": {"source": "value", "min": 2.0, "max": 32.0}, "mask.feather_px": {"source": "value", "min": 0.0, "max": 8.0}}},
					{"id": "BREAKUP", "label": "Breakup", "fields": ["fx.operator_threshold"], "mapping": {"fx.operator_threshold": {"source": "value"}}},
					{"id": "TURBULENCE", "label": "Turbulence", "fields": ["fx.operator_scale", "fx.operator_speed"], "mapping": {"fx.operator_scale": {"source": "value"}, "fx.operator_speed": {"source": "value"}}},
					{"id": "DRIFT", "label": "Drift", "fields": ["fx.operator_axis_x", "fx.operator_axis_y"], "mapping": {"fx.operator_axis_x": {"source": "value", "axis": "x"}, "fx.operator_axis_y": {"source": "value", "axis": "y"}}},
					{"id": "INTENSITY", "label": "Intensity", "fields": ["fx.operator_strength"], "mapping": {"fx.operator_strength": {"source": "value"}}},
				],
				"source_semantics": {"input": "ORIGINAL_SOURCE_ALPHA", "mask_source": "ORIGINAL_SOURCE_ALPHA", "approximation": "NONE"},
				"layers": [{"instance_key": "living_contour", "name": "Living Contour", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.lane": "TARGET_LOCAL", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "ADD",
					"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "EDGE_BAND", "mask.space": "SOURCE_SPACE", "mask.width_px": 18.0, "mask.feather_px": 3.0,
					"fx.operator": "noise_erosion_border", "fx.operator_strength": 0.84, "fx.operator_scale": 1.0, "fx.operator_speed": 1.1, "fx.operator_threshold": 0.48, "fx.operator_softness": 0.12, "fx.operator_axis_x": 1.0, "fx.operator_axis_y": 0.0, "fx.operator_time_source": "PRESENTATION_TIME",
				}}],
			})
		SIGNAL_MELT:
			return _decorate({
				"stable_id": SIGNAL_MELT,
				"name": "Signal Melt",
				"category": "Gold Recipe",
				"description": "A directional luminance-run smear that selects from the resolved local input instead of faking motion with RGB separation or dither.",
				"intent": "Directional signal smear",
				"operator_ids": ["pixel_sort_smear"],
				"target_compatibility": {"target_roles": ["echo"], "element_roles": ["echo"], "allowed_planes": ["TARGET_OVERLAY", "TARGET_SOURCE"], "requires_fighter": false, "primary_intent": "ECHO"},
				"advanced_access": true,
				"macros": [
					{"id": "MELT", "label": "Melt", "fields": ["fx.operator_strength", "fx.operator_scale"], "mapping": {"fx.operator_strength": {"source": "value"}, "fx.operator_scale": {"source": "value", "min": 0.5, "max": 4.0}}},
					{"id": "THRESHOLD", "label": "Threshold", "fields": ["fx.operator_threshold"], "mapping": {"fx.operator_threshold": {"source": "value"}}},
					{"id": "SOFTNESS", "label": "Softness", "fields": ["fx.operator_softness"], "mapping": {"fx.operator_softness": {"source": "value", "min": 0.01, "max": 0.5}}},
					{"id": "DIRECTION", "label": "Direction", "fields": ["fx.operator_axis_x", "fx.operator_axis_y"], "mapping": {"fx.operator_axis_x": {"source": "value", "axis": "x"}, "fx.operator_axis_y": {"source": "value", "axis": "y"}}},
					{"id": "TURBULENCE", "label": "Turbulence", "fields": ["fx.operator_speed"], "mapping": {"fx.operator_speed": {"source": "value", "min": 0.0, "max": 3.0}}},
					{"id": "CHROMATIC_SPLIT", "label": "Chromatic Split", "fields": ["fx.operator_mix_mode"], "mapping": {"fx.operator_mix_mode": {"source": "mode"}}},
				],
				"source_semantics": {"input": "LOCAL_RESOLVED_INPUT", "approximation": "NONE"},
				"layers": [{"instance_key": "signal_melt", "name": "Signal Melt", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.lane": "TARGET_LOCAL", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"fx.operator": "pixel_sort_smear", "fx.operator_strength": 0.98, "fx.operator_scale": 2.4, "fx.operator_speed": 1.0, "fx.operator_threshold": 0.32, "fx.operator_softness": 0.08, "fx.operator_mix_mode": 0.0, "fx.operator_axis_x": 1.0, "fx.operator_axis_y": 0.0, "fx.operator_time_source": "PRESENTATION_TIME",
				}}],
			})
		VACUUM_CLASH:
			return _decorate({
				"stable_id": VACUUM_CLASH,
				"name": "Vacuum Clash",
				"category": "Gold Recipe",
				"description": "A radial inward pull and moving burst ring over the captured final frame for clash punctuation.",
				"intent": "Radial clash vacuum",
				"operator_ids": ["vacuum_burst"],
				"target_compatibility": {"target_roles": ["composition"], "element_roles": ["composition"], "allowed_planes": ["COMPOSITION_FOREGROUND"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [
					{"id": "STRENGTH", "label": "Strength", "fields": ["fx.operator_strength"], "mapping": {"fx.operator_strength": {"source": "value"}}},
					{"id": "POLARITY", "label": "Pull / Push", "fields": ["fx.operator_polarity"], "mapping": {"fx.operator_polarity": {"source": "option"}}},
					{"id": "RADIUS", "label": "Radius", "fields": ["fx.operator_scale"], "mapping": {"fx.operator_scale": {"source": "value", "min": 0.5, "max": 3.0}}},
					{"id": "WOBBLE", "label": "Wobble", "fields": ["fx.operator_speed", "fx.operator_distortion"], "mapping": {"fx.operator_speed": {"source": "value"}, "fx.operator_distortion": {"source": "value", "scale": 0.4}}},
					{"id": "DURATION", "label": "Duration", "fields": ["fx.operator_duration"], "mapping": {"fx.operator_duration": {"source": "value", "min": 0.05, "max": 3.0}}},
				],
				"source_semantics": {"input": "FINAL_COMPOSITE_CAPTURE", "approximation": "NONE"},
				"layers": [{"instance_key": "vacuum_clash", "name": "Vacuum Clash", "type": "FX", "authored_fields": {
					"layer.plane": "COMPOSITION_FOREGROUND", "layer.lane": "FINAL_COMPOSITE", "layer.authority": "COMPOSITION", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"fx.operator": "vacuum_burst", "fx.operator_anchor": "VS_MARK", "fx.operator_scope": "EXCLUDE_PRIMARY", "fx.operator_strength": 1.0, "fx.operator_scale": 1.5, "fx.operator_speed": 1.3, "fx.operator_distortion": 0.0, "fx.operator_center_x": 0.5, "fx.operator_center_y": 0.5, "fx.operator_polarity": 0.0, "fx.operator_time_source": "PRESENTATION_TIME", "fx.operator_event_start": 0.58, "fx.operator_duration": 0.34, "fx.operator_color_a": [0.25, 0.95, 1.0, 1.0], "fx.operator_color_b": [1.0, 0.35, 0.82, 1.0], "fx.final_tint_amount": 0.0,
				}}],
			})
		CLASH_OVERDRIVE:
			return _decorate({
				"stable_id": CLASH_OVERDRIVE,
				"name": "Clash Overdrive",
				"category": "Gold Recipe",
				"description": "A focused clash choreography: restrained vacuum anticipation, fixed-axis speedline impact, and an exact neutral release.",
				"intent": "Primary-protected clash overdrive",
				"operator_ids": ["vacuum_burst", "speedlines_field"],
				"target_compatibility": {"target_roles": ["composition"], "element_roles": ["composition"], "allowed_planes": ["COMPOSITION_FOREGROUND"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [
					{"id": "IMPACT", "label": "Impact", "fields": ["fx.operator_strength"], "mapping": {"fx.operator_strength": {"source": "value", "operators": ["vacuum_burst", "speedlines_field"]}}},
					{"id": "DIRECTION", "label": "Direction", "fields": ["fx.operator_axis_x", "fx.operator_axis_y"], "mapping": {"fx.operator_axis_x": {"source": "value", "axis": "x", "operators": ["speedlines_field"]}, "fx.operator_axis_y": {"source": "value", "axis": "y", "operators": ["speedlines_field"]}}},
					{"id": "DISTORTION", "label": "Distortion", "fields": ["fx.operator_mix_mode"], "mapping": {"fx.operator_mix_mode": {"source": "mode", "operators": ["speedlines_field"]}}},
					{"id": "DURATION", "label": "Duration", "fields": ["fx.operator_duration"], "mapping": {"fx.operator_duration": {"source": "value", "min": 0.1, "max": 3.0}}},
				],
				"source_semantics": {"input": "FINAL_COMPOSITE_CAPTURE", "composition": "VACUUM_SPEEDLINES", "scope": "EXCLUDE_PRIMARY", "approximation": "NONE"},
				"layers": [
					{"instance_key": "clash_vacuum", "name": "Clash Vacuum Anticipation", "type": "FX", "authored_fields": {
						"layer.plane": "COMPOSITION_FOREGROUND", "layer.lane": "FINAL_COMPOSITE", "layer.authority": "COMPOSITION", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
						"fx.operator": "vacuum_burst", "fx.operator_anchor": "VS_MARK", "fx.operator_strength": 0.94, "fx.operator_scale": 1.0, "fx.operator_speed": 1.3, "fx.operator_center_x": 0.5, "fx.operator_center_y": 0.5, "fx.operator_polarity": 0.0, "fx.operator_scope": "EXCLUDE_PRIMARY", "fx.operator_time_source": "PRESENTATION_TIME", "fx.operator_event_start": 0.46, "fx.operator_duration": 0.20, "fx.final_tint_amount": 0.0,
					}},
					{"instance_key": "clash_speedlines", "name": "Clash Speedline Burst", "type": "FX", "authored_fields": {
						"layer.plane": "COMPOSITION_FOREGROUND", "layer.lane": "FINAL_COMPOSITE", "layer.authority": "COMPOSITION", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
						"fx.operator": "speedlines_field", "fx.operator_anchor": "VS_MARK", "fx.operator_strength": 0.96, "fx.operator_scale": 1.1, "fx.operator_speed": 1.5, "fx.operator_pattern_mode": 0.0, "fx.operator_mix_mode": 2.0, "fx.operator_distortion": 0.72, "fx.operator_scope": "EXCLUDE_PRIMARY", "fx.operator_center_x": 0.5, "fx.operator_center_y": 0.5, "fx.operator_axis_x": 1.0, "fx.operator_axis_y": 0.0, "fx.operator_event_start": 0.60, "fx.operator_duration": 0.42, "fx.operator_time_source": "PRESENTATION_TIME", "fx.final_tint_amount": 0.0,
					}},
				],
			})
		PRIMARY_FLAME_ENERGY:
			return _decorate({
				"stable_id": PRIMARY_FLAME_ENERGY,
				"name": "Primary Flame Energy",
				"category": "Hero Recipe",
				"description": "A layered flame-energy wake behind the PRIMARY fighter, combining alpha-gated fringe, flow, a named driver and event motion.",
				"intent": "Behind PRIMARY fighter",
				"target_compatibility": {
					"target_roles": ["primary"],
					"element_roles": ["primary"],
					"allowed_planes": ["TARGET_UNDERLAY"],
					"requires_fighter": true,
				},
				"advanced_access": true,
				"macros": [
					{"id": "FLAME_EDGE", "label": "Flame Edge", "fields": ["fx.fringe", "fx.edge_width", "fx.fringe_bleed"], "mapping": {"fx.fringe": {"source": "value", "min": 0.2, "max": 1.4, "instance_keys": ["flame_fringe"]}, "fx.edge_width": {"source": "value", "min": 4.0, "max": 24.0, "instance_keys": ["flame_fringe"]}, "fx.fringe_bleed": {"source": "value", "min": 0.0, "max": 1.0, "instance_keys": ["flame_fringe"]}}},
					{"id": "FLAME_FLOW", "label": "Flame Flow", "fields": ["fx.flow", "fx.flow_strength", "fx.driver_mode"], "mapping": {"fx.flow": {"source": "value", "min": 0.0, "max": 1.0, "instance_keys": ["flame_flow"]}, "fx.flow_strength": {"source": "value", "min": 0.5, "max": 3.0, "instance_keys": ["flame_flow"]}, "fx.driver_mode": {"source": "value", "min": 0.0, "max": 16.0, "instance_keys": ["flame_flow"]}}},
					{"id": "FLAME_MOTION", "label": "Impact Motion", "fields": ["motion.enabled.fringe", "motion.enabled.flow"], "mapping": {"motion.enabled.fringe": {"source": "value", "threshold": 0.5, "instance_keys": ["flame_fringe"]}, "motion.enabled.flow": {"source": "value", "threshold": 0.5, "instance_keys": ["flame_flow"]}}},
				],
				"source_semantics": {"mask_source": "ORIGINAL_SOURCE_ALPHA", "mask_space": "SOURCE_SPACE", "plane": "TARGET_UNDERLAY"},
				"layers": [
					{
						"instance_key": "flame_fringe",
						"name": "Primary Flame Fringe",
						"type": "FX",
						"authored_fields": {
							"layer.plane": "TARGET_UNDERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "ADD",
							"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "OUTER_BAND", "mask.space": "SOURCE_SPACE", "mask.width_px": 10.0, "mask.feather_px": 4.0,
							"fx.fringe": 1.15, "fx.intensity": 1.15, "fx.edge_width": 14.0, "fx.wind_reach": 48.0, "fx.wind_trail": 0.85, "fx.fringe_bleed": 0.90, "fx.edge_source_mode": 0.0,
							"motion.enabled.fringe": true, "motion.tracks.fringe.anchor": "clash_impact", "motion.tracks.fringe.delay": 0.03, "motion.tracks.fringe.attack": 0.08, "motion.tracks.fringe.hold": 0.18, "motion.tracks.fringe.release": 0.34, "motion.tracks.fringe.sustain": 0.85,
						},
					},
					{
						"instance_key": "flame_flow",
						"name": "Primary Flame Flow",
						"type": "FX",
						"authored_fields": {
							"layer.plane": "TARGET_UNDERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "SCREEN",
							"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "FULL", "mask.space": "SOURCE_SPACE", "mask.feather_px": 3.0,
							"fx.flow": 1.0, "fx.flow_strength": 2.2, "fx.driver_mode": 8.0, "fx.DRIVER_FLOW": 0.9, "fx.wind_reach": 32.0, "fx.wind_trail": 0.60,
							"displacement.enabled": true, "displacement.driver": "FRINGE_DRIVER", "displacement.amount_px": [7.0, 3.0], "displacement.scale": 1.5, "displacement.speed": 0.85, "displacement.seed": 17,
							"motion.enabled.flow": true, "motion.tracks.flow.anchor": "clash_impact", "motion.tracks.flow.delay": 0.05, "motion.tracks.flow.attack": 0.10, "motion.tracks.flow.hold": 0.20, "motion.tracks.flow.release": 0.40, "motion.tracks.flow.sustain": 0.75,
						},
					},
					{
						"instance_key": "flame_core",
						"name": "Primary Flame Core",
						"type": "FX",
						"authored_fields": {
							"layer.plane": "TARGET_UNDERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "ADD",
							"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "INNER_BAND", "mask.space": "SOURCE_SPACE", "mask.width_px": 5.0, "mask.feather_px": 2.0,
							"fx.fringe": 0.55, "fx.flow": 0.55, "fx.intensity": 1.05, "fx.driver_mode": 8.0, "fx.edge_source_mode": 0.0,
							"motion.enabled.fringe": true, "motion.enabled.flow": true, "motion.tracks.fringe.anchor": "fixed", "motion.tracks.flow.anchor": "fixed",
						},
					},
				],
			})
		ORGANIC_SIDE_FIELD:
			return _decorate({
				"stable_id": ORGANIC_SIDE_FIELD,
				"name": "Organic Side Field",
				"category": "Hero Recipe",
				"description": "An irregular side-field treatment driven by the actual source alpha contour, never a rectangle or radial approximation.",
				"intent": "Follow actual irregular side-field source alpha",
				"target_compatibility": {
					"target_roles": ["side_field"],
					"element_roles": ["side_field"],
					"allowed_planes": ["TARGET_SOURCE", "TARGET_OVERLAY"],
					"requires_fighter": false,
				},
				"advanced_access": true,
				"macros": [
					{"id": "ORGANIC_CONTOUR", "label": "Organic Contour", "fields": ["fx.edge_source_mode", "fx.edge_width"], "mapping": {"fx.edge_source_mode": {"source": "value", "threshold": 0.5, "instance_keys": ["organic_alpha", "organic_contour"]}, "fx.edge_width": {"source": "value", "min": 4.0, "max": 24.0, "instance_keys": ["organic_contour"]}}},
					{"id": "ORGANIC_FLOW", "label": "Contour Flow", "fields": ["fx.flow", "fx.flow_strength", "fx.driver_mode"], "mapping": {"fx.flow": {"source": "value", "min": 0.0, "max": 1.0, "instance_keys": ["organic_alpha"]}, "fx.flow_strength": {"source": "value", "min": 0.5, "max": 3.0, "instance_keys": ["organic_alpha"]}, "fx.driver_mode": {"source": "value", "min": 0.0, "max": 16.0, "instance_keys": ["organic_alpha"]}}},
					{"id": "ORGANIC_MOTION", "label": "Field Motion", "fields": ["motion.enabled.fringe", "motion.enabled.flow"], "mapping": {"motion.enabled.fringe": {"source": "value", "threshold": 0.5, "instance_keys": ["organic_alpha"]}, "motion.enabled.flow": {"source": "value", "threshold": 0.5, "instance_keys": ["organic_alpha"]}}},
				],
				"source_semantics": {"mask_source": "ORIGINAL_SOURCE_ALPHA", "mask_space": "SOURCE_SPACE", "edge_source_mode": "ALPHA", "approximation": "NONE"},
				"layers": [
					{
						"instance_key": "organic_alpha",
						"name": "Organic Alpha Field",
						"type": "FX",
						"authored_fields": {
							"layer.plane": "TARGET_SOURCE", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "SCREEN",
							"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "FULL", "mask.space": "SOURCE_SPACE", "mask.feather_px": 1.5,
							"fx.edge_source_mode": 0.0, "fx.edge_alpha_weight": 2.0, "fx.edge_luma_weight": 0.0, "fx.edge_threshold": 0.035, "fx.edge_width": 16.0,
							"fx.fringe": 0.80, "fx.flow": 0.90, "fx.flow_strength": 1.60, "fx.driver_mode": 10.0, "fx.DRIVER_FLOW": 0.80,
							"motion.enabled.fringe": true, "motion.enabled.flow": true, "motion.tracks.fringe.anchor": "hold_enter", "motion.tracks.flow.anchor": "hold_enter", "motion.tracks.fringe.attack": 0.16, "motion.tracks.flow.attack": 0.20,
						},
					},
					{
						"instance_key": "organic_contour",
						"name": "Organic Alpha Contour",
						"type": "FX",
						"authored_fields": {
							"layer.plane": "TARGET_OVERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "ADD",
							"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "EDGE_BAND", "mask.space": "SOURCE_SPACE", "mask.width_px": 7.0, "mask.feather_px": 2.0,
							"fx.edge_source_mode": 0.0, "fx.edge_alpha_weight": 2.5, "fx.edge_luma_weight": 0.0, "fx.edge_threshold": 0.05, "fx.edge_width": 11.0,
							"fx.fringe": 0.65, "fx.flow": 0.45, "fx.flow_strength": 1.20, "fx.driver_mode": 10.0, "fx.wind_reach": 22.0, "fx.wind_trail": 0.30,
							"motion.enabled.fringe": true, "motion.tracks.fringe.anchor": "fixed", "motion.tracks.fringe.attack": 0.12, "motion.tracks.fringe.release": 0.30,
						},
					},
				],
			})
		EDGE_HALO:
			return _decorate({
				"stable_id": EDGE_HALO,
				"name": "Edge Halo",
				"category": "Curated Preset",
				"description": "A restrained alpha-contour halo that clarifies the silhouette without turning the fighter into a glowing cutout.",
				"intent": "Readable silhouette edge",
				"target_compatibility": {"target_roles": ["primary", "secondary"], "element_roles": ["primary", "secondary"], "allowed_planes": ["TARGET_OVERLAY"], "requires_fighter": true},
				"advanced_access": true,
				"macros": [{"id": "HALO_EDGE", "label": "Edge Halo", "fields": ["fx.edge_width", "fx.fringe", "fx.intensity"], "mapping": {"fx.edge_width": {"source": "value", "min": 2.0, "max": 20.0, "instance_keys": ["edge_halo"]}, "fx.fringe": {"source": "value", "min": 0.0, "max": 1.5, "instance_keys": ["edge_halo"]}, "fx.intensity": {"source": "value", "min": 0.0, "max": 2.0, "instance_keys": ["edge_halo"]}}}],
				"source_semantics": {"mask_source": "ORIGINAL_SOURCE_ALPHA", "mask_space": "SOURCE_SPACE", "approximation": "NONE"},
				"layers": [{"instance_key": "edge_halo", "name": "Edge Halo", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "ADD",
					"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "EDGE_BAND", "mask.space": "SOURCE_SPACE", "mask.width_px": 8.0, "mask.feather_px": 3.0,
					"fx.edge_source_mode": 0.0, "fx.edge_width": 9.0, "fx.fringe": 0.65, "fx.intensity": 1.08, "fx.fringe_bleed": 0.55,
				}}],
			})
		RGB_TEAR:
			return _decorate({
				"stable_id": RGB_TEAR,
				"name": "RGB Tear",
				"category": "Curated Preset",
				"description": "A controlled chromatic split for impact and transition moments, with the source alpha kept as the authority.",
				"intent": "Chromatic impact accent",
				"target_compatibility": {"target_roles": ["primary", "secondary"], "element_roles": ["primary", "secondary"], "allowed_planes": ["TARGET_OVERLAY"], "requires_fighter": true},
				"advanced_access": true,
				"macros": [{"id": "RGB_IMPACT", "label": "RGB Impact", "fields": ["fx.rgb", "fx.rgb_shift_amount", "fx.rgb_shift_alpha"], "mapping": {"fx.rgb": {"source": "value", "min": 0.0, "max": 1.0, "instance_keys": ["rgb_tear"]}, "fx.rgb_shift_amount": {"source": "value", "min": 0.0, "max": 16.0, "instance_keys": ["rgb_tear"]}, "fx.rgb_shift_alpha": {"source": "value", "min": 0.0, "max": 1.0, "instance_keys": ["rgb_tear"]}}}],
				"source_semantics": {"mask_source": "ORIGINAL_SOURCE_ALPHA", "mask_space": "SOURCE_SPACE", "approximation": "NONE"},
				"layers": [{"instance_key": "rgb_tear", "name": "RGB Tear", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "SCREEN",
					"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "FULL", "mask.space": "SOURCE_SPACE", "mask.feather_px": 2.0,
					"fx.rgb": 0.78, "fx.rgb_shift_amount": 9.0, "fx.rgb_shift_alpha": 0.35, "fx.intensity": 0.92,
				}}],
			})
		DITHER_TREATMENT:
			return _decorate({
				"stable_id": DITHER_TREATMENT,
				"name": "Dither Treatment",
				"category": "Curated Preset",
				"description": "A small-pixel breakup for graphic texture and controlled degradation, balanced to remain production-readable.",
				"intent": "Graphic texture breakup",
				"target_compatibility": {"target_roles": ["primary", "secondary", "side_field"], "element_roles": ["primary", "secondary", "side_field"], "allowed_planes": ["TARGET_OVERLAY", "TARGET_SOURCE"], "requires_fighter": false},
				"advanced_access": true,
				"macros": [{"id": "DITHER_TEXTURE", "label": "Dither Texture", "fields": ["fx.dither", "fx.dither_pixel", "fx.dither_contrast", "fx.dither_gamma"], "mapping": {"fx.dither": {"source": "value", "min": 0.0, "max": 1.0, "instance_keys": ["dither_treatment"]}, "fx.dither_pixel": {"source": "value", "min": 1.0, "max": 8.0, "instance_keys": ["dither_treatment"]}, "fx.dither_contrast": {"source": "value", "min": 0.5, "max": 2.5, "instance_keys": ["dither_treatment"]}, "fx.dither_gamma": {"source": "value", "min": 0.5, "max": 2.5, "instance_keys": ["dither_treatment"]}}}],
				"source_semantics": {"mask_source": "ORIGINAL_SOURCE_ALPHA", "mask_space": "SOURCE_SPACE", "approximation": "NONE"},
				"layers": [{"instance_key": "dither_treatment", "name": "Dither Treatment", "type": "FX", "authored_fields": {
					"layer.plane": "TARGET_OVERLAY", "layer.input": "ORIGINAL_SOURCE", "layer.blend_mode": "NORMAL",
					"mask.enabled": true, "mask.source": "ORIGINAL_SOURCE_ALPHA", "mask.region": "FULL", "mask.space": "SOURCE_SPACE", "mask.feather_px": 1.0,
					"fx.dither": 0.55, "fx.dither_pixel": 2.0, "fx.dither_contrast": 1.4, "fx.dither_gamma": 1.25, "fx.intensity": 0.90,
				}}],
			})
	return {}

static func _decorate(recipe: Dictionary) -> Dictionary:
	var out := recipe.duplicate(true)
	var group := "CHARACTER"
	match str(out.get("stable_id", "")):
		KINETIC_RUSH, VACUUM_CLASH:
			group = "MOTION / IMPACT"
		PATTERN_CUT:
			group = "GRAPHIC TRANSITION"
		CLASH_OVERDRIVE:
			group = "SIGNATURE"
		EDGE_HALO, RGB_TEAR, DITHER_TREATMENT:
			group = "BASIC PRESETS"
	out["library_group"] = group
	var all_fields: Dictionary = {}
	for raw_spec in out.get("layers", []):
		var spec: Dictionary = raw_spec
		for path in (spec.get("authored_fields", {}) as Dictionary).keys():
			all_fields["%s.%s" % [str(spec.get("instance_key", "layer")), str(path)]] = (spec["authored_fields"] as Dictionary)[path]
	out["authored_fields"] = all_fields
	out["canonical_fields"] = authored_field_paths_from_recipe(out)
	out["macro_metadata"] = out.get("macros", []).duplicate(true)
	if COMPOSITION_RECIPE_IDS.has(str(out.get("stable_id", ""))):
		out["ownership"] = "COMPOSITION"
		out["composition_passes"] = out.get("layers", []).duplicate(true)
	else:
		out["ownership"] = "TARGET_LOOK"
	return out

static func authored_field_paths_from_recipe(recipe: Dictionary) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for raw_spec in recipe.get("layers", []):
		for path in (raw_spec as Dictionary).get("authored_fields", {}).keys():
			var text := str(path)
			if not seen.has(text):
				seen[text] = true
				out.append(text)
	return out

static func _restore_authored_fields(layer: Dictionary, spec: Dictionary) -> void:
	var authored: Dictionary = spec.get("authored_fields", {})
	for raw_path in authored.keys():
		_set_field(layer, str(raw_path), authored[raw_path])

static func _set_field(layer: Dictionary, path: String, value) -> bool:
	if not _is_supported_field_path(path):
		return false
	var parts := path.split(".")
	if str(parts[0]) == "layer":
		parts = parts.slice(1)
	var cursor: Variant = layer
	for i in range(parts.size() - 1):
		if not (cursor is Dictionary):
			return false
		var dict: Dictionary = cursor
		var key := str(parts[i])
		if not dict.has(key) or not (dict[key] is Dictionary):
			return false
		cursor = dict[key]
	if not (cursor is Dictionary):
		return false
	(cursor as Dictionary)[str(parts[parts.size() - 1])] = value
	return true

static func _get_field(layer: Dictionary, path: String):
	if not _is_supported_field_path(path):
		return null
	var cursor: Variant = layer
	var parts := path.split(".")
	if str(parts[0]) == "layer":
		parts = parts.slice(1)
	for part in parts:
		if not (cursor is Dictionary):
			return null
		var dict: Dictionary = cursor
		if not dict.has(str(part)):
			return null
		cursor = dict[str(part)]
	return cursor

static func _is_supported_field_path(path: String) -> bool:
	var parts := path.split(".")
	if parts.size() < 2:
		return false
	if str(parts[0]) == "layer":
		return parts.size() == 2 and str(parts[1]) in ["plane", "lane", "authority", "input", "blend_mode"]
	return str(parts[0]) in ["transform", "displacement", "mask", "fx", "motion"]

static func _diff_paths(neutral: Dictionary, actual: Dictionary, prefix := "") -> Array:
	var out: Array = []
	for raw_key in neutral.keys():
		var key := str(raw_key)
		if key in ["layer_id", "name", "type"]:
			continue
		if not actual.has(key):
			continue
		var path := key if prefix == "" else prefix + "." + key
		if prefix == "" and key in ["plane", "lane", "authority", "input", "blend_mode"]:
			path = "layer." + key
		var before = neutral[key]
		var after = actual[key]
		if before is Dictionary and after is Dictionary:
			out.append_array(_diff_paths(before, after, path))
		elif not FxLookScript.equivalent(before, after):
			out.append(path)
	return out

static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var out := ""
	var previous_separator := false
	for i in range(raw.length()):
		var c := raw[i]
		var valid := (c >= "a" and c <= "z") or (c >= "0" and c <= "9")
		if valid:
			out += c
			previous_separator = false
		elif not previous_separator:
			out += "-"
			previous_separator = true
		if out.length() >= 48:
			break
	while out.begins_with("-"):
		out = out.substr(1)
	while out.ends_with("-"):
		out = out.substr(0, out.length() - 1)
	return out if out != "" else "key"
