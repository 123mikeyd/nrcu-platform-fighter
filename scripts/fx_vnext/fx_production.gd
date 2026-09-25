class_name FxProduction
extends RefCounted
# NRCU FX Lab vNext — Production authority store (specs/10 §1, §3, §5, §6).
#
# Transactional persistence for Looks + Assignments. Every apply follows the
# spec-10 sequence: serialize candidate -> schema+semantic validate -> re-read
# and validate again -> keep a last-known-good recovery copy -> replace
# atomically (rename-over dance) -> re-read and verify. On any failure the
# previous Production authority stays byte-equivalent.
#
# Pure data layer: no UI, no rendering. The lab and the game both read
# Production data through this module.

const FxLookScript := preload("res://scripts/fx_vnext/fx_look.gd")
const FxResolverScript := preload("res://scripts/fx_vnext/fx_resolver.gd")
const FxAssetsScript := preload("res://scripts/fx_vnext/fx_assets.gd")
const FxCompositionScript := preload("res://scripts/fx_vnext/fx_composition.gd")
const FxOperatorsScript := preload("res://scripts/fx_vnext/fx_operators.gd")

var data_dir: String = "res://nrcu_fx_data"

# ---------------------------------------------------------------- paths

func looks_dir() -> String:
	return data_dir.path_join("looks")

func recovery_dir() -> String:
	return data_dir.path_join(".recovery")

func assignments_path() -> String:
	return data_dir.path_join("assignments.json")

func look_path(look_id: String) -> String:
	return looks_dir().path_join(look_id + ".json")

func composition_path() -> String:
	return data_dir.path_join("composition.json")

func ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(looks_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(recovery_dir()))

# ---------------------------------------------------------------- loading

func _read_json(path: String) -> Dictionary:
	# Direct read; falls back to the ".prev" sidecar when the main file is
	# missing (crash between the two renames of a replace cycle).
	for candidate in [path, path + ".prev"]:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			var out: Dictionary = parsed
			if candidate != path:
				out["_recovered_from_prev"] = true
			return out
	return {}

func load_assignments() -> Dictionary:
	# Result: {ok, doc, errors, recovery_required}
	# R3 §23 fix: no existence short-circuit — _read_json falls back to the .prev
	# sidecar (crash between renames) and reports it, so a .prev-only state is
	# loaded or flagged, never silently reported as empty.
	var main := assignments_path()
	var doc := _read_json(main)
	if doc.is_empty():
		if not FileAccess.file_exists(main) and not FileAccess.file_exists(main + ".prev"):
			return {"ok": true, "doc": FxResolverScript.new_assignments(), "errors": [], "recovery_required": false}
		return {"ok": false, "doc": {}, "errors": ["assignments.json unreadable"], "recovery_required": true}
	var from_prev := bool(doc.get("_recovered_from_prev", false))
	doc.erase("_recovered_from_prev")
	var check: Dictionary = FxResolverScript.validate_assignments(doc)
	return {
		"ok": bool(check["ok"]),
		"doc": doc,
		"errors": check["errors"],
		"recovery_required": not bool(check["ok"]) or from_prev,
		"recovered_from_prev": from_prev,
	}

func load_look(look_id: String) -> Dictionary:
	var main := look_path(look_id)
	var raw := _read_json(main)
	if raw.is_empty():
		if not FileAccess.file_exists(main) and not FileAccess.file_exists(main + ".prev"):
			return {"ok": false, "doc": {}, "errors": ["look not found: " + look_id], "recovery_required": false}
		return {"ok": false, "doc": {}, "errors": ["look unreadable: " + look_id], "recovery_required": true}
	var from_prev_look := bool(raw.get("_recovered_from_prev", false))
	raw.erase("_recovered_from_prev")
	var doc := FxLookScript.materialize(raw)
	var check: Dictionary = FxLookScript.validate_input(doc)
	return {"ok": bool(check["ok"]), "doc": doc, "errors": check["errors"], "recovery_required": not bool(check["ok"]) or from_prev_look, "recovered_from_prev": from_prev_look}

func load_composition() -> Dictionary:
	var main := composition_path()
	var raw := _read_json(main)
	if raw.is_empty():
		if not FileAccess.file_exists(main) and not FileAccess.file_exists(main + ".prev"):
			return {"ok": true, "doc": {}, "errors": [], "recovery_required": false}
		return {"ok": false, "doc": {}, "errors": ["composition.json unreadable"], "recovery_required": true}
	var from_prev := bool(raw.get("_recovered_from_prev", false))
	raw.erase("_recovered_from_prev")
	var doc := FxCompositionScript.materialize(raw)
	var check := FxCompositionScript.validate(doc)
	return {"ok": bool(check.get("ok", false)), "doc": doc, "errors": check.get("errors", []), "recovery_required": not bool(check.get("ok", false)) or from_prev, "recovered_from_prev": from_prev}

func list_look_ids() -> Array:
	var out: Array = []
	var abs_dir := ProjectSettings.globalize_path(looks_dir())
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".json") and not name.ends_with(".prev"):
			out.append(name.get_basename())
	out.sort()
	return out

