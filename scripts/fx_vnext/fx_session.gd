class_name FxSession
extends RefCounted
# NRCU FX Lab vNext — editor session state machine (specs/06, specs/09, specs/15 §8–§11).
#
# Owns the authoring loop for one target at a time: open (Draft -> Production ->
# neutral), edit, auto-stash, Apply/Update with the novice scope builder, shared
# protection (Edit Shared Look / Make Unique), Styling ON/OFF and the Why?
# explanation. Pure logic: no UI, no rendering. The shell drives this module and
# forwards the working Look to the layer renderer.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxCompositionScript := preload("res://scripts/fx_vnext/fx_composition.gd")
const FxRecipesScript := preload("res://scripts/fx_vnext/fx_recipes.gd")

const FIGHTER_ROLES := ["primary", "echo", "name"]
const ASSIGNMENT_SCOPE_MODES := [
	"CURRENT_OCCURRENCE",
	"FIGHTER_ROLE_SIDE",
	"FIGHTER_ROLE",
	"ROLE_SIDE",
	"ROLE",
	"STATIC_ELEMENT",
	"ADVANCED",
]

var production
var drafts

# --- current target
var current_key: String = ""
var context: Dictionary = {}
var signature: String = ""
var role: String = ""

# --- working state
var look: Dictionary = {}
var composition: Dictionary = {}
var base: Dictionary = {} # {kind: unassigned|production|draft|composition, look_id, revision, shared_count}
var mode: String = "NONE" # NONE | EDIT_UNASSIGNED | EDIT_PRODUCTION_UNIQUE | SHARED_PROTECTED | EDIT_SHARED_DRAFT
var dirty: bool = false
var stash_override: Callable = Callable()
var last_errors: Array = []
var last_warnings: Array = []
var resolution: Dictionary = {}
var styling_enabled: bool = true
var assignment_scope_mode: String = "CURRENT_OCCURRENCE"
var assignment_selector_override: Dictionary = {}
var _undo_stack: Array = []
var _redo_stack: Array = []
var _stacks_by_sig: Dictionary = {}

func _init(production_ref, drafts_ref) -> void:
	production = production_ref
	drafts = drafts_ref

# ================================================================ undo / redo

func snapshot() -> void:
	# Called before a structural/value edit; keeps the last 60 states. Composition
	# is explicit authority, so a history entry must capture it alongside the
	# editor projection instead of trying to rebuild it from one recipe id.
	_undo_stack.append({"look": look.duplicate(true), "composition": composition.duplicate(true)})
	if _undo_stack.size() > 60:
		_undo_stack.pop_front()
	_redo_stack.clear()

func _restore_history_state(state) -> void:
	if state is Dictionary and (state as Dictionary).has("look"):
		look = (state as Dictionary).get("look", {}).duplicate(true)
		composition = (state as Dictionary).get("composition", {}).duplicate(true)
	else:
		# Read old in-memory histories created before composition became explicit.
		look = (state as Dictionary).duplicate(true) if state is Dictionary else {}
	if current_key == "composition" and not composition.is_empty():
		composition = FxCompositionScript.materialize(composition)
		look = _composition_editor(composition)

func undo() -> bool:
	if not is_editable():
		last_errors = ["shared production Look is protected — choose Edit Shared Look or Make Unique first"]
		return false
	if _undo_stack.is_empty():
		return false
	_redo_stack.append({"look": look.duplicate(true), "composition": composition.duplicate(true)})
	_restore_history_state(_undo_stack.pop_back())
	dirty = true
	return true

func redo() -> bool:
	if not is_editable():
		last_errors = ["shared production Look is protected — choose Edit Shared Look or Make Unique first"]
		return false
	if _redo_stack.is_empty():
		return false
	_undo_stack.append({"look": look.duplicate(true), "composition": composition.duplicate(true)})
	_restore_history_state(_redo_stack.pop_back())
	dirty = true
	return true

# ================================================================ draft revert

func revert_draft() -> Dictionary:
	if current_key == "composition":
		if str(signature) != "":
			drafts.clear_target(signature)
		var reopened := _open_composition_target()
		if bool(reopened.get("ok", false)):
			dirty = false
		return reopened
	# G — Revert Draft returns to the assigned clean Look (or neutral).
	# DR-05: the shared draft is cleared together with the target draft, so
	# it can never silently reopen. DR-06: base/mode/revision are reconciled
	# from current authority together with the visible look.
	if str(signature) != "":
		drafts.clear_target(signature)
	var look_id := effective_look_id()
	if look_id != "":
		for entry in drafts.list_shared():
			if str((entry as Dictionary).get("look_id", "")) == look_id:
				drafts.clear_shared(look_id, int((entry as Dictionary).get("base_revision", 0)))
	if look_id != "":
		var loaded: Dictionary = production.load_look(look_id)
		if bool(loaded.get("ok", false)):
			var usage: Dictionary = production.usage(look_id)
			look = loaded["doc"]
			base = {
				"kind": "production",
				"look_id": look_id,
				"revision": int(look.get("revision", 1)),
				"shared_count": int(usage.get("count", 0)),
			}
			mode = "SHARED_PROTECTED" if int(usage.get("count", 0)) > 1 else "EDIT_PRODUCTION_UNIQUE"
			dirty = false
			_undo_stack.clear()
			_redo_stack.clear()
			_refresh_resolution()
			return {"ok": true, "errors": [], "reverted_to": look_id}
	look = FxLookScript.new_look("", "")
	look["name"] = _breadcrumb_name()
	base = {"kind": "unassigned", "look_id": "", "revision": 0, "shared_count": 0}
	mode = "EDIT_UNASSIGNED"
	dirty = false
	_undo_stack.clear()
	_redo_stack.clear()
	return {"ok": true, "errors": [], "reverted_to": ""}

# ================================================================ library / assignment ops

func unassign_target() -> Dictionary:
	if current_key == "composition":
		return {"ok": false, "errors": ["composition authority has no assignment"]}
	# I — Unassign removes the binding for the user-selected assignment scope;
	# the Look stays in the Library untouched.
	if mode == "NONE":
		return {"ok": false, "errors": ["no target open"]}
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return {"ok": false, "errors": ["assignments invalid; fix Production first"]}
	var asg_doc: Dictionary = assignments["doc"]
	var selector := assignment_selector()
	if selector.is_empty():
		return {"ok": false, "errors": ["assignment scope has no usable selector fields"]}
	var key := FxResolverScript.selector_key(selector)
	asg_doc["bindings"] = (asg_doc.get("bindings", []) as Array).filter(func(raw):
		return not (raw is Dictionary) or FxResolverScript.selector_key((raw as Dictionary).get("selector", {})) != key
	)
	var result: Dictionary = production.apply({"assignments": asg_doc})
	if not bool(result.get("ok", false)):
		return result
	_refresh_resolution()
	# RS-05: report what is actually effective now — a broader fallback may
	# still style this target, so never claim bare "unassigned".
	var status := str(resolution.get("status", "UNASSIGNED"))
	if status in ["ASSIGNED", "AMBIGUOUS"]:
		return {"ok": true, "errors": [], "fallback_look_id": str(resolution.get("look_id", "")), "message": "exact binding removed; fallback %s now effective" % str(resolution.get("look_id", ""))}
	return {"ok": true, "errors": [], "fallback_look_id": "", "message": "unassigned; neutral design"}

