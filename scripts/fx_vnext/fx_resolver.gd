class_name FxResolver
extends RefCounted
# NRCU FX Lab vNext — shared assignment resolver (specs/09 §1–§2).
#
# The single source of truth for "which Look applies to this target context".
# Lab and game runtime consume this module literally; no second resolution
# implementation is allowed. Pure data: no UI, no rendering.

# Specificity weights — specs/09 §1.2. Do not change without a spec revision.
const WEIGHTS := {
	"element_id": 100,
	"fighter_id": 50,
	"element_role": 20,
	"presentation_slot": 12,
	"visual_side": 8,
	"team_side": 6,
	"mode_family": 5,
	"stage_id": 5,
}

const SELECTOR_FIELDS := ["element_id", "fighter_id", "element_role", "visual_side", "presentation_slot", "team_side", "mode_family", "stage_id"]

const ASSIGNMENTS_SCHEMA := "NRCU_VS_FX_ASSIGNMENTS_V2"

static var _serial := 0

# ---------------------------------------------------------------- selectors

static func normalize_selector(selector) -> Dictionary:
	var out := {}
	if not (selector is Dictionary):
		return out
	for key in WEIGHTS.keys():
		if (selector as Dictionary).has(key):
			var value := str((selector as Dictionary)[key])
			if value != "":
				out[str(key)] = value
	return out

static func selector_key(selector) -> String:
	# Canonical string: sorted field=value pairs. Used for duplicate detection
	# and the deterministic runtime tiebreak (specs/09 §1.3).
	var norm := normalize_selector(selector)
	var keys: Array = norm.keys()
	keys.sort()
	var parts: Array = []
	for key in keys:
		parts.append("%s=%s" % [str(key), str(norm[key])])
	return "&".join(parts)

static func selector_score(selector) -> int:
	var norm := normalize_selector(selector)
	var total := 0
	for key in norm.keys():
		total += int(WEIGHTS.get(key, 0))
	return total

static func selector_field_count(selector) -> int:
	return normalize_selector(selector).size()

static func selector_matches(selector, context) -> bool:
	var norm := normalize_selector(selector)
	if norm.is_empty():
		return false
	if not (context is Dictionary):
		return false
	for key in norm.keys():
		if str((context as Dictionary).get(key, "")) != str(norm[key]):
			return false
	return true

# ---------------------------------------------------------------- resolution

static func resolve(doc: Dictionary, context: Dictionary) -> Dictionary:
	# Result: {status, look_id?, binding_id?, bypass_id?, selector?, chain[]}
	# status ∈ UNASSIGNED | ASSIGNED | BYPASSED | AMBIGUOUS
	var chain: Array = []

	# 1) Bypass first — a matching enabled bypass wins over every binding.
	var matched_bypasses: Array = []
	for raw in doc.get("bypasses", []):
		if not (raw is Dictionary):
			continue
		var bypass: Dictionary = raw
		if not _truthy(bypass.get("enabled", true)):
			continue
		if selector_matches(bypass.get("selector", {}), context):
			matched_bypasses.append(bypass)
	if not matched_bypasses.is_empty():
		matched_bypasses.sort_custom(func(a, b):
			var ka := selector_key(a.get("selector", {}))
			var kb := selector_key(b.get("selector", {}))
			if ka != kb:
				return ka < kb
			return str(a.get("bypass_id", "")) < str(b.get("bypass_id", ""))
		)
		var winner: Dictionary = matched_bypasses[0]
		return {
			"status": "BYPASSED",
			"bypass_id": str(winner.get("bypass_id", "")),
			"selector": normalize_selector(winner.get("selector", {})),
			"chain": chain,
		}

	# 2) Enabled bindings that match.
	var candidates: Array = []
	for raw in doc.get("bindings", []):
		if not (raw is Dictionary):
			continue
		var binding: Dictionary = raw
		if not _truthy(binding.get("enabled", true)):
			continue
		var selector = binding.get("selector", {})
		if not selector_matches(selector, context):
			continue
		candidates.append({
			"binding_id": str(binding.get("binding_id", "")),
			"look_id": str(binding.get("look_id", "")),
			"selector_key": selector_key(selector),
			"selector": normalize_selector(selector),
			"score": selector_score(selector),
			"count": selector_field_count(selector),
		})
	if candidates.is_empty():
		return {"status": "UNASSIGNED", "chain": chain}

	# Primary: highest specificity score. Secondary: most constrained fields.
	# Tertiary (runtime tiebreak, specs/09 §1.3): canonical selector string, then
	# binding_id lexical order — never hash iteration order.
	candidates.sort_custom(func(a, b):
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		if int(a["count"]) != int(b["count"]):
			return int(a["count"]) > int(b["count"])
		if str(a["selector_key"]) != str(b["selector_key"]):
			return str(a["selector_key"]) < str(b["selector_key"])
		return str(a["binding_id"]) < str(b["binding_id"])
	)

	var top: Dictionary = candidates[0]
	chain = []
	for index in range(candidates.size()):
		var entry: Dictionary = candidates[index].duplicate()
		entry["winner"] = index == 0
		chain.append(entry)

	var tied: Array = []
	for candidate in candidates:
		if int(candidate["score"]) == int(top["score"]) and int(candidate["count"]) == int(top["count"]):
			tied.append(candidate)
	var ambiguous := false
	for candidate in tied:
		if str(candidate["look_id"]) != str(top["look_id"]):
			ambiguous = true
			break

	return {
		"status": "AMBIGUOUS" if ambiguous else "ASSIGNED",
		"look_id": str(top["look_id"]),
		"binding_id": str(top["binding_id"]),
		"selector": top["selector"],
		"ambiguous_ids": tied.map(func(entry): return str(entry["binding_id"])) if ambiguous else [],
		"chain": chain,
	}