func production_state() -> Dictionary:
	# Startup diagnostic per specs/10 §5: valid production / recovery required.
	var assignments := load_assignments()
	var composition := load_composition()
	var errors: Array = []
	errors.append_array(assignments.get("errors", []))
	errors.append_array(composition.get("errors", []))
	var look_errors: Array = []
	var conflict_diagnostics: Array = []
	var known: Dictionary = {}
	var composition_doc: Dictionary = composition.get("doc", {}) if composition.get("doc", {}) is Dictionary else {}
	var composition_active := bool(composition.get("ok", false)) and not composition_doc.is_empty()
	for look_id in list_look_ids():
		known[str(look_id)] = true
		var loaded := load_look(str(look_id))
		var raw_look := _read_json(look_path(str(look_id)))
		if not bool(loaded["ok"]):
			look_errors.append(str(look_id))
		if composition_active:
			var conflict_doc: Dictionary = raw_look if not raw_look.is_empty() else loaded.get("doc", {})
			conflict_diagnostics.append_array(_legacy_final_conflicts(str(look_id), conflict_doc))
	# R3 §23 fix: a binding whose Look file is gone is a broken state, not a
	# silently-valid production.
	if bool(assignments.get("ok", false)):
		for raw in (assignments["doc"] as Dictionary).get("bindings", []):
			if raw is Dictionary:
				var bound_id := str((raw as Dictionary).get("look_id", ""))
				if bound_id != "" and not known.has(bound_id):
					look_errors.append("binding references missing look: " + bound_id)
	errors.append_array(look_errors)
	for conflict in conflict_diagnostics:
		errors.append("MIGRATION_REVIEW_REQUIRED: legacy target-owned FINAL_COMPOSITE conflicts with composition.json (%s layer=%s operator=%s)" % [str(conflict.get("look_id", "")), str(conflict.get("layer_id", "")), str(conflict.get("operator", ""))])
	return {
		"ok": errors.is_empty(),
		"recovery_required": bool(assignments.get("recovery_required", false)) or bool(composition.get("recovery_required", false)) or not look_errors.is_empty() or not conflict_diagnostics.is_empty(),
		"errors": errors,
		"composition_conflicts": conflict_diagnostics,
	}

func _legacy_final_conflicts(look_id: String, look: Dictionary) -> Array:
	var conflicts: Array = []
	for raw_layer in look.get("layers", []):
		if not (raw_layer is Dictionary):
			continue
		var layer: Dictionary = raw_layer
		if not bool(layer.get("enabled", true)):
			continue
		if FxOperatorsScript.lane_for_layer(layer) != "FINAL_COMPOSITE":
			continue
		if str(layer.get("authority", "")) == "COMPOSITION":
			continue
		var fx: Dictionary = layer.get("fx", {}) if layer.get("fx", {}) is Dictionary else {}
		conflicts.append({
			"look_id": look_id,
			"layer_id": str(layer.get("layer_id", "")),
			"operator": str(fx.get("operator", "NONE")),
			"authority": str(layer.get("authority", "")),
			"recommended_action": "remove the legacy final layer or migrate it into composition.json",
		})
	return conflicts
# ---------------------------------------------------------------- usage

func usage(look_id: String) -> Dictionary:
	# RS-06: resolution skips disabled bindings, so every consumer must see
	# the split explicitly. "count" drives resolution-adjacent semantics
	# (shared protection, badges, health); "total_count" (incl. disabled)
	# drives delete protection, since a disabled binding still references
	# the look and re-enabling it must not dangle.
	var assignments := load_assignments()
	var targets: Array = []
	var enabled_count := 0
	for raw in assignments["doc"].get("bindings", []):
		if raw is Dictionary and str((raw as Dictionary).get("look_id", "")) == look_id:
			var is_enabled := bool((raw as Dictionary).get("enabled", true))
			enabled_count += 1 if is_enabled else 0
			targets.append({
				"binding_id": str((raw as Dictionary).get("binding_id", "")),
				"selector": FxResolverScript.normalize_selector((raw as Dictionary).get("selector", {})),
				"selector_key": FxResolverScript.selector_key((raw as Dictionary).get("selector", {})),
				"enabled": is_enabled,
			})
	return {"count": enabled_count, "total_count": targets.size(), "targets": targets}

# ---------------------------------------------------------------- transaction

func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true

func _file_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

func _backup(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var name := path.get_file()
	# DR-11: second-resolution stamps collide within one second — add
	# millisecond precision plus a collision counter so rapid successive
	# backups never silently overwrite each other.
	var stamp := str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_msec() % 1000)
	var target := recovery_dir().path_join("%s.%s.bak" % [name, stamp])
	var attempt := 0
	while FileAccess.file_exists(target) and attempt < 100:
		attempt += 1
		target = recovery_dir().path_join("%s.%s_%d.bak" % [name, stamp, attempt])
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(_file_bytes(path))
	file.close()
	_prune_recovery_history(name)
	return true

func _prune_recovery_history(base_name: String) -> void:
	# R3 §23: bounded recovery history - keep the newest 20 .bak per file.
	var dir := DirAccess.open(recovery_dir())
	if dir == null:
		return
	var matches: Array = []
	for n in dir.get_files():
		var s := str(n)
		if s.begins_with(base_name + ".") and s.ends_with(".bak"):
			matches.append(s)
	if matches.size() <= 20:
		return
	matches.sort()
	for i in range(matches.size() - 20):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(recovery_dir().path_join(str(matches[i]))))

