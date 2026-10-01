extends RefCounted
# FxAssets (Round-2 Finding 15): external masks/textures used by a Look are
# IMPORTED into project-local production assets at apply time; the persisted
# Look only ever references the project-relative copy. A missing asset yields a
# clear invalid/diagnostic state instead of a broken reference.

static func is_external(ref: String) -> bool:
	var text := ref.strip_edges()
	if text == "":
		return false
	if text.begins_with("res://") or text.begins_with("user://"):
		return false
	return true

static func assets_dir(data_dir: String) -> String:
	return data_dir.path_join("assets")

static func import_external(ref: String, data_dir: String) -> Dictionary:
	# Copies the file under a FULL content-hash name and returns the project
	# ref. Content-addressed + immutable: an existing target is reused only
	# after its bytes re-hash to the expected digest; anything else fails
	# closed (never overwrite), and a failed apply only ever orphans an
	# unreferenced blob (researcher 12-10 §4/§6).
	if not FileAccess.file_exists(ref):
		return {"ok": false, "errors": ["external asset not found: " + ref]}
	var bytes := FileAccess.get_file_as_bytes(ref)
	if bytes.is_empty():
		return {"ok": false, "errors": ["external asset unreadable: " + ref]}
	var digest := _sha256(bytes)
	var base := ref.get_file()
	var safe := ""
	for i in range(base.length()):
		var ch := base[i]
		if (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch in [".", "_", "-"]:
			safe += ch
	if safe == "":
		safe = "asset.png"
	var rel := assets_dir(data_dir).path_join(digest + "_" + safe)
	var abs_target := ProjectSettings.globalize_path(rel)
	DirAccess.make_dir_recursive_absolute(abs_target.get_base_dir())
	if FileAccess.file_exists(rel):
		var have := FileAccess.get_file_as_bytes(rel)
		if _sha256(have) != digest:
			return {"ok": false, "errors": ["asset pool integrity failure (hash mismatch, not overwritten): " + rel]}
		return {"ok": true, "ref": rel, "bytes": bytes.size(), "reused": true}
	var out := FileAccess.open(abs_target, FileAccess.WRITE)
	if out == null:
		return {"ok": false, "errors": ["cannot write project asset: " + rel]}
	out.store_buffer(bytes)
	out.close()
	if not FileAccess.file_exists(rel):
		return {"ok": false, "errors": ["project asset missing after import: " + rel]}
	return {"ok": true, "ref": rel, "bytes": bytes.size()}

static func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()

static func ensure_project_ref(ref: String, data_dir: String) -> Dictionary:
	# Verifies a project-local ref (and reports a clear diagnostic if missing).
	# Harvest rule (UI-07/08): res:// is project-local already (existence
	# check only, never duplicated); user:// OUTSIDE the production data dir
	# is an authoring source and gets imported into the project-local assets
	# dir, so Production never depends on an external user file. A user://
	# ref already inside data_dir is a previous harvest result: keep it.
	var text := ref.strip_edges()
	if text == "":
		return {"ok": false, "errors": ["empty asset reference"]}
	if is_external(text):
		return import_external(text, data_dir)
	if text.begins_with("user://") and not _inside_dir(text, data_dir):
		return import_external(text, data_dir)
	if FileAccess.file_exists(text) or ResourceLoader.exists(text):
		return {"ok": true, "ref": text}
	return {"ok": false, "missing": true, "errors": ["asset does not exist: " + text]}

static func _inside_dir(ref: String, data_dir: String) -> bool:
	var ad := assets_dir(data_dir)
	return ref == data_dir or ref.begins_with(data_dir.rstrip("/") + "/") or ref == ad or ref.begins_with(ad.rstrip("/") + "/")

# ---------------------------------------------------------------- UI-07/08:
# central dependency truth. UI rows, INCOMPLETE notes and (via the same
# health rules) validation share these states — never a loose UI if-chain.
# States: NOT_REQUIRED / COMPLETE / MISSING / UNLOADABLE / WRONG_TYPE /
# INVALID. needs_harvest marks authoring sources Production will import.

const DEP_FIELDS := {
	"displacement.custom_texture": {"block": "displacement", "key": "custom_texture"},
	"displacement.influence_mask.custom_mask": {"block": "influence", "key": "custom_mask"},
	"mask.custom_mask": {"block": "mask", "key": "custom_mask"},
	"treatment_mask_path": {"block": "fx", "key": "treatment_mask_path"},
}

static func is_field_required(field_id: String, layer: Dictionary) -> bool:
	if not (layer is Dictionary):
		return false
	match field_id:
		"displacement.custom_texture":
			var draw = layer.get("displacement", {})
			var dd: Dictionary = draw if draw is Dictionary else {}
			return str(dd.get("driver", "NOISE")) == "CUSTOM_TEXTURE"
		"displacement.influence_mask.custom_mask":
			var disraw = layer.get("displacement", {})
			var disd: Dictionary = disraw if disraw is Dictionary else {}
			var infl_raw = disd.get("influence_mask", {})
			var infl: Dictionary = infl_raw if infl_raw is Dictionary else {}
			return bool(infl.get("enabled", false)) and str(infl.get("source", "")) == "CUSTOM_MASK"
		"mask.custom_mask":
			var m_raw = layer.get("mask", {})
			var m: Dictionary = m_raw if m_raw is Dictionary else {}
			return bool(m.get("enabled", false)) and str(m.get("source", "")) == "CUSTOM_MASK"
		"treatment_mask_path":
			var fraw = layer.get("fx", {})
			var fd: Dictionary = fraw if fraw is Dictionary else {}
			return bool(fd.get("effect_mask_enabled", false))
	return false

static func field_path(field_id: String, layer: Dictionary):
	if not DEP_FIELDS.has(field_id) or not (layer is Dictionary):
		return null
	var spec: Dictionary = DEP_FIELDS[field_id]
	var block_name := str(spec["block"])
	var block: Dictionary = {}
	if block_name == "influence":
		var disraw2 = layer.get("displacement", {})
		var disd2: Dictionary = disraw2 if disraw2 is Dictionary else {}
		var iraw = disd2.get("influence_mask", {})
		block = iraw if iraw is Dictionary else {}
	else:
		var braw = layer.get(block_name, {})
		block = braw if braw is Dictionary else {}
	return block.get(str(spec["key"]), null)

static func load_texture(path: String):
	# Runtime texture load that never depends on the editor importer:
	# imported project assets go through ResourceLoader; plain files
	# (user:// staging, harvested copies, absolute picks) decode via Image.
	# Returns the Texture2D, or null when unloadable / wrong type.
	var text := path.strip_edges()
	if ResourceLoader.exists(text, "Texture2D"):
		var res = load(text)
		return res if res is Texture2D else null
	if not FileAccess.file_exists(text):
		return null
	var ext := text.get_extension().to_lower()
	if not is_image_path(text):
		return null
	var img := Image.new()
	if img.load(text) != OK:
		return null
	return ImageTexture.create_from_image(img)

static func asset_health(path) -> Dictionary:
	# EMPTY / MISSING / UNLOADABLE / WRONG_TYPE / COMPLETE (+needs_harvest).
	# Order (researcher 12-10 §3): real Texture2D resources first (any
	# extension, e.g. res://foo.tres), then raw raster files via Image decode.
	if path == null or str(path).strip_edges() == "":
		return {"state": "EMPTY", "detail": "no path set", "needs_harvest": false}
	var text := str(path).strip_edges()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(text)):
		return {"state": "INVALID", "detail": "asset is a directory: " + text, "needs_harvest": false}
	if ResourceLoader.exists(text, "Texture2D"):
		var res = load(text)
		if res is Texture2D:
			return {"state": "COMPLETE", "detail": text, "needs_harvest": false}
		return {"state": "UNLOADABLE", "detail": "registered Texture2D fails to load: " + text, "needs_harvest": false}
	if text.contains("://") and not text.begins_with("res://") and not text.begins_with("user://"):
		return {"state": "INVALID", "detail": "must be project-local: " + text, "needs_harvest": false}
	if text.begins_with("/") or text.contains(":\\"):
		# Absolute OS paths (e.g., fresh FileDialog picks) are harvestable
		# authoring input, never persisted production refs: existing files
		# are COMPLETE + need harvest (flagged by the caller), missing ones
		# are MISSING. Production validation never sees them (harvest
		# rewrites first, or apply already failed at the assets stage).
		if not FileAccess.file_exists(text):
			return {"state": "MISSING", "detail": "asset does not exist: " + text, "needs_harvest": false}
		if not is_image_path(text):
			return {"state": "WRONG_TYPE", "detail": "asset is not a Texture2D: " + text, "needs_harvest": false}
		if load_texture(text) == null:
			return {"state": "UNLOADABLE", "detail": "asset not loadable: " + text, "needs_harvest": false}
		return {"state": "COMPLETE", "detail": text, "needs_harvest": true}
	if not FileAccess.file_exists(text) and not ResourceLoader.exists(text):
		return {"state": "MISSING", "detail": "asset does not exist: " + text, "needs_harvest": false}
	if not is_image_path(text):
		return {"state": "WRONG_TYPE", "detail": "asset is not a Texture2D: " + text, "needs_harvest": false}
	var tex = load_texture(text)
	if tex == null:
		return {"state": "UNLOADABLE", "detail": "asset not loadable: " + text, "needs_harvest": false}
	return {"state": "COMPLETE", "detail": text, "needs_harvest": false}