# ---------------------------------------------------------------- validation

static func compatible_selectors(a, b) -> bool:
	# True when some context can match both selectors: shared fields agree.
	var na := normalize_selector(a)
	var nb := normalize_selector(b)
	for key in na.keys():
		if nb.has(key) and str(na[key]) != str(nb[key]):
			return false
	return true

static func _truthy(value) -> bool:
	# R3 §10/§20: hostile container values must not hit the bool() constructor;
	# strings follow Godot's classic coercion (empty / "0" = false, else true).
	if value is bool:
		return value
	if value is float or value is int:
		return float(value) != 0.0
	if value is String:
		var s := (value as String).strip_edges()
		if s == "":
			return false
		if s.is_valid_float():
			return s.to_float() != 0.0
		return true
	return false

static func validate_assignments(doc: Dictionary) -> Dictionary:
	var errors: Array = []
	if str(doc.get("schema", "")) != ASSIGNMENTS_SCHEMA:
		errors.append("schema: expected %s" % ASSIGNMENTS_SCHEMA)
	var seen_binding_ids: Dictionary = {}
	var seen_binding_selectors: Dictionary = {}
	# R3 §10/§20: a hostile bindings value must fail SAFELY (clean error) instead
	# of producing a typed-assignment script error.
	var bindings_value = doc.get("bindings", [])
	if not (bindings_value is Array):
		errors.append("bindings: expected an array")
		return {"ok": false, "errors": errors}
	var bindings: Array = bindings_value
	for raw in bindings:
		if not (raw is Dictionary):
			errors.append("bindings: entry is not an object")
			continue
		var binding: Dictionary = raw
		var binding_id := str(binding.get("binding_id", ""))
		if binding_id.length() < 8:
			errors.append("binding_id too short: %s" % binding_id)
		if seen_binding_ids.has(binding_id):
			errors.append("binding_id duplicate: %s" % binding_id)
		seen_binding_ids[binding_id] = true
		var key := selector_key(binding.get("selector", {}))
		if key == "":
			errors.append("binding %s: empty selector" % binding_id)
		elif seen_binding_selectors.has(key):
			errors.append("duplicate selector: %s (%s and %s)" % [key, seen_binding_selectors[key], binding_id])
		seen_binding_selectors[key] = binding_id
		if str(binding.get("look_id", "")) == "":
			errors.append("binding %s: look_id must not be empty" % binding_id)
	# Ambiguity: compatible selectors with equal score + count that resolve to
	# different Looks are invalid Production data (specs/09 §1.3).
	for i in range(bindings.size()):
		if not (bindings[i] is Dictionary):
			continue
		for j in range(i + 1, bindings.size()):
			if not (bindings[j] is Dictionary):
				continue
			var a: Dictionary = bindings[i]
			var b: Dictionary = bindings[j]
			if not compatible_selectors(a.get("selector", {}), b.get("selector", {})):
				continue
			if selector_score(a.get("selector", {})) != selector_score(b.get("selector", {})):
				continue
			if selector_field_count(a.get("selector", {})) != selector_field_count(b.get("selector", {})):
				continue
			if str(a.get("look_id", "")) != str(b.get("look_id", "")):
				errors.append("ambiguous winner: %s vs %s (different Looks)" % [str(a.get("binding_id", "")), str(b.get("binding_id", ""))])
	var seen_bypass_ids: Dictionary = {}
	var seen_bypass_selectors: Dictionary = {}
	for raw in doc.get("bypasses", []):
		if not (raw is Dictionary):
			errors.append("bypasses: entry is not an object")
			continue
		var bypass: Dictionary = raw
		var bypass_id := str(bypass.get("bypass_id", ""))
		if bypass_id.length() < 8:
			errors.append("bypass_id too short: %s" % bypass_id)
		if seen_bypass_ids.has(bypass_id):
			errors.append("bypass_id duplicate: %s" % bypass_id)
		seen_bypass_ids[bypass_id] = true
		var key := selector_key(bypass.get("selector", {}))
		if key == "":
			errors.append("bypass %s: empty selector" % bypass_id)
		elif seen_bypass_selectors.has(key):
			errors.append("duplicate bypass selector: %s" % key)
		seen_bypass_selectors[key] = bypass_id
	return {"ok": errors.is_empty(), "errors": errors}