func disable_binding(binding_id: String) -> Dictionary:
	# I — Advanced: disable a specific binding so lower-priority rules win.
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return {"ok": false, "errors": ["assignments invalid; fix Production first"]}
	var asg_doc: Dictionary = assignments["doc"]
	if not FxResolverScript.set_binding_enabled(asg_doc, binding_id, false):
		return {"ok": false, "errors": ["binding not found: " + binding_id]}
	var result: Dictionary = production.apply({"assignments": asg_doc})
	if not bool(result.get("ok", false)):
		return result
	_refresh_resolution()
	return {"ok": true, "errors": []}

func enable_binding(binding_id: String) -> Dictionary:
	# RS-02: every Disable has a reachable Enable recovery on the same path.
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return {"ok": false, "errors": ["assignments invalid; fix Production first"]}
	var asg_doc: Dictionary = assignments["doc"]
	if not FxResolverScript.set_binding_enabled(asg_doc, binding_id, true):
		return {"ok": false, "errors": ["binding not found: " + binding_id]}
	var result: Dictionary = production.apply({"assignments": asg_doc})
	if not bool(result.get("ok", false)):
		return result
	_refresh_resolution()
	return {"ok": true, "errors": []}

func look_library() -> Array:
	var out: Array = []
	for look_id in production.list_look_ids():
		var loaded: Dictionary = production.load_look(look_id)
		var usage: Dictionary = production.usage(look_id)
		out.append({
			"look_id": str(look_id),
			"status": str((loaded.get("doc", {}) as Dictionary).get("status", "?")),
			"revision": int((loaded.get("doc", {}) as Dictionary).get("revision", 0)),
			"usage": int(usage.get("count", 0)),
			"valid": bool(loaded.get("ok", false)),
		})
	return out

func delete_look(look_id: String) -> Dictionary:
	# I — Delete Look is blocked while assignments still reference it.
	# RS-06: disabled bindings count too — deleting under them would leave a
	# dangling reference that breaks on re-enable.
	var usage: Dictionary = production.usage(look_id)
	var total := int(usage.get("total_count", usage.get("count", 0)))
	if total > 0:
		var disabled := total - int(usage.get("count", 0))
		var extra := " (%d disabled reference(s))" % disabled if disabled > 0 else ""
		return {"ok": false, "errors": ["Look is used by %d assignment(s)%s — unassign or replace first" % [total, extra]], "usage": usage}
	var path: String = production.look_path(look_id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["look not found: " + look_id]}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return {"ok": true, "errors": []}

# ================================================================ opening

