extends RefCounted
class_name FxComposition
# Explicit composition authority for full-frame FINAL_COMPOSITE passes.
# Target Looks own target-local layers; this document owns ordered scene passes.

const SCHEMA := "NRCU_FX_COMPOSITION_V0_1"
const STATUS_VALUES := ["DRAFT", "PRODUCTION"]
const OPERATORS := ["NONE", "speedlines_field", "pattern_transition", "vacuum_burst"]
const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxOperatorsScript := preload("res://scripts/fx_vnext/fx_operators.gd")

static func new_document(composition_id: String, name := "Composition") -> Dictionary:
	return {
		"schema": SCHEMA,
		"composition_id": composition_id,
		"name": name,
		"revision": 1,
		"status": "DRAFT",
		"final_passes": [],
		"metadata": {},
	}

static func materialize(raw: Dictionary) -> Dictionary:
	var doc := new_document(str(raw.get("composition_id", "")), str(raw.get("name", "Composition")))
	for key in ["schema", "revision", "status", "metadata"]:
		if raw.has(key):
			doc[key] = raw[key]
	var passes: Array = []
	for raw_pass in raw.get("final_passes", []):
		if not (raw_pass is Dictionary):
			continue
		var source: Dictionary = raw_pass
		var operator_id := str(source.get("operator", "NONE"))
		var fx: Dictionary = source.get("fx", {}) if source.get("fx", {}) is Dictionary else {}
		var seed: Dictionary = FxLookScript.new_layer("FX", str(source.get("name", operator_id)))
		seed["lane"] = str(source.get("lane", ""))
		seed["plane"] = str(source.get("plane", ""))
		seed["authority"] = str(source.get("authority", ""))
		seed["layer_id"] = str(source.get("pass_id", ""))
		# FxLook.materialize is the canonical FX sanitizer: only schema fields and
		# valid x_* extensions survive. Feed raw FX into it before reading the
		# canonical result; merging after materialization would leak unknown keys.
		seed["fx"] = fx.duplicate(true)
		var materialized: Dictionary = FxLookScript.materialize({"layers": [seed]})
		var canonical: Dictionary = materialized.get("layers", [seed])[0]
		var canonical_fx: Dictionary = canonical.get("fx", {})
		canonical_fx["operator"] = operator_id
		var event_start := float(source.get("event_start", canonical_fx.get("operator_event_start", 0.0)))
		var duration := float(source.get("duration", canonical_fx.get("operator_duration", 0.0)))
		canonical_fx["operator_event_start"] = event_start
		canonical_fx["operator_duration"] = duration
		canonical["fx"] = canonical_fx
		passes.append({
			"pass_id": str(source.get("pass_id", "")),
			"name": str(source.get("name", operator_id)),
			"operator": operator_id,
			"enabled": bool(source.get("enabled", true)),
			"event_start": event_start,
			"duration": duration,
			"lane": str(source.get("lane", "")),
			"plane": str(source.get("plane", "")),
			"authority": str(source.get("authority", "")),
			"fx": canonical_fx,
		})
	doc["final_passes"] = passes
	return doc

static func validate(raw: Dictionary) -> Dictionary:
	var doc := materialize(raw)
	var errors: Array = []
	if str(doc.get("schema", "")) != SCHEMA:
		errors.append("composition schema must be %s" % SCHEMA)
	if str(doc.get("composition_id", "")).strip_edges() == "":
		errors.append("composition_id must not be empty")
	if int(doc.get("revision", 0)) < 1:
		errors.append("composition revision must be >= 1")
	if not STATUS_VALUES.has(str(doc.get("status", ""))):
		errors.append("composition status must be DRAFT or PRODUCTION")
	var ids: Dictionary = {}
	for raw_pass in doc.get("final_passes", []):
		var composition_pass: Dictionary = raw_pass
		var pass_id := str(composition_pass.get("pass_id", ""))
		if pass_id == "" or ids.has(pass_id):
			errors.append("final_pass pass_id must be unique and non-empty")
		ids[pass_id] = true
		var operator_id := str(composition_pass.get("operator", ""))
		if not OPERATORS.has(operator_id):
			errors.append("unsupported composition operator: " + operator_id)
		if str(composition_pass.get("lane", "")) != "FINAL_COMPOSITE" or str(composition_pass.get("authority", "")) != "COMPOSITION":
			errors.append("composition pass %s has invalid ownership" % pass_id)
		if not is_finite(float(composition_pass.get("event_start", 0.0))) or not is_finite(float(composition_pass.get("duration", 0.0))):
			errors.append("composition pass %s has non-finite timing" % pass_id)
		if float(composition_pass.get("event_start", 0.0)) < 0.0 or float(composition_pass.get("duration", 0.0)) < 0.0:
			errors.append("composition pass %s has negative timing" % pass_id)
		var fx: Dictionary = composition_pass.get("fx", {})
		var fx_errors: Array = FxLookScript._validate_fx(fx, pass_id, str(composition_pass.get("lane", "")))
		errors.append_array(fx_errors)
		if operator_id != "NONE":
			var layer := _pass_to_layer(composition_pass)
			var lane_check := FxOperatorsScript.validate_layer_lane(layer)
			if not bool(lane_check.get("ok", false)):
				errors.append_array(lane_check.get("errors", []))
	return {"ok": errors.is_empty(), "errors": errors, "doc": doc}

static func to_layers(raw: Dictionary) -> Array:
	var doc := materialize(raw)
	var out: Array = []
	for raw_pass in doc.get("final_passes", []):
		var composition_pass: Dictionary = raw_pass
		if not bool(composition_pass.get("enabled", true)) or str(composition_pass.get("operator", "NONE")) == "NONE":
			continue
		out.append(_pass_to_layer(composition_pass))
	return out

static func _pass_to_layer(composition_pass: Dictionary) -> Dictionary:
	var layer := FxLookScript.new_layer("FX", str(composition_pass.get("name", composition_pass.get("operator", "Final Pass"))))
	layer["layer_id"] = str(composition_pass.get("pass_id", ""))
	layer["lane"] = "FINAL_COMPOSITE"
	layer["plane"] = "COMPOSITION_FOREGROUND"
	layer["authority"] = "COMPOSITION"
	var raw_fx = composition_pass.get("fx", {})
	layer["fx"] = (raw_fx as Dictionary).duplicate(true) if raw_fx is Dictionary else {}
	var fx: Dictionary = layer["fx"]
	fx["operator"] = str(composition_pass.get("operator", "NONE"))
	fx["operator_event_start"] = float(composition_pass.get("event_start", fx.get("operator_event_start", 0.0)))
	fx["operator_duration"] = float(composition_pass.get("duration", fx.get("operator_duration", 0.0)))
	layer["fx"] = fx
	# Re-materialize after adding composition-owned operator/timing fields so
	# runtime layers use the exact same canonical FX surface as persistence.
	return FxLookScript.materialize({"layers": [layer]}).get("layers", [layer])[0]

static func save_text(raw: Dictionary) -> String:
	return JSON.stringify(materialize(raw), "\t", false)