static func is_image_path(text: String) -> bool:
	var ext := text.get_extension().to_lower()
	return ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp" or ext == "bmp" or ext == "exr"

static func dependency_status(field_id: String, layer: Dictionary, data_dir := "") -> Dictionary:
	# ACTIVE required: valid -> COMPLETE, bad/missing -> blocking states.
	# INACTIVE: empty -> NOT_REQUIRED; valid dormant path -> DORMANT kept
	# (reactivation revalidates); broken dormant path -> DORMANT_WARNING,
	# never a blocking dependency failure (researcher 12-10 §2).
	var required := is_field_required(field_id, layer)
	var path = field_path(field_id, layer)
	if not required and (path == null or str(path).strip_edges() == ""):
		return {"state": "NOT_REQUIRED", "detail": "mode needs no asset", "needs_harvest": false, "required": false}
	var health := asset_health(path)
	if not required:
		if str(health["state"]) == "COMPLETE":
			return {"state": "DORMANT", "detail": "kept, not required by current mode", "needs_harvest": false, "required": false}
		return {"state": "DORMANT_WARNING", "detail": "invalid while unused: " + str(health["detail"]), "needs_harvest": false, "required": false}
	var out := {"state": str(health["state"]), "detail": str(health["detail"]), "required": true, "needs_harvest": false}
	if str(out["state"]) == "EMPTY":
		out["state"] = "MISSING"
		out["detail"] = "required asset missing: " + field_id
	if str(out["state"]) == "COMPLETE" and data_dir != "":
		var text := str(path).strip_edges()
		if bool(health.get("needs_harvest", false)) or (text.begins_with("user://") and not _inside_dir(text, data_dir)) or is_external(text):
			out["needs_harvest"] = true
			out["detail"] = "authoring source, harvested on apply: " + text
	return out