func open_target(key: String, ctx: Dictionary, signature_: String, role_: String) -> Dictionary:
	var outgoing_sig := str(signature)
	if outgoing_sig != "":
		# R3 §9 fix: per-target undo/redo history — stash the outgoing target's
		# stacks so they can never bleed onto the next target, and restore the
		# incoming target's own history below.
		_stacks_by_sig[outgoing_sig] = {"undo": _undo_stack.duplicate(), "redo": _redo_stack.duplicate()}
	current_key = key
	context = ctx
	signature = signature_
	role = role_
	var inbound: Dictionary = _stacks_by_sig.get(signature_, {})
	_undo_stack = (inbound.get("undo", []) as Array).duplicate()
	_redo_stack = (inbound.get("redo", []) as Array).duplicate()
	look = {}
	composition = {}
	base = {}
	mode = "NONE"
	dirty = false
	last_errors = []
	last_warnings = []
	assignment_scope_mode = "CURRENT_OCCURRENCE"
	assignment_selector_override = {}

	if key == "composition":
		return _open_composition_target()

	var assignments: Dictionary = production.load_assignments()
	resolution = FxResolverScript.resolve(assignments.get("doc", {}), context) if bool(assignments.get("ok", false)) else {"status": "BROKEN", "chain": []}
	styling_enabled = str(resolution.get("status", "")) != "BYPASSED"

	# 1) exact target Draft exists → open Draft (specs/06 §2), subject to
	# authority reconciliation (DR-01/03/04). A structurally invalid draft
	# never reaches typed shell access; a clean draft never shadows newer
	# Production; a draft never bypasses shared-Look protection. The draft
	# file itself is always preserved — reconciliation only changes priority.
	var draft_loaded: Dictionary = drafts.load_target(signature_)
	if bool(draft_loaded.get("ok", false)):
		var record: Dictionary = draft_loaded["record"]
		if not bool(draft_loaded.get("struct_ok", false)):
			last_errors.append("target draft structurally invalid; kept on disk, opening authority instead: " + str(draft_loaded.get("struct_errors", [])))
		else:
			var open_prod_id := ""
			var open_prod_rev := 0
			if str(resolution.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
				open_prod_id = str(resolution.get("look_id", ""))
				var prod_loaded: Dictionary = production.load_look(open_prod_id) if open_prod_id != "" else {"ok": false}
				if bool(prod_loaded.get("ok", false)):
					open_prod_rev = int((prod_loaded["doc"] as Dictionary).get("revision", 0))
			var draft_dirty := bool(record.get("dirty", true))
			if not draft_dirty and open_prod_rev > int(record.get("base_revision", 0)):
				last_errors.append("clean parked draft is older than Production rev%d; opening current authority" % open_prod_rev)
			else:
				look = record["look"]
				base = {
					"kind": "draft",
					"look_id": str(look.get("look_id", "")),
					"revision": int(record.get("base_revision", 0)),
					"shared_count": 0,
				}
				dirty = draft_dirty
				mode = "EDIT_UNASSIGNED"
				if str(resolution.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
					var prod_id := str(resolution.get("look_id", ""))
					if prod_id != "" and prod_id == str(look.get("look_id", "")):
						base["kind"] = "production"
						base["look_id"] = prod_id
						# R3 §9: record shared usage; the APPLY guard enforces protection
						# for draft-branch sessions (no fake shared-draft mode).
						var usage: Dictionary = production.usage(prod_id)
						base["shared_count"] = int(usage.get("count", 0))
						# DR-04: a retained draft never downgrades shared protection.
						mode = "SHARED_PROTECTED" if int(usage.get("count", 0)) > 1 else "EDIT_PRODUCTION_UNIQUE"
				return {"ok": true, "opened": "draft", "errors": []}

	# 2) else resolve Production Assignment; 3) load Production Look.
	if str(resolution.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"]:
		var look_id := str(resolution.get("look_id", ""))
		var loaded: Dictionary = production.load_look(look_id)
		if bool(loaded.get("ok", false)):
			var usage: Dictionary = production.usage(look_id)
			look = loaded["doc"]
			base = {
				"kind": "production",
				"look_id": look_id,
				"revision": int(look.get("revision", 1)),
				"shared_count": int(usage.get("count", 0)),
			}
			mode = "SHARED_PROTECTED" if int(usage.get("count", 0)) > 1 else "EDIT_PRODUCTION_UNIQUE"
			var shared_draft: Dictionary = drafts.load_shared(look_id, int(base["revision"]))
			if bool(shared_draft.get("ok", false)):
				look = shared_draft["record"]["look"]
				mode = "EDIT_SHARED_DRAFT"
				dirty = bool(shared_draft["record"].get("dirty", true))
			return {"ok": true, "opened": "production", "errors": []}
		last_errors.append("assigned look is missing or broken: " + look_id)

	# 4) otherwise create a neutral Source-only working design.
	look = FxLookScript.new_look("", "")
	look["name"] = _breadcrumb_name()
	base = {"kind": "unassigned", "look_id": "", "revision": 0, "shared_count": 0}
	mode = "EDIT_UNASSIGNED"
	return {"ok": true, "opened": "neutral", "errors": last_errors.duplicate()}

func _composition_recipe_id(doc: Dictionary) -> String:
	var metadata: Dictionary = doc.get("metadata", {}) if doc.get("metadata", {}) is Dictionary else {}
	var recipe_id := str(metadata.get("recipe_id", ""))
	if FxRecipesScript.is_composition_recipe(recipe_id):
		return recipe_id
	var composition_id := str(doc.get("composition_id", ""))
	for candidate in FxRecipesScript.COMPOSITION_RECIPE_IDS:
		if composition_id.begins_with("COMP_" + str(candidate) + "_"):
			return str(candidate)
	return ""

func _composition_editor(doc: Dictionary) -> Dictionary:
	var composition_doc: Dictionary = FxCompositionScript.materialize(doc)
	var editor := FxLookScript.new_look(str(composition_doc.get("composition_id", "COMP_ACTIVE")), str(composition_doc.get("name", "Scene Composition")))
	var metadata: Dictionary = composition_doc.get("metadata", {}) if composition_doc.get("metadata", {}) is Dictionary else {}
	metadata = metadata.duplicate(true)
	metadata["composition_authority"] = true
	# recipe_instances is the authoritative composition provenance. The legacy
	# recipe_id projection may remain for older readers, but is never used to
	# reconstruct the pass list.
	editor["metadata"] = metadata
	var layers := FxCompositionScript.to_layers(composition_doc)
	if not layers.is_empty():
		editor["layers"] = layers
	return FxLookScript.materialize(editor)

func _open_composition_target() -> Dictionary:
	# Composition is a separate authority boundary. Do not load assignments or
	# ask the resolver which fighter Look happens to cover this synthetic target.
	resolution = {"status": "COMPOSITION", "authority": "composition", "chain": []}
	styling_enabled = true
	var draft_loaded: Dictionary = drafts.load_composition(signature)
	if bool(draft_loaded.get("ok", false)):
		if not bool(draft_loaded.get("struct_ok", false)):
			last_errors.append("composition draft structurally invalid; kept on disk, opening authority instead: " + str(draft_loaded.get("struct_errors", [])))
		else:
			var record: Dictionary = draft_loaded["record"]
			var production_loaded: Dictionary = production.load_composition()
			var production_revision := int((production_loaded.get("doc", {}) as Dictionary).get("revision", 0)) if bool(production_loaded.get("ok", false)) else 0
			var draft_revision := int(record.get("base_revision", 0))
			var draft_dirty := bool(record.get("dirty", true))
			# Explicit dirty work remains the author's authority even when
			# Production advanced while the editor was closed. Clean snapshots are
			# only eligible while they are not stale.
			if draft_dirty or production_revision <= draft_revision:
				composition = FxCompositionScript.materialize(record["composition"])
				look = _composition_editor(composition)
				base = {"kind": "composition_draft", "authority": "draft", "look_id": "", "composition_id": str(composition.get("composition_id", "")), "revision": draft_revision, "shared_count": 0}
				mode = "EDIT_COMPOSITION"
				dirty = draft_dirty
				return {"ok": true, "opened": "draft", "errors": []}
			last_errors.append("clean composition draft is older than Production rev%d; opening current authority" % production_revision)

	var loaded: Dictionary = production.load_composition()
	if bool(loaded.get("ok", false)) and not (loaded.get("doc", {}) as Dictionary).is_empty():
		composition = FxCompositionScript.materialize(loaded["doc"])
		look = _composition_editor(composition)
		base = {"kind": "composition", "authority": "production", "look_id": "", "composition_id": str(composition.get("composition_id", "")), "revision": int(composition.get("revision", 1)), "shared_count": 0}
		mode = "EDIT_COMPOSITION"
		dirty = false
		return {"ok": true, "opened": "production", "errors": last_errors.duplicate()}

	# A blank composition is still composition-owned state, never a fighter
	# neutral Look. It becomes persistable once a composition recipe is chosen.
	composition = FxCompositionScript.new_document("COMP_ACTIVE", "Scene Composition")
	composition["metadata"] = {"composition_authority": true}
	look = _composition_editor(composition)
	base = {"kind": "composition", "authority": "neutral", "look_id": "", "composition_id": "COMP_ACTIVE", "revision": 0, "shared_count": 0}
	mode = "EDIT_COMPOSITION"
	dirty = false
	return {"ok": true, "opened": "neutral", "errors": last_errors.duplicate()}

func _breadcrumb_name() -> String:
	var selector := assignment_selector()
	var parts: Array = []
	if selector.has("fighter_id"):
		parts.append(str(selector["fighter_id"]).replace("_", " ").capitalize())
	if selector.has("element_role"):
		parts.append(str(selector["element_role"]).capitalize())
	elif selector.has("element_id"):
		parts.append(str(selector["element_id"]).replace("_", " ").capitalize())
	if selector.has("visual_side"):
		parts.append(str(selector["visual_side"]).capitalize())
	return " ".join(parts) if not parts.is_empty() else "Untitled Design"

# ================================================================ scope

func set_assignment_scope(mode_: String, custom_selector: Dictionary = {}) -> Dictionary:
	if current_key == "composition":
		return {"ok": false, "errors": ["composition authority has no assignment scope"]}
	var normalized_mode := str(mode_).to_upper()
	if not ASSIGNMENT_SCOPE_MODES.has(normalized_mode):
		return {"ok": false, "errors": ["unknown assignment scope: " + normalized_mode]}
	assignment_scope_mode = normalized_mode
	assignment_selector_override = FxResolverScript.normalize_selector(custom_selector) if normalized_mode == "ADVANCED" else {}
	return {"ok": true, "selector": assignment_selector(), "scope": assignment_scope_text()}

func _context_selector() -> Dictionary:
	var selector: Dictionary = {}
	for field in FxResolverScript.SELECTOR_FIELDS:
		var value := str(context.get(str(field), ""))
		if value != "":
			selector[str(field)] = value
	return FxResolverScript.normalize_selector(selector)

func assignment_selector() -> Dictionary:
	if current_key == "composition":
		return {}
	var exact := _context_selector()
	match assignment_scope_mode:
		"CURRENT_OCCURRENCE": return exact
		"FIGHTER_ROLE_SIDE": return FxResolverScript.normalize_selector({"fighter_id": context.get("fighter_id", ""), "element_role": context.get("element_role", role), "visual_side": context.get("visual_side", "")})
		"FIGHTER_ROLE": return FxResolverScript.normalize_selector({"fighter_id": context.get("fighter_id", ""), "element_role": context.get("element_role", role)})
		"ROLE_SIDE": return FxResolverScript.normalize_selector({"element_role": context.get("element_role", role), "visual_side": context.get("visual_side", "")})
		"ROLE": return FxResolverScript.normalize_selector({"element_role": context.get("element_role", role)})
		"STATIC_ELEMENT": return FxResolverScript.normalize_selector({"element_id": context.get("element_id", "")})
		"ADVANCED": return FxResolverScript.normalize_selector(assignment_selector_override)
	return exact

func assignment_scope_text() -> String:
	if current_key == "composition":
		return "COMPOSITION / SCENE FX"
	var selector := assignment_selector()
	var labels := {
		"CURRENT_OCCURRENCE": "CURRENT OCCURRENCE / EXACT TARGET",
		"FIGHTER_ROLE_SIDE": "FIGHTER + ROLE + VISUAL SIDE",
		"FIGHTER_ROLE": "FIGHTER + ROLE",
		"ROLE_SIDE": "ROLE + VISUAL SIDE",
		"ROLE": "ROLE",
		"STATIC_ELEMENT": "STATIC ELEMENT",
		"ADVANCED": "ADVANCED SELECTOR",
	}
	var label := str(labels.get(assignment_scope_mode, assignment_scope_mode.replace("_", " ")))
	var key := FxResolverScript.selector_key(selector)
	return "%s · %s" % [label, key if key != "" else "no matching fields"]

func novice_selector() -> Dictionary:
	# specs/15 §8: exact novice scope rules.
	var selector: Dictionary = {}
	if role in FIGHTER_ROLES:
		selector["fighter_id"] = str(context.get("fighter_id", ""))
		selector["element_role"] = str(context.get("element_role", role))
		selector["visual_side"] = str(context.get("visual_side", ""))
		return FxResolverScript.normalize_selector(selector)
	if role == "stage":
		selector["element_id"] = str(context.get("element_id", "stage"))
		var stage_id := str(context.get("stage_id", ""))
		if stage_id != "":
			selector["stage_id"] = stage_id
		return FxResolverScript.normalize_selector(selector)
	selector["element_id"] = str(context.get("element_id", ""))
	return FxResolverScript.normalize_selector(selector)

func proposed_look_id() -> String:
	var selector := assignment_selector()
	var parts: Array = []
	if selector.has("fighter_id"):
		parts.append(str(selector["fighter_id"]))
	elif selector.has("element_id"):
		parts.append(str(selector["element_id"]))
	if selector.has("element_role"):
		parts.append(str(selector["element_role"]))
	if selector.has("stage_id") and not selector.has("element_role"):
		parts.append(str(selector["stage_id"]))
	if selector.has("visual_side"):
		parts.append(str(selector["visual_side"]))
	var raw := "_".join(parts).to_upper()
	var clean := ""
	for i in range(raw.length()):
		var c := raw[i]
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_":
			clean += c
	while clean.begins_with("_"):
		clean = clean.substr(1)
	while clean.ends_with("_"):
		clean = clean.substr(0, clean.length() - 1)
	return clean if clean != "" else "UNTITLED_FX"

func unique_look_id(proposal: String, keep: String) -> String:
	# specs/15 §10: `_2`, `_3`, ... deterministically until unique; an update of
	# the currently assigned Look keeps its id.
	if proposal == "":
		return proposal
	var existing: Array = production.list_look_ids()
	if not existing.has(proposal) or proposal == keep:
		return proposal
	var index := 2
	while existing.has("%s_%d" % [proposal, index]):
		index += 1
	return "%s_%d" % [proposal, index]

# ================================================================ editing

func is_editable() -> bool:
	return mode != "SHARED_PROTECTED"

func edit(mutator: Callable) -> Dictionary:
	if not is_editable():
		last_errors = ["shared production Look opens protected — choose Edit Shared Look or Make Unique first"]
		return {"ok": false, "changed": false, "errors": last_errors.duplicate()}
	# Mutate a private candidate. A false/failed mutator must never leave a
	# partially changed authority document behind or manufacture a dirty edit.
	var candidate: Dictionary = look.duplicate(true)
	var result = mutator.call(candidate)
	if result is bool and not bool(result):
		last_errors = ["mutation rejected"]
		return {"ok": false, "changed": false, "errors": last_errors.duplicate()}
	if result is Dictionary and not bool((result as Dictionary).get("ok", true)):
		return result
	if result is Dictionary and (result as Dictionary).has("changed") and not bool((result as Dictionary).get("changed", true)):
		return {"ok": true, "changed": false, "errors": [], "warnings": []}
	look = FxLookScript.materialize(candidate)
	if current_key == "composition":
		_sync_composition_from_editor()
	var check: Dictionary = FxCompositionScript.validate(composition) if current_key == "composition" else FxLookScript.validate(look)
	last_warnings = check["errors"] if not bool(check["ok"]) else []
	dirty = true
	return {"ok": true, "changed": true, "errors": [], "warnings": last_warnings.duplicate()}

func edit_recipe_macro(recipe_id: String, recipe_instance_id: String, macro_id: String, value) -> Dictionary:
	if not is_editable():
		last_errors = ["shared production Look opens protected — choose Edit Shared Look or Make Unique first"]
		return {"ok": false, "changed": false, "errors": last_errors.duplicate()}
	if str(recipe_instance_id).strip_edges() == "":
		last_errors = ["recipe macro requires an explicit recipe_instance_id"]
		return {"ok": false, "changed": false, "errors": last_errors.duplicate()}
	var authority: Dictionary = composition if current_key == "composition" else look
	# Keep the live authority untouched until both the Macro mutator and the
	# authority validator accept a private candidate. This is the transaction
	# boundary for failed Macro edits.
	var candidate: Dictionary = authority.duplicate(true)
	var result: Dictionary = FxRecipesScript.apply_macro_result(candidate, recipe_id, recipe_instance_id, macro_id, value)
	if not bool(result.get("ok", false)):
		last_errors = result.get("errors", ["recipe macro mutation rejected"])
		return result
	if not bool(result.get("changed", false)):
		return result
	if current_key == "composition":
		var candidate_composition: Dictionary = FxCompositionScript.materialize(candidate)
		var composition_check: Dictionary = FxCompositionScript.validate(candidate_composition)
		if not bool(composition_check.get("ok", false)):
			last_errors = composition_check.get("errors", [])
			return {"ok": false, "changed": false, "errors": last_errors.duplicate()}
		composition = candidate_composition
		look = _composition_editor(composition)
	else:
		look = FxLookScript.materialize(candidate)
	var check: Dictionary = FxCompositionScript.validate(composition) if current_key == "composition" else FxLookScript.validate(look)
	last_warnings = check.get("errors", []) if not bool(check.get("ok", false)) else []
	dirty = true
	return {"ok": true, "changed": true, "errors": [], "warnings": last_warnings.duplicate(), "targets": result.get("targets", [])}

func _sync_composition_from_editor() -> void:
	if current_key != "composition":
		return
	# The Look shown by the inspector is a deterministic projection of the
	# explicit composition document. Copy edits back by pass identity, preserving
	# every membership and every pass that is currently disabled/hidden.
	var doc: Dictionary = FxCompositionScript.materialize(composition)
	doc["name"] = str(look.get("name", doc.get("name", "Scene Composition")))
	var passes: Array = (doc.get("final_passes", []) as Array).duplicate(true)
	for raw_layer in look.get("layers", []):
		if not (raw_layer is Dictionary):
			continue
		var layer: Dictionary = raw_layer
		var layer_id := str(layer.get("layer_id", ""))
		if layer_id == "":
			continue
		for index in range(passes.size()):
			if not (passes[index] is Dictionary):
				continue
			var composition_pass: Dictionary = passes[index]
			if str(composition_pass.get("pass_id", "")) != layer_id:
				continue
			composition_pass["name"] = str(layer.get("name", composition_pass.get("name", "Final Pass")))
			composition_pass["enabled"] = bool(layer.get("enabled", composition_pass.get("enabled", true)))
			composition_pass["operator"] = str((layer.get("fx", {}) as Dictionary).get("operator", composition_pass.get("operator", "NONE")))
			var fx: Dictionary = layer.get("fx", {}) if layer.get("fx", {}) is Dictionary else {}
			composition_pass["fx"] = fx.duplicate(true)
			composition_pass["event_start"] = float(fx.get("operator_event_start", composition_pass.get("event_start", 0.0)))
			composition_pass["duration"] = float(fx.get("operator_duration", composition_pass.get("duration", 0.0)))
			passes[index] = composition_pass
			break
	doc["final_passes"] = passes
	var metadata: Dictionary = composition.get("metadata", {}) if composition.get("metadata", {}) is Dictionary else {}
	metadata = metadata.duplicate(true)
	metadata["composition_authority"] = true
	doc["metadata"] = metadata
	# Document revision and Production base revision are separate authorities.
	# A never-applied draft may be based on production revision 0 while its
	# Composition document remains schema-valid revision 1.
	doc["revision"] = maxi(1, int(composition.get("revision", 1)))
	doc["status"] = "DRAFT"
	composition = FxCompositionScript.materialize(doc)

func _recipe_memberships(doc: Dictionary) -> Array:
	var metadata: Dictionary = doc.get("metadata", {}) if doc.get("metadata", {}) is Dictionary else {}
	var raw: Variant = metadata.get("recipe_instances", [])
	return (raw as Array).duplicate(true) if raw is Array else []

func _next_recipe_instance_id(recipe_id: String) -> String:
	var doc := composition if current_key == "composition" else look
	var memberships := _recipe_memberships(doc)
	var ordinal := 0
	for raw_entry in memberships:
		if raw_entry is Dictionary and str((raw_entry as Dictionary).get("recipe_id", "")) == recipe_id:
			ordinal += 1
	return "%s:%s:%d" % [current_key, recipe_id, ordinal]

func add_recipe_instance(recipe_id: String, target_context: Dictionary = {}, requested_instance_id := "") -> Dictionary:
	# This is the canonical public Recipe mutation seam. Revalidate the live
	# target context before snapshotting or changing either authority document.
	if mode == "NONE":
		return {"ok": false, "errors": ["no target open"]}
	if not is_editable():
		return {"ok": false, "errors": ["shared production Look opens protected — choose Edit Shared Look or Make Unique first"]}
	var live_context: Dictionary = target_context.duplicate(true) if not target_context.is_empty() else context.duplicate(true)
	if str(live_context.get("target_key", "")) != current_key:
		return {"ok": false, "errors": ["recipe target context is stale or does not match the open target"]}
	var compatibility: Dictionary = FxRecipesScript.target_compatibility(recipe_id, live_context)
	if not bool(compatibility.get("ok", false)):
		last_errors = compatibility.get("errors", [])
		return {"ok": false, "errors": last_errors.duplicate(), "compatibility": compatibility}
	var instance_id := str(requested_instance_id).strip_edges() if str(requested_instance_id) != "" else _next_recipe_instance_id(recipe_id)
	if instance_id == "":
		return {"ok": false, "errors": ["recipe instance id must not be empty"]}
	var recipe_result: Dictionary = FxRecipesScript.instantiate(recipe_id, instance_id)
	if not bool(recipe_result.get("ok", false)):
		last_errors = recipe_result.get("errors", [])
		return {"ok": false, "errors": last_errors.duplicate()}
	var recipe_definition: Dictionary = FxRecipesScript.get_recipe(recipe_id)
	var membership: Dictionary = (recipe_result.get("membership", {}) as Dictionary).duplicate(true)
	membership["instance_id"] = instance_id
	membership["recipe_instance_id"] = instance_id
	var target_doc := composition if current_key == "composition" else look
	var prior_memberships := _recipe_memberships(target_doc)
	membership["created_order"] = prior_memberships.size()
	# Every successful authoring mutation has exactly one history entry, and the
	# snapshot is taken only after all fail-closed checks above have passed.
	snapshot()
	if current_key == "composition":
		var composition_result: Dictionary = recipe_result.get("composition", {})
		if not bool(composition_result.get("ok", false)):
			_restore_history_state(_undo_stack.pop_back())
			last_errors = composition_result.get("errors", ["composition Recipe has no composition document"])
			return {"ok": false, "errors": last_errors.duplicate()}
		var doc: Dictionary = FxCompositionScript.materialize(composition)
		var added_doc: Dictionary = FxCompositionScript.materialize(composition_result.get("doc", {}))
		var passes: Array = (doc.get("final_passes", []) as Array).duplicate(true)
		passes.append_array((added_doc.get("final_passes", []) as Array).duplicate(true))
		doc["final_passes"] = passes
		var metadata: Dictionary = doc.get("metadata", {}) if doc.get("metadata", {}) is Dictionary else {}
		metadata = metadata.duplicate(true)
		metadata["composition_authority"] = true
		var all_memberships: Array = _recipe_memberships(doc)
		all_memberships.append(membership.duplicate(true))
		metadata["recipe_instances"] = all_memberships
		# Legacy projections stay readable, while composition logic uses only the
		# membership list and canonical passes above.
		metadata["recipe_id"] = recipe_id
		metadata["recipe_macros"] = recipe_definition.get("macros", []).duplicate(true)
		metadata["recipe_target_compatibility"] = recipe_definition.get("target_compatibility", {}).duplicate(true)
		metadata["source_semantics"] = recipe_definition.get("source_semantics", {}).duplicate(true)
		doc["metadata"] = metadata
		doc["status"] = "DRAFT"
		composition = FxCompositionScript.materialize(doc)
		look = _composition_editor(composition)
		dirty = true
	else:
		var result: Dictionary = edit(func(editor_doc):
			(editor_doc["layers"] as Array).append_array((recipe_result.get("layers", []) as Array).duplicate(true))
			var metadata: Dictionary = editor_doc.get("metadata", {}) if editor_doc.get("metadata", {}) is Dictionary else {}
			metadata = metadata.duplicate(true)
			var all_memberships: Array = _recipe_memberships(editor_doc)
			all_memberships.append(membership.duplicate(true))
			metadata["recipe_instances"] = all_memberships
			# Compatibility projections for existing target-local readers.
			metadata["recipe_id"] = recipe_id
			metadata["recipe_macros"] = recipe_definition.get("macros", []).duplicate(true)
			metadata["recipe_target_compatibility"] = recipe_definition.get("target_compatibility", {}).duplicate(true)
			metadata["source_semantics"] = recipe_definition.get("source_semantics", {}).duplicate(true)
			editor_doc["metadata"] = metadata
		)
		if not bool(result.get("ok", false)):
			_restore_history_state(_undo_stack.pop_back())
			return result
	return {
		"ok": true,
		"errors": [],
		"recipe_id": recipe_id,
		"recipe_instance_id": instance_id,
		"instance_id": instance_id,
		"layer_ids": (membership.get("layer_ids", []) as Array).duplicate(),
		"pass_ids": (membership.get("pass_ids", []) as Array).duplicate(),
		"membership": membership.duplicate(true),
		"compatibility": compatibility,
	}

func stash() -> Dictionary:
	if stash_override.is_valid():
		return stash_override.call()
	# Auto-stash (specs/10 §2) — crash-safe editor work, never Production.
	if base.get("kind", "") == "production" and int(base.get("shared_count", 0)) > 1 and mode == "EDIT_SHARED_DRAFT":
		return drafts.save_shared(str(base["look_id"]), int(base["revision"]), look, dirty)
	if current_key == "composition":
		_sync_composition_from_editor()
		if str(signature) == "":
			return {"ok": false, "errors": ["no target signature"]}
		return drafts.save_composition(signature, composition, int(base.get("revision", 0)), dirty)
	if str(signature) == "":
		return {"ok": false, "errors": ["no target signature"]}
	return drafts.save_target(signature, look, int(base.get("revision", 0)), dirty)

func save_draft() -> Dictionary:
	var result := stash()
	if bool(result.get("ok", false)):
		return {"ok": true, "errors": [], "message": "Draft saved"}
	return result

func prepare_for_remount() -> Dictionary:
	# A remount is an authority transition, never a visual-only reset. Persist the
	# current dirty target before releasing its identity; a failed stash keeps the
	# old authority intact so the user can retry without data loss.
	if mode == "NONE" or str(current_key) == "":
		return {"ok": true, "stashed": false, "errors": []}
	if dirty:
		var result: Dictionary = stash()
		if not bool(result.get("ok", false)):
			return {"ok": false, "stashed": false, "errors": result.get("errors", [])}
	return {"ok": true, "stashed": dirty, "errors": []}

func close_target() -> void:
	current_key = ""
	context = {}
	signature = ""
	role = ""
	look = {}
	composition = {}
	base = {}
	mode = "NONE"
	dirty = false
	last_errors = []
	last_warnings = []
	resolution = {}
	styling_enabled = true
	assignment_scope_mode = "CURRENT_OCCURRENCE"
	assignment_selector_override = {}
	_undo_stack.clear()
	_redo_stack.clear()
	_stacks_by_sig.clear()
	stash_override = Callable()


func _prepare_doc(final_id: String, revision: int) -> Dictionary:
	var doc: Dictionary = look.duplicate(true)
	doc["look_id"] = final_id
	doc["status"] = "PRODUCTION"
	doc["revision"] = revision
	return FxLookScript.materialize(doc)

func apply(look_id_override := "") -> Dictionary:
	if mode == "SHARED_PROTECTED":
		last_errors = ["shared Look is protected — Edit Shared Look or Make Unique before applying"]
		return {"ok": false, "errors": last_errors.duplicate()}
	if mode == "NONE":
		return {"ok": false, "errors": ["no target open"]}
	# R3 §9: shared-Look protection covers EVERY entry into apply. A draft-branch
	# session whose underlying look is shared must go through Edit Shared Look or
	# Make Unique — never silently update the shared look in place.
	if mode != "EDIT_SHARED_DRAFT" and str(base.get("kind", "")) == "production":
		var keep_id := str(base.get("look_id", ""))
		if keep_id != "":
			var usage_now: Dictionary = production.usage(keep_id)
			if int(usage_now.get("count", 0)) > 1:
				last_errors = ["shared Look is protected — Edit Shared Look or Make Unique before applying"]
				return {"ok": false, "errors": last_errors.duplicate()}
	# Composition authority has no fighter assignment selector. Its Production
	# transaction writes the explicit composition document, never a target Look.
	if current_key == "composition":
		# composition is the canonical working document. Never reconstruct it from
		# the legacy last-recipe projection in the editor metadata.
		_sync_composition_from_editor()
		var composition_doc: Dictionary = FxCompositionScript.materialize(composition)
		var composition_metadata: Dictionary = composition_doc.get("metadata", {}) if composition_doc.get("metadata", {}) is Dictionary else {}
		composition_metadata = composition_metadata.duplicate(true)
		composition_metadata["composition_authority"] = true
		composition_doc["metadata"] = composition_metadata
		var existing_composition: Dictionary = production.load_composition()
		var composition_revision := 1
		if bool(existing_composition.get("ok", false)) and not (existing_composition.get("doc", {}) as Dictionary).is_empty():
			composition_revision = int((existing_composition["doc"] as Dictionary).get("revision", 0)) + 1
		composition_doc["status"] = "PRODUCTION"
		composition_doc["revision"] = composition_revision
		var composition_apply: Dictionary = production.apply({"composition": composition_doc})
		if not bool(composition_apply.get("ok", false)):
			last_errors = composition_apply.get("errors", [])
			return composition_apply
		var persisted_composition: Dictionary = production.load_composition()
		if not bool(persisted_composition.get("ok", false)):
			last_errors = persisted_composition.get("errors", ["composition apply could not be re-read"])
			return {"ok": false, "errors": last_errors}
		composition = FxCompositionScript.materialize(persisted_composition["doc"])
		look = _composition_editor(composition)
		base = {"kind": "composition", "authority": "production", "look_id": "", "composition_id": str(composition.get("composition_id", "")), "revision": int(composition.get("revision", composition_revision)), "shared_count": 0}
		last_errors = []
		dirty = false
		mode = "EDIT_COMPOSITION"
		drafts.save_composition(signature, composition, int(composition.get("revision", composition_revision)), false)
		return {"ok": true, "errors": [], "composition_revision": int(composition.get("revision", composition_revision)), "revision": int(composition.get("revision", composition_revision))}
	# R3 §9: if an intentionally disabled binding still covers this scope, say so
	# — applying will create an active binding that takes precedence over it.
	var disabled_notice := _disabled_binding_notice()
	if disabled_notice != "" and not last_warnings.has(disabled_notice):
		last_warnings.append(disabled_notice)
	var selector := assignment_selector()
	if selector.is_empty():
		return {"ok": false, "errors": ["assignment scope has no usable selector fields"]}
	var keep := ""
	var revision := 1
	if str(base.get("kind", "")) == "production":
		keep = str(base.get("look_id", ""))
		revision = int(base.get("revision", 1)) + 1
	var proposal := look_id_override if look_id_override != "" else (keep if keep != "" else proposed_look_id())
	var final_id := unique_look_id(proposal, keep)
	if final_id == "":
		return {"ok": false, "errors": ["cannot derive a Look ID — set one explicitly"]}

	var doc := _prepare_doc(final_id, revision)
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return {"ok": false, "errors": ["assignments invalid; fix Production first"]}
	var asg_doc: Dictionary = assignments["doc"]
	# RS-01: notice when this apply re-enables an exact disabled binding.
	var reenabled := false
	var sel_key := FxResolverScript.selector_key(selector)
	for raw in (asg_doc as Dictionary).get("bindings", []):
		if raw is Dictionary and FxResolverScript.selector_key((raw as Dictionary).get("selector", {})) == sel_key:
			if not bool((raw as Dictionary).get("enabled", true)) and str((raw as Dictionary).get("look_id", "")) != final_id:
				reenabled = true
	FxResolverScript.upsert_binding(asg_doc, selector, final_id, "novice apply")
	var result: Dictionary = production.apply({"look": doc, "assignments": asg_doc})
	if not bool(result.get("ok", false)):
		last_errors = result.get("errors", [])
		return result
	if reenabled and not last_warnings.has("re-enabled a disabled binding for this scope"):
		last_warnings.append("re-enabled a disabled binding for this scope")

	# Success (specs/15 §10): status PRODUCTION, draft stays as clean snapshot.
	if mode == "EDIT_SHARED_DRAFT":
		drafts.clear_shared(str(base.get("look_id", "")), int(base.get("revision", 0)))
	look = doc
	last_errors = []
	dirty = false
	var usage: Dictionary = production.usage(final_id)
	base = {
		"kind": "production",
		"look_id": final_id,
		"revision": revision,
		"shared_count": int(usage.get("count", 0)),
	}
	mode = "SHARED_PROTECTED" if int(usage.get("count", 0)) > 1 else "EDIT_PRODUCTION_UNIQUE"
	_refresh_resolution()
	if str(signature) != "":
		drafts.save_target(signature, look, revision, false)
	return {"ok": true, "errors": [], "look_id": final_id, "revision": revision}

func make_unique() -> Dictionary:
	if current_key == "composition":
		return {"ok": false, "errors": ["composition authority has no shared Look"]}
	if mode != "SHARED_PROTECTED":
		return {"ok": false, "errors": ["Make Unique is only needed for shared Looks"]}
	var original_id := str(base.get("look_id", ""))
	var proposal := unique_look_id(original_id + "_UNIQUE", "")
	var selector := assignment_selector()
	if selector.is_empty():
		return {"ok": false, "errors": ["assignment scope has no usable selector fields"]}
	var doc := _prepare_doc(proposal, 1)
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return {"ok": false, "errors": ["assignments invalid; fix Production first"]}
	var asg_doc: Dictionary = assignments["doc"]
	FxResolverScript.upsert_binding(asg_doc, selector, proposal, "make unique")
	var result: Dictionary = production.apply({"look": doc, "assignments": asg_doc})
	if not bool(result.get("ok", false)):
		last_errors = result.get("errors", [])
		return result
	look = doc
	base = {"kind": "production", "look_id": proposal, "revision": 1, "shared_count": 1}
	mode = "EDIT_PRODUCTION_UNIQUE"
	dirty = false
	last_errors = []
	# R3 §9 fix: a stale parked draft for this target would reopen the OLD shared
	# look on the next visit - drop it now that the target owns its unique copy.
	if str(signature) != "":
		drafts.clear_target(signature)
	_refresh_resolution()
	return {"ok": true, "errors": [], "look_id": proposal}

func _disabled_binding_notice() -> String:
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return ""
	for raw in (assignments["doc"] as Dictionary).get("bindings", []):
		if raw is Dictionary and not bool((raw as Dictionary).get("enabled", true)):
			if FxResolverScript.selector_matches((raw as Dictionary).get("selector", {}), context):
				return "a disabled binding covers this scope; the applied binding takes precedence over it"
	return ""

func edit_shared() -> Dictionary:
	if current_key == "composition":
		return {"ok": false, "errors": ["composition authority has no shared Look"]}
	# Opens (or creates) the shared draft for the current shared Look revision.
	if mode != "SHARED_PROTECTED":
		return {"ok": false, "errors": ["not in shared-protected state"]}
	var look_id := str(base.get("look_id", ""))
	var revision := int(base.get("revision", 1))
	var existing: Dictionary = drafts.load_shared(look_id, revision)
	if not bool(existing.get("ok", false)):
		var saved: Dictionary = drafts.save_shared(look_id, revision, look, false)
		if not bool(saved.get("ok", false)):
			return saved
	mode = "EDIT_SHARED_DRAFT"
	return {"ok": true, "errors": []}

# ================================================================ styling on/off

func set_styling(enabled: bool) -> Dictionary:
	if current_key == "composition":
		return {"ok": false, "errors": ["composition authority has no styling assignment"]}
	if mode == "NONE":
		return {"ok": false, "errors": ["no target open"]}
	var assignments: Dictionary = production.load_assignments()
	if not bool(assignments.get("ok", false)):
		return {"ok": false, "errors": ["assignments invalid; fix Production first"]}
	var asg_doc: Dictionary = assignments["doc"]
	var selector := assignment_selector()
	if selector.is_empty():
		return {"ok": false, "errors": ["assignment scope has no usable selector fields"]}
	if enabled:
		FxResolverScript.remove_bypass(asg_doc, selector)
	else:
		FxResolverScript.add_bypass(asg_doc, selector, "styling off")
	var result: Dictionary = production.apply({"assignments": asg_doc})
	if not bool(result.get("ok", false)):
		return result
	styling_enabled = enabled
	_refresh_resolution()
	# RS-03/04: enabling only removes the exact novice bypass. A broader
	# inherited bypass can still win — report it instead of claiming ON.
	var warnings: Array = []
	if enabled and str(resolution.get("status", "")) == "BYPASSED":
		warnings.append("still styling-OFF: broader bypass %s matches this target" % FxResolverScript.selector_key((resolution.get("selector", {}) as Dictionary)))
	return {"ok": true, "errors": [], "warnings": warnings}

func _refresh_resolution() -> void:
	var assignments: Dictionary = production.load_assignments()
	resolution = FxResolverScript.resolve(assignments.get("doc", {}), context) if bool(assignments.get("ok", false)) else {"status": "BROKEN", "chain": []}
	styling_enabled = str(resolution.get("status", "")) != "BYPASSED"

# ================================================================ status / why

func effective_look_id() -> String:
	return str(resolution.get("look_id", "")) if str(resolution.get("status", "")) in ["ASSIGNED", "AMBIGUOUS"] else ""

func badge_text() -> String:
	if current_key == "composition":
		return "◈ COMPOSITION / SCENE FX" + (" · DRAFT" if dirty else "")
	var effective := str(resolution.get("status", "UNASSIGNED"))
	var suffix := " · DRAFT" if dirty else ""
	# R3 §23 fix: a resolution that merely POINTS at a look whose file is gone
	# must not display as assigned — surface the broken state truthfully.
	for entry in last_errors:
		if str(entry).begins_with("assigned look is missing or broken"):
			return "⚠ BROKEN" + suffix
	match effective:
		"BYPASSED":
			return "⦸ STYLING OFF" + suffix
		"AMBIGUOUS":
			return "⚠ AMBIGUOUS" + suffix
		"ASSIGNED":
			if str(look.get("status", "")) == "MIGRATION_REVIEW_REQUIRED":
				return "⚠ MIGRATION REVIEW" + suffix
			if int(base.get("shared_count", 0)) > 1:
				return "◆ SHARED (%d)" % int(base["shared_count"]) + suffix
			return "● ASSIGNED" + suffix
		"BROKEN":
			return "⚠ BROKEN" + suffix
	if dirty:
		return "◐ DRAFT"
	return "○ UNASSIGNED"

func status_detail() -> String:
	if current_key == "composition":
		return "COMPOSITION / SCENE FX\nComposition revision: %d\nAuthority: %s" % [int(base.get("revision", 0)), str(base.get("authority", "neutral")).to_upper()]
	var lines: Array = []
	var effective := str(resolution.get("status", "UNASSIGNED"))
	if effective == "ASSIGNED" or effective == "AMBIGUOUS":
		lines.append("Effective Style: " + str(resolution.get("look_id", "")))
	else:
		lines.append("Effective Style: —")
	if int(base.get("shared_count", 0)) > 1:
		lines.append("Used by %d assignments" % int(base["shared_count"]))
	if mode == "SHARED_PROTECTED":
		lines.append("Protected: shared Look — Edit Shared Look or Make Unique to change.")
	elif mode == "EDIT_SHARED_DRAFT":
		lines.append("Editing shared draft (applies to every target using this Look).")
	return "\n".join(lines)

func why() -> Array:
	if current_key == "composition":
		return ["COMPOSITION / SCENE FX", "Production revision: %d" % int(base.get("revision", 0)), "Assignment scope does not apply."]
	# specs/06 §10: explain the winning match in human terms.
	var lines: Array = []
	var assignments: Dictionary = production.load_assignments()
	var doc: Dictionary = assignments.get("doc", {}) if bool(assignments.get("ok", false)) else {}
	var status := str(resolution.get("status", "UNASSIGNED"))
	if status == "BYPASSED":
		var sel := str(resolution.get("selector", {}).get("element_id", ""))
		lines.append("Styling OFF — explicit bypass matches this target.")
		var byp_selector: Dictionary = resolution.get("selector", {})
		lines.append("Bypass scope: " + FxResolverScript.selector_key(byp_selector))
		var fallback := FxResolverScript.resolve(_without_bypass(doc), context)
		if str(fallback.get("status", "")) == "ASSIGNED":
			lines.append("Without the bypass: " + str(fallback.get("look_id", "")))
		return lines
	# disabled bindings that match (fallback explanation)
	for raw in doc.get("bindings", []):
		if raw is Dictionary and not bool((raw as Dictionary).get("enabled", true)):
			if FxResolverScript.selector_matches((raw as Dictionary).get("selector", {}), context):
				lines.append("%s — disabled" % str((raw as Dictionary).get("look_id", "")))
	var chain: Array = resolution.get("chain", [])
	for entry in chain:
		var desc := _selector_human(str(entry.get("selector_key", "")))
		if bool(entry.get("winner", false)):
			lines.append("%s — selected (%s, score %d)" % [str(entry.get("look_id", "")), desc, int(entry.get("score", 0))])
		else:
			lines.append("%s — lower priority (%s, score %d)" % [str(entry.get("look_id", "")), desc, int(entry.get("score", 0))])
	if status == "AMBIGUOUS":
		lines.append("Ambiguous tie — resolved deterministically; fix the bindings.")
	if lines.is_empty():
		lines.append("No matching assignment — neutral design.")
	return lines

func _without_bypass(doc: Dictionary) -> Dictionary:
	var copy: Dictionary = doc.duplicate(true)
	copy["bypasses"] = []
	return copy

func _selector_human(key: String) -> String:
	if key == "":
		return "universal"
	var parts: Array = []
	for pair in key.split("&"):
		var kv := pair.split("=")
		if kv.size() == 2:
			parts.append(str(kv[1]).replace("_", " "))
	return " · ".join(parts) if not parts.is_empty() else key