func _replace(path: String) -> Dictionary:
	# tmp -> target with a .prev sidecar so a crash mid-swap is recoverable.
	var tmp := path + ".tmp"
	var prev := path + ".prev"
	if FileAccess.file_exists(prev):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prev))
	if FileAccess.file_exists(path):
		var backup_ok := _backup(path)
		if not backup_ok:
			pass # recovery copy is best-effort; the .prev swap below still guards
		var rename_old := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(prev))
		if rename_old != OK:
			return {"ok": false, "errors": ["replace: cannot park previous file (%d)" % rename_old]}
	var rename_new := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if rename_new != OK:
		# restore previous authority
		if FileAccess.file_exists(prev):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(prev), ProjectSettings.globalize_path(path))
		return {"ok": false, "errors": ["replace: cannot move candidate into place (%d)" % rename_new]}
	if FileAccess.file_exists(prev):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prev))
	return {"ok": true, "errors": []}

func apply(plan: Dictionary) -> Dictionary:
	# plan: {"look": <doc|null>, "assignments": <doc|null>, "composition": <doc|null>, "check_context": <ctx|null>}
	# Returns transactional verification for every supplied authority document.
	ensure_dirs()
	var errors: Array = []
	var look = plan.get("look", null)
	var assignments = plan.get("assignments", null)
	var composition = plan.get("composition", null)
	var look_id := ""
	var revision := 0
	var composition_revision := 0

	if look != null:
		if not (look is Dictionary):
			return {"ok": false, "errors": ["look: not a dictionary"]}
		var input_check: Dictionary = FxLookScript.reject_aliases(look)
		if not bool(input_check.get("ok", false)):
			return {"ok": false, "errors": input_check.get("errors", []), "stage": "validate-input"}
		var normalized := FxLookScript.materialize(look)
		look_id = str(normalized.get("look_id", ""))
		revision = int(normalized.get("revision", 0))
		# Round-2 Finding 15: external masks/textures are imported into
		# project-local production assets before the Look is validated/saved.
		var harvested := _harvest_external_assets(normalized)
		if not bool(harvested["ok"]):
			return {"ok": false, "errors": harvested["errors"], "stage": "assets"}
		normalized = harvested["doc"]
		var look_check: Dictionary = FxLookScript.validate(normalized)
		if not bool(look_check["ok"]):
			return {"ok": false, "errors": look_check["errors"], "stage": "validate-look"}
		# Revision rule (specs/10 §6): exactly +1 on update, 1 on create.
		var existing := load_look(look_id)
		if bool(existing["ok"]):
			var expected := int(existing["doc"].get("revision", 0)) + 1
			if revision != expected:
				return {"ok": false, "errors": ["revision must increment by exactly 1 (got %d, expected %d)" % [revision, expected]], "stage": "revision"}
		elif FileAccess.file_exists(look_path(look_id)):
			return {"ok": false, "errors": ["existing look unreadable; fix Production before updating"], "stage": "revision"}
		elif revision != 1:
			return {"ok": false, "errors": ["new look must start at revision 1"], "stage": "revision"}
		look = normalized

	if composition != null:
		if not (composition is Dictionary):
			return {"ok": false, "errors": ["composition: not a dictionary"]}
		var composition_check := FxCompositionScript.validate(composition)
		if not bool(composition_check.get("ok", false)):
			return {"ok": false, "errors": composition_check.get("errors", []), "stage": "validate-composition"}
		composition = composition_check.get("doc", FxCompositionScript.materialize(composition))
		var existing_composition := load_composition()
		composition_revision = int((composition as Dictionary).get("revision", 0))
		if bool(existing_composition.get("ok", false)) and not (existing_composition.get("doc", {}) as Dictionary).is_empty():
			var expected_composition_revision := int((existing_composition["doc"] as Dictionary).get("revision", 0)) + 1
			if composition_revision != expected_composition_revision:
				return {"ok": false, "errors": ["composition revision must increment by exactly 1 (got %d, expected %d)" % [composition_revision, expected_composition_revision]], "stage": "composition-revision"}
		elif FileAccess.file_exists(composition_path()):
			return {"ok": false, "errors": ["existing composition unreadable; fix Production before updating"], "stage": "composition-revision"}
		elif composition_revision != 1:
			return {"ok": false, "errors": ["new composition must start at revision 1"], "stage": "composition-revision"}

	if assignments != null:
		if not (assignments is Dictionary):
			return {"ok": false, "errors": ["assignments: not a dictionary"]}
		var asg_check: Dictionary = FxResolverScript.validate_assignments(assignments)
		if not bool(asg_check["ok"]):
			return {"ok": false, "errors": asg_check["errors"], "stage": "validate-assignments"}
		# Bindings must point at existing Looks (specs/09 §5).
		for raw in (assignments as Dictionary).get("bindings", []):
			if raw is Dictionary:
				var bound := str((raw as Dictionary).get("look_id", ""))
				if bound != look_id and not FileAccess.file_exists(look_path(bound)):
					return {"ok": false, "errors": ["binding points to missing look: " + bound], "stage": "validate-references"}

	# Write candidates, then re-read + validate again (specs/10 §1 step 4).
	if look != null:
		if not _write_text(look_path(look_id) + ".tmp", FxLookScript.to_json(look)):
			return {"ok": false, "errors": ["cannot write look candidate"], "stage": "write"}
	if assignments != null:
		if not _write_text(assignments_path() + ".tmp", _json_text(assignments)):
			return {"ok": false, "errors": ["cannot write assignments candidate"], "stage": "write"}
	if composition != null:
		if not _write_text(composition_path() + ".tmp", FxCompositionScript.save_text(composition)):
			return {"ok": false, "errors": ["cannot write composition candidate"], "stage": "write"}

	if look != null:
		var reread := _read_json(look_path(look_id) + ".tmp")
		reread.erase("_recovered_from_prev")
		var rc: Dictionary = FxLookScript.validate_input(FxLookScript.materialize(reread))
		if not bool(rc["ok"]):
			_remove_leftovers(look_path(look_id))
			return {"ok": false, "errors": ["candidate re-read invalid: %s" % str(rc["errors"])], "stage": "reread"}
	if assignments != null:
		var reread_asg := _read_json(assignments_path() + ".tmp")
		reread_asg.erase("_recovered_from_prev")
		var rac: Dictionary = FxResolverScript.validate_assignments(reread_asg)
		if not bool(rac["ok"]):
			_remove_leftovers(assignments_path())
			if composition != null:
				_remove_leftovers(composition_path())
			return {"ok": false, "errors": ["assignments candidate re-read invalid: %s" % str(rac["errors"])], "stage": "reread"}

	if composition != null:
		var reread_composition := _read_json(composition_path() + ".tmp")
		reread_composition.erase("_recovered_from_prev")
		var rcc := FxCompositionScript.validate(reread_composition)
		if not bool(rcc.get("ok", false)):
			_remove_leftovers(composition_path())
			return {"ok": false, "errors": ["composition candidate re-read invalid: %s" % str(rcc.get("errors", []))], "stage": "reread"}

	# ---- transactional commit with rollback (specs/10 §1; Round-2 Finding 5) ----
	# Every persisted file affected by this apply is journaled with its exact
	# pre-commit bytes. Any failure - ours, an injected one, or a failed final
	# verification - restores ALL journaled files byte-identically.
	var inject := str(plan.get("inject_failure", ""))
	var writes: Array = []
	if look != null:
		writes.append({"path": look_path(look_id), "label": "look"})
	if assignments != null:
		writes.append({"path": assignments_path(), "label": "assignments"})
	if composition != null:
		writes.append({"path": composition_path(), "label": "composition"})

	if inject == "before_first_commit":
		_remove_leftovers(look_path(look_id))
		_remove_leftovers(assignments_path())
		if composition != null:
			_remove_leftovers(composition_path())
		return {"ok": false, "errors": ["injected failure: before first commit"], "stage": "inject", "rolled_back": true}

	# R3 §8 hardening: crash-safe commit. A transaction marker plus deterministic
	# pre-commit copies make an ABRUPT process death (not just a caught failure)
	# recover to strict last-known-good on the next boot: recover_if_needed()
	# restores every file listed in the marker to its pre-commit bytes.
	_maybe_crash(plan, "before_first_commit")
	var marker_ok := _write_txn_marker(writes)
	if not marker_ok:
		_remove_leftovers(look_path(look_id))
		_remove_leftovers(assignments_path())
		if composition != null:
			_remove_leftovers(composition_path())
		return {"ok": false, "errors": ["transaction marker not writable"], "stage": "replace"}

	var journal: Array = []
	var commit_failed := ""
	for i in range(writes.size()):
		if i == 1 and inject == "after_first_replace":
			commit_failed = "injected failure: after first file replacement"
			break
		if i == 1:
			_maybe_crash(plan, "after_first_replace")
		var w: Dictionary = writes[i]
		var path_str := str(w["path"])
		var abs_path := ProjectSettings.globalize_path(path_str)
		var had_file := FileAccess.file_exists(path_str)
		journal.append({"path": path_str, "had_file": had_file, "prev": _file_bytes(abs_path) if had_file else PackedByteArray()})
		var swap := _replace(path_str)
		if not bool(swap["ok"]):
			_rollback(journal)
			_remove_leftovers(look_path(look_id))
			_remove_leftovers(assignments_path())
			if composition != null:
				_remove_leftovers(composition_path())
			return {"ok": false, "errors": swap["errors"], "stage": "replace", "rolled_back": true}
		if i == 1 and inject == "during_second_replace":
			commit_failed = "injected failure: during second file replacement"
			break
		if i == 1:
			_maybe_crash(plan, "during_second_replace")

	_maybe_crash(plan, "before_final_marker")
	if commit_failed != "" or inject == "before_final_marker":
		_rollback(journal)
		_remove_leftovers(look_path(look_id))
		_remove_leftovers(assignments_path())
		if composition != null:
			_remove_leftovers(composition_path())
		var msg := commit_failed if commit_failed != "" else "injected failure: before final commit marker"
		return {"ok": false, "errors": [msg], "stage": "inject", "rolled_back": true}

	# Final verification (specs/10 §1 steps 6-7). A failed verification also
	# rolls every committed file back to its pre-apply state.
	var verified_look_id := ""
	if look != null:
		var final := load_look(look_id)
		if not bool(final["ok"]) or int(final["doc"].get("revision", 0)) != revision:
			_rollback(journal)
			return {"ok": false, "errors": ["final verification failed for look " + look_id], "stage": "verify", "rolled_back": true}
		verified_look_id = look_id
	if assignments != null:
		var final_asg := load_assignments()
		if not bool(final_asg["ok"]):
			_rollback(journal)
			return {"ok": false, "errors": final_asg["errors"], "stage": "verify", "rolled_back": true}
	if composition != null:
		var final_composition := load_composition()
		if not bool(final_composition.get("ok", false)) or int((final_composition.get("doc", {}) as Dictionary).get("revision", 0)) != composition_revision:
			_rollback(journal)
			return {"ok": false, "errors": ["final verification failed for composition"], "stage": "verify", "rolled_back": true}
	_clear_txn_marker()
	return {"ok": true, "errors": [], "look_revision": revision, "composition_revision": composition_revision, "verified_look_id": verified_look_id}