# ---------------------------------------------------------------- editing helpers

static func new_assignments() -> Dictionary:
	return {"schema": ASSIGNMENTS_SCHEMA, "bindings": [], "bypasses": []}

static func upsert_binding(doc: Dictionary, selector: Dictionary, look_id: String, note := "") -> String:
	# Updating a selector replaces the existing binding rather than appending a
	# duplicate (specs/09 §2). RS-01: retargeting to a DIFFERENT look is an
	# explicit new-authority intent, so a disabled binding is re-enabled;
	# re-saving the same look preserves the enabled flag.
	var key := selector_key(selector)
	for raw in doc.get("bindings", []):
		if raw is Dictionary and selector_key((raw as Dictionary).get("selector", {})) == key:
			var existing: Dictionary = raw
			if str(existing.get("look_id", "")) != look_id:
				existing["look_id"] = look_id
				existing["enabled"] = true
			if note != "":
				existing["note"] = note
			return str(existing.get("binding_id", ""))
	var binding := {
		"binding_id": next_binding_id("binding"),
		"selector": normalize_selector(selector),
		"look_id": look_id,
		"enabled": true,
	}
	if note != "":
		binding["note"] = note
	doc["bindings"].append(binding)
	return str(binding["binding_id"])

static func add_bypass(doc: Dictionary, selector: Dictionary, note := "") -> String:
	var key := selector_key(selector)
	for raw in doc.get("bypasses", []):
		if raw is Dictionary and selector_key((raw as Dictionary).get("selector", {})) == key:
			return str((raw as Dictionary).get("bypass_id", ""))
	var bypass := {
		"bypass_id": next_binding_id("bypass"),
		"selector": normalize_selector(selector),
		"enabled": true,
	}
	if note != "":
		bypass["note"] = note
	doc["bypasses"].append(bypass)
	return str(bypass["bypass_id"])

static func remove_bypass(doc: Dictionary, selector: Dictionary) -> bool:
	var key := selector_key(selector)
	var before: int = doc.get("bypasses", []).size()
	doc["bypasses"] = (doc.get("bypasses", []) as Array).filter(func(raw):
		return not (raw is Dictionary) or selector_key((raw as Dictionary).get("selector", {})) != key
	)
	return doc["bypasses"].size() != before

static func set_binding_enabled(doc: Dictionary, binding_id: String, enabled: bool) -> bool:
	for raw in doc.get("bindings", []):
		if raw is Dictionary and str((raw as Dictionary).get("binding_id", "")) == binding_id:
			(raw as Dictionary)["enabled"] = enabled
			return true
	return false

static func next_binding_id(prefix: String) -> String:
	_serial += 1
	return "%s-%04d-%s" % [prefix, _serial, _hex(4)]

static func _hex(length: int) -> String:
	var out := ""
	for i in range(length):
		out += "0123456789abcdef"[randi() % 16]
	return out