func _harvest_external_assets(look: Dictionary) -> Dictionary:
	# Rewrites every REQUIRED external asset reference to its imported
	# project-local copy. Dormant (mode-inactive) paths are skipped
	# entirely: a stale unused path must never block an apply, and
	# reactivation re-harvests it (researcher 12-10 §2).
	var import_errors: Array = []
	for layer in look.get("layers", []):
		if not (layer is Dictionary):
			continue
		for field in ["displacement", "mask"]:
			var dep_id := "displacement.custom_texture" if field == "displacement" else "mask.custom_mask"
			if not FxAssetsScript.is_field_required(dep_id, layer):
				continue
			var block = (layer as Dictionary).get(field, null)
			if not (block is Dictionary):
				continue
			var key := "custom_texture" if field == "displacement" else "custom_mask"
			var ref = (block as Dictionary).get(key, null)
			if ref == null or str(ref).strip_edges() == "":
				continue
			var result: Dictionary = FxAssetsScript.ensure_project_ref(str(ref), data_dir)
			if not bool(result.get("ok", false)):
				import_errors.append("%s.%s: %s" % [field, key, str(result.get("errors", []))])
				continue
			(block as Dictionary)[key] = str(result["ref"])
		# MK-04: nested influence-mask asset + fx treatment/edge assets are
		# production assets too — an unharvested external ref would leave
		# Production non-self-contained.
		var disp = (layer as Dictionary).get("displacement", null)
		if disp is Dictionary and FxAssetsScript.is_field_required("displacement.influence_mask.custom_mask", layer):
			var infl = (disp as Dictionary).get("influence_mask", null)
			if infl is Dictionary and (infl as Dictionary).get("custom_mask") != null and str((infl as Dictionary).get("custom_mask")).strip_edges() != "":
				var iresult: Dictionary = FxAssetsScript.ensure_project_ref(str((infl as Dictionary)["custom_mask"]), data_dir)
				if not bool(iresult.get("ok", false)):
					import_errors.append("displacement.influence_mask.custom_mask: %s" % str(iresult.get("errors", [])))
				else:
					(infl as Dictionary)["custom_mask"] = str(iresult["ref"])
		var fx = (layer as Dictionary).get("fx", null)
		if fx is Dictionary and FxAssetsScript.is_field_required("treatment_mask_path", layer):
			for fx_key in ["treatment_mask_path"]:
				var fx_ref = (fx as Dictionary).get(fx_key, null)
				if fx_ref == null or str(fx_ref).strip_edges() == "":
					continue
				var fresult: Dictionary = FxAssetsScript.ensure_project_ref(str(fx_ref), data_dir)
				if not bool(fresult.get("ok", false)):
					import_errors.append("fx.%s: %s" % [fx_key, str(fresult.get("errors", []))])
				else:
					(fx as Dictionary)[fx_key] = str(fresult["ref"])
	if not import_errors.is_empty():
		return {"ok": false, "errors": import_errors, "doc": look}
	return {"ok": true, "errors": [], "doc": look}

func _rollback(journal: Array) -> void:
	# Restores every journaled file to its pre-commit bytes (byte-identical).
	for entry_raw in journal:
		var entry: Dictionary = entry_raw
		var abs_path := ProjectSettings.globalize_path(str(entry["path"]))
		if bool(entry.get("had_file", true)):
			var f := FileAccess.open(abs_path, FileAccess.WRITE)
			if f != null:
				f.store_buffer(entry["prev"])
				f.close()
		elif FileAccess.file_exists(str(entry["path"])):
			DirAccess.remove_absolute(abs_path)
	_clear_txn_marker()

# ---------------------------------------------------------------- R3 §8 crash-safety

func _txn_marker_path() -> String:
	return recovery_dir().path_join(".txn.json")

func _txn_bak_path(path: String) -> String:
	return recovery_dir().path_join(path.get_file() + ".txnbak")

func _write_txn_marker(writes: Array) -> bool:
	# Deterministic pre-commit copies + a marker consumed by recover_if_needed().
	var entries: Array = []
	for w_raw in writes:
		var p := str((w_raw as Dictionary)["path"])
		var had := FileAccess.file_exists(p)
		if had:
			var bak := FileAccess.open(_txn_bak_path(p), FileAccess.WRITE)
			if bak == null:
				return false
			bak.store_buffer(_file_bytes(p))
			bak.close()
		entries.append({"path": p, "had_file": had})
	var f := FileAccess.open(_txn_marker_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"files": entries, "started_unix": Time.get_unix_time_from_system()}))
	f.close()
	return true

func _clear_txn_marker() -> void:
	var marker := _txn_marker_path()
	if FileAccess.file_exists(marker):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(marker))
	var dir := DirAccess.open(recovery_dir())
	if dir != null:
		for name in dir.get_files():
			if str(name).ends_with(".txnbak"):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(recovery_dir().path_join(str(name))))

func recover_if_needed() -> Dictionary:
	# Strict last-known-good crash recovery (R3 §8). Called at boot (shell and VS
	# runtime) and by the crash tests. If a transaction marker exists, the last
	# commit died mid-flight: every file it lists is restored to its pre-commit
	# bytes (or removed if it did not exist before), then the marker is dropped.
	# Regardless of the marker, any *.tmp candidate found at boot is litter from
	# an interrupted transaction (nothing may be in-flight across a boot) and is
	# removed so orphan candidates can never accumulate or be mistaken for state.
	ensure_dirs()
	_sweep_tmp_orphans()
	var marker := _txn_marker_path()
	if not FileAccess.file_exists(marker):
		return {"recovered": false, "files": 0, "errors": []}
	var text := ""
	var mf := FileAccess.open(marker, FileAccess.READ)
	if mf != null:
		text = mf.get_as_text()
		mf.close()
	var parsed = JSON.parse_string(text)
	var entries: Array = []
	if parsed is Dictionary and (parsed as Dictionary).get("files") is Array:
		entries = (parsed as Dictionary)["files"]
	var errors: Array = []
	var restored := 0
	for entry_raw in entries:
		if not (entry_raw is Dictionary):
			continue
		var entry: Dictionary = entry_raw
		var p := str(entry.get("path", ""))
		if p == "":
			continue
		var abs_path := ProjectSettings.globalize_path(p)
		if bool(entry.get("had_file", false)):
			var bak_path := _txn_bak_path(p)
			if FileAccess.file_exists(bak_path):
				var bytes := _file_bytes(bak_path)
				var out := FileAccess.open(abs_path, FileAccess.WRITE)
				if out != null:
					out.store_buffer(bytes)
					out.close()
					restored += 1
				else:
					errors.append("cannot restore " + p)
			else:
				# No transaction copy: fall back to the .prev sidecar, then give up loudly.
				if FileAccess.file_exists(p + ".prev"):
					DirAccess.rename_absolute(ProjectSettings.globalize_path(p + ".prev"), abs_path)
					restored += 1
				else:
					errors.append("recovery copy missing for " + p)
			# Drop the interrupted transaction's unadopted candidates.
			_remove_leftovers(p)
			if FileAccess.file_exists(p + ".prev"):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p + ".prev"))
		else:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(abs_path)
			for leftover in [p + ".tmp", p + ".prev"]:
				if FileAccess.file_exists(leftover):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(leftover))
			restored += 1
	_clear_txn_marker()
	return {"recovered": true, "files": restored, "errors": errors}

func _sweep_tmp_orphans() -> void:
	for dir_path in [data_dir, looks_dir()]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for name in dir.get_files():
			if str(name).ends_with(".tmp"):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_path.path_join(str(name))))

func _maybe_crash(plan: Dictionary, stage: String) -> void:
	# R3 §8: simulates abrupt process termination at a commit stage. Enabled only
	# by the crash tests via plan["crash_at"]; the process is terminated outright.
	if str(plan.get("crash_at", "")) != stage:
		return
	var flag := OS.get_environment("FXLAB_CRASH_FLAG")
	if flag != "":
		var ff := FileAccess.open(flag, FileAccess.WRITE)
		if ff != null:
			ff.store_string("crashing at %s\n" % stage)
			ff.close()
	print("[FX-TXN] crash_at=%s - terminating process now" % stage)
	# Windows: OS.kill(self) is silently ineffective on this platform; taskkill is
	# deterministic. Fallback loop parks the process so the runner's timeout can
	# classify reality if even taskkill fails.
	var pid := OS.get_process_id()
	OS.execute("C:/Windows/System32/taskkill.exe", ["/F", "/PID", str(pid)])
	var t_end := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < t_end:
		OS.delay_msec(50)
	print("[FX-TXN] taskkill did not land; continuing without rollback")

func _remove_leftovers(path: String) -> void:
	for candidate in [path + ".tmp"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))

func _json_text(doc: Dictionary) -> String:
	return JSON.stringify(doc, "  ", true)

# ---------------------------------------------------------------- recovery

func retire_look(look_id: String, mode: String, replacement_look_id := "") -> Dictionary:
	# Round-2 Finding 14: a Look with active bindings is never silently deleted.
	# mode "replace": every binding to look_id is rebound to replacement_look_id
	# (must exist). mode "unassign": those bindings are removed. Both happen in
	# ONE transaction together with the file removal; any failure rolls back.
	ensure_dirs()
	if mode != "replace" and mode != "unassign":
		return {"ok": false, "errors": ["unknown retire mode: " + mode], "stage": "args"}
	if mode == "replace":
		if replacement_look_id == "" or replacement_look_id == look_id:
			return {"ok": false, "errors": ["replacement look required"], "stage": "args"}
		if not FileAccess.file_exists(look_path(replacement_look_id)):
			return {"ok": false, "errors": ["replacement look not found: " + replacement_look_id], "stage": "args"}
		# DR-09: existence is not validity — a corrupt replacement must never
		# receive rebound bindings while the valid original is deleted.
		var replacement_check := load_look(replacement_look_id)
		if not bool(replacement_check.get("ok", false)):
			return {"ok": false, "errors": ["replacement look invalid, keeping " + look_id + ": " + str(replacement_check.get("errors", []))], "stage": "replacement"}
	var loaded := load_assignments()
	if not bool(loaded.get("ok", false)):
		return {"ok": false, "errors": loaded.get("errors", ["assignments unreadable"]), "stage": "load"}
	var doc: Dictionary = loaded["doc"]
	var use := usage(look_id)
	var kept: Array = []
	var changed := 0
	for raw in doc.get("bindings", []):
		if raw is Dictionary and str((raw as Dictionary).get("look_id", "")) == look_id:
			changed += 1
			if mode == "replace":
				var reb: Dictionary = (raw as Dictionary).duplicate(true)
				reb["look_id"] = replacement_look_id
				kept.append(reb)
		else:
			kept.append(raw)
	doc["bindings"] = kept
	var check: Dictionary = FxResolverScript.validate_assignments(doc)
	if not bool(check["ok"]):
		return {"ok": false, "errors": check["errors"], "stage": "validate"}

	# journal: assignments + the look file itself (bytes, or absence)
	var asg_path := assignments_path()
	var abs_asg := ProjectSettings.globalize_path(asg_path)
	var lpath := look_path(look_id)
	var abs_look := ProjectSettings.globalize_path(lpath)
	var journal: Array = [
		{"path": asg_path, "had_file": FileAccess.file_exists(asg_path), "prev": _file_bytes(abs_asg) if FileAccess.file_exists(asg_path) else PackedByteArray()},
		{"path": lpath, "had_file": FileAccess.file_exists(lpath), "prev": _file_bytes(abs_look) if FileAccess.file_exists(lpath) else PackedByteArray()},
	]
	if not _write_text(asg_path + ".tmp", _json_text(doc)):
		_remove_leftovers(asg_path)
		_rollback(journal)
		return {"ok": false, "errors": ["cannot write assignments candidate"], "stage": "write", "rolled_back": true}
	var swap := _replace(asg_path)
	if not bool(swap["ok"]):
		_remove_leftovers(asg_path)
		_rollback(journal)
		return {"ok": false, "errors": swap["errors"], "stage": "replace", "rolled_back": true}
	if FileAccess.file_exists(lpath):
		_backup(lpath)
		DirAccess.remove_absolute(abs_look)
	if FileAccess.file_exists(lpath):
		_rollback(journal)
		return {"ok": false, "errors": ["look removal failed"], "stage": "verify", "rolled_back": true}
	var final_asg := load_assignments()
	if not bool(final_asg.get("ok", false)):
		_rollback(journal)
		return {"ok": false, "errors": ["final verification failed"], "stage": "verify", "rolled_back": true}
	return {"ok": true, "errors": [], "mode": mode, "usage_before": int(use.get("count", 0)), "rebound": changed if mode == "replace" else 0, "unassigned": changed if mode == "unassign" else 0}

func list_recovery() -> Array:
	# DR-11: only real backups — transaction internals (.txn.json, .txnbak)
	# are never history entries.
	var out: Array = []
	var dir := DirAccess.open(ProjectSettings.globalize_path(recovery_dir()))
	if dir == null:
		return out
	for name in dir.get_files():
		var s := str(name)
		if s.ends_with(".bak"):
			out.append(s)
	out.sort()
	return out

func restore_recovery(backup_name: String) -> Dictionary:
	# DR-10: manual restore is explicit and safe — unknown names are refused,
	# the candidate is semantically validated BEFORE it touches authority,
	# the current file is backed up first, and the result is post-verified.
	if not str(backup_name).ends_with(".bak") or str(backup_name).contains("/") or str(backup_name).contains("\\"):
		return {"ok": false, "errors": ["invalid backup name: " + backup_name]}
	var source := recovery_dir().path_join(backup_name)
	if not FileAccess.file_exists(source):
		return {"ok": false, "errors": ["recovery file not found: " + backup_name]}
	# Backup names look like "<file>.json.<stamp>.bak"; strip .bak and the stamp.
	var stem := backup_name.get_basename()
	var last_dot := stem.rfind(".")
	if last_dot != -1:
		stem = stem.substr(0, last_dot)
	var target := ""
	if stem.begins_with("assignments"):
		target = assignments_path()
	else:
		target = looks_dir().path_join(stem)
	var candidate_text := _file_bytes(source).get_string_from_utf8()
	var candidate = JSON.parse_string(candidate_text)
	if not (candidate is Dictionary):
		return {"ok": false, "errors": ["backup is not a JSON document: " + backup_name]}
	if target == assignments_path():
		var asg_check: Dictionary = FxResolverScript.validate_assignments(candidate)
		if not bool(asg_check.get("ok", false)):
			return {"ok": false, "errors": ["backup fails assignments validation: " + str(asg_check.get("errors", []))]}
	else:
		var look_check: Dictionary = FxLookScript.validate_input(FxLookScript.materialize(candidate))
		if not bool(look_check.get("ok", false)):
			return {"ok": false, "errors": ["backup fails look validation: " + str(look_check.get("errors", []))]}
	if not _backup(target):
		return {"ok": false, "errors": ["cannot back up current file before restore"]}
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["cannot restore to " + target]}
	file.store_string(candidate_text)
	file.close()
	if target == assignments_path():
		var verify := load_assignments()
		if not bool(verify.get("ok", false)):
			return {"ok": false, "errors": ["restored assignments unreadable: " + str(verify.get("errors", []))]}
	else:
		var verify := load_look(stem.get_basename())
		if not bool(verify.get("ok", false)):
			return {"ok": false, "errors": ["restored look unreadable: " + str(verify.get("errors", []))]}
	return {"ok": true, "errors": []}

# ------------------------------------------------------- migration review queue
# MIGRATION_REVIEW_REQUIRED looks need a human decision before they can become
# production authority. All three entry points persist through the same
# transactional apply() path, so revision/order/validation guarantees hold.

func list_migration_review_look_ids() -> Array:
	var out: Array = []
	for look_id in list_look_ids():
		var loaded := load_look(str(look_id))
		if bool(loaded.get("ok", false)) and str((loaded["doc"] as Dictionary).get("status", "")) == "MIGRATION_REVIEW_REQUIRED":
			out.append(str(look_id))
	out.sort()
	return out

func load_migration_review(look_id: String) -> Dictionary:
	var loaded := load_look(look_id)
	if not bool(loaded.get("ok", false)):
		return {"ok": false, "errors": loaded.get("errors", ["look not found: " + look_id]), "stage": "load"}
	var doc: Dictionary = loaded["doc"]
	if str(doc.get("status", "")) != "MIGRATION_REVIEW_REQUIRED":
		return {"ok": false, "errors": ["look %s is not pending review (status %s)" % [look_id, str(doc.get("status", ""))]], "stage": "state"}
	var metadata: Dictionary = doc.get("metadata", {})
	return {"ok": true, "errors": [], "doc": doc, "notes": (metadata.get("migration_notes", []) as Array).duplicate()}

func save_migration_repair(look_id: String, repair: Dictionary) -> Dictionary:
	# repair: {"layers": {layer_id: {"fx": {...}, "mask": {...}}}} — merged into
	# the persisted REVIEW document; status stays MIGRATION_REVIEW_REQUIRED.
	var loaded := load_migration_review(look_id)
	if not bool(loaded.get("ok", false)):
		return loaded
	var doc: Dictionary = (loaded["doc"] as Dictionary).duplicate(true)
	var layers_patch: Dictionary = repair.get("layers", {})
	for layer in doc.get("layers", []):
		if not (layer is Dictionary):
			continue
		var lid := str((layer as Dictionary).get("layer_id", ""))
		if not layers_patch.has(lid):
			continue
		var entry: Dictionary = layers_patch[lid]
		if (entry as Dictionary).has("fx"):
			for key in ((entry as Dictionary)["fx"] as Dictionary).keys():
				((layer as Dictionary)["fx"] as Dictionary)[key] = ((entry as Dictionary)["fx"] as Dictionary)[key]
		if (entry as Dictionary).has("mask"):
			for key in ((entry as Dictionary)["mask"] as Dictionary).keys():
				((layer as Dictionary)["mask"] as Dictionary)[key] = ((entry as Dictionary)["mask"] as Dictionary)[key]
	doc["revision"] = int(doc.get("revision", 1)) + 1
	return apply({"look": doc})

func approve_migration_review(look_id: String, acknowledgement: String) -> Dictionary:
	# Acknowledgement-gated: an empty acknowledgement never approves.
	if str(acknowledgement).strip_edges() == "":
		return {"ok": false, "errors": ["approval requires a non-empty acknowledgement"], "stage": "args"}
	var loaded := load_migration_review(look_id)
	if not bool(loaded.get("ok", false)):
		return loaded
	var doc: Dictionary = (loaded["doc"] as Dictionary).duplicate(true)
	doc["status"] = "PRODUCTION"
	doc["revision"] = int(doc.get("revision", 1)) + 1
	var metadata: Dictionary = (doc.get("metadata", {}) as Dictionary).duplicate(true)
	metadata["review"] = {
		"acknowledged": str(acknowledgement),
		"note_count": int((loaded["notes"] as Array).size()),
	}
	doc["metadata"] = metadata
	return apply({"look": doc})
