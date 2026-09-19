@tool
extends SceneTree
## Offline generator; never resizes live physics. See docs/core-collision-authoring.md.
const Profile = preload("res://scripts/core/collision/character_collision_profile.gd")
const Hurtbox = preload("res://scripts/core/collision/generated_hurtbox.gd")
const Roster = preload("res://scripts/roster.gd")

func _init() -> void:
	if "--generate" in OS.get_cmdline_user_args(): call_deferred("_cli")

func _cli() -> void:
	var output := "res://data/collision/generated"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var summary := generate_roster(root, output)
	print(JSON.stringify(summary, "\t"))
	# Missing content is recorded distinctly; partial roster is never exit-success.
	quit(2 if summary.failed_count > 0 else 0)

static func generate_roster(parent: Node, output: String) -> Dictionary:
	var manifest_path := output.path_join("manifest.json")
	var ids: Array = Roster.ids(); var unique: Array[String] = []
	for id in ids:
		if not id in unique: unique.append(id)
	unique.sort()
	var summary := {"generator_version": 1, "roster_count": ids.size(), "unique_count": unique.size(), "generated_count": 0, "analyzed_count": 0, "failed_count": 0, "entries": []}
	var errors: Array[String] = []
	for path in [output, manifest_path]:
		var error := _path_error(path, path == output)
		if not error.is_empty(): errors.append(error)
	for id in unique:
		var error := _path_error(output.path_join(id + ".tres"), false)
		if not error.is_empty(): errors.append(error)
	if errors.is_empty() and DirAccess.make_dir_recursive_absolute(output) != OK:
		errors.append("Cannot create output directory: " + output)
	if not errors.is_empty():
		for id in unique: summary.entries.append({"id": id, "status": "failed", "errors": []})
		return _fail_batch(summary, errors)
	var old: Dictionary = {}
	if FileAccess.file_exists(manifest_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if parsed is Dictionary: old = parsed
	var previous := {}
	for entry in old.get("entries", []): previous[entry.id] = entry
	for id in unique:
		var entry := {"id": id, "status": "failed", "errors": []}
		var meta := source_metadata(id)
		entry.errors = meta.errors
		if meta.errors.is_empty():
			entry.asset = meta.asset
			var f := FileAccess.open(meta.asset, FileAccess.READ)
			if not f or f.get_buffer(4).get_string_from_ascii() != "glTF":
				entry.errors = ["missing GLB content (absent or LFS pointer); no substitute generated"]
			else:
				var packed = load(meta.asset)
				if not packed is PackedScene: entry.errors = ["GLB not imported as PackedScene"]
				else:
					var model: Node3D = packed.instantiate(); parent.add_child(model)
					var result := analyze(model,id,meta.scale); model.free()
					summary.analyzed_count += 1
					entry.errors = result.errors
					if result.errors.is_empty():
						var p = result.profile
						p.source_asset = meta.asset; p.source_sha256 = FileAccess.get_sha256(meta.asset)
						p.provenance.presenter = meta.presenter; p.provenance.presenter_sha256 = meta.presenter_sha256
						p.warnings.append("Rest foot origin does not include animated presenter offsets/root travel; preserve approved presenter behavior when integrating.")
						# Overrides remain separate, never rewritten or baked into generated output.
						var override_path := "res://data/collision/overrides/%s.tres" % id
						var merged: Dictionary = p.merged_with(load(override_path) if ResourceLoader.exists(override_path) else null)
						entry.errors = merged.errors
						if merged.errors.is_empty():
							var target := output.path_join(id+".tres")
							var saved := write_generated(target,p,previous.get(id,{}).get("sha256",""))
							entry.errors = saved.errors
							if saved.errors.is_empty():
								entry.status = "generated"; entry.profile = target; entry.sha256 = saved.sha256
								entry.hurtboxes = p.hurtboxes.size(); entry.vertices = p.provenance.vertices
								entry.body_radius = p.body_radius; entry.body_height = p.body_height; entry.visual_scale = p.visual_scale
								entry.warnings = Array(p.warnings)
								entry.override_resource = override_path if ResourceLoader.exists(override_path) else ""
		if entry.status == "generated": summary.generated_count += 1
		else:
			summary.failed_count += 1
			# Retain last good hash even after refusal; never bless edited content.
			if previous.has(id) and previous[id].has("sha256"): entry.sha256 = previous[id].sha256
		summary.entries.append(entry)
	return _publish_manifest(manifest_path, summary)

static func _publish_manifest(path: String, summary: Dictionary) -> Dictionary:
	var parent_error := _path_error(path.get_base_dir(), true)
	if not parent_error.is_empty(): return _fail_batch(summary, [parent_error])
	var staging := _exclusive_directory(path.get_base_dir())
	if staging.is_empty(): return _fail_batch(summary, ["Cannot stage manifest; retain returned hashes for recovery"])
	var candidate := staging.path_join("manifest-recovery.json")
	var error := _store_text(candidate, JSON.stringify(summary, "	", true) + "\n")
	if error.is_empty():
		summary.recovery_manifest = candidate
		error = _path_error(path, false)
		if error.is_empty() and DirAccess.rename_absolute(candidate, path) != OK:
			error = "Cannot atomically publish collision manifest: " + path
	if not error.is_empty():
		summary.recovery_directory = staging
		return _fail_batch(summary, [error + "; artifacts retained; preserve returned hashes"])
	summary.erase("recovery_manifest")
	DirAccess.remove_absolute(staging)
	return summary

static func _store_text(path: String, text: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file: return "Cannot open staged file: " + path
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_string(path) != text:
		return "Staged file write/readback failed: " + path
	return ""

static func write_generated(path: String, profile: Resource, known_sha256: String) -> Dictionary:
	var path_error := _path_error(path, false)
	if not path_error.is_empty(): return {"errors": [path_error]}
	if not profile.validate().is_empty(): return {"errors": profile.validate()}
	if FileAccess.file_exists(path) and (known_sha256.is_empty() or FileAccess.get_sha256(path) != known_sha256):
		return {"errors": ["Refusing unknown/hand-edited generated file: " + path]}
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return {"errors": ["cannot create output parent"]}
	var staging := _exclusive_directory(path.get_base_dir())
	if staging.is_empty(): return {"errors": ["cannot create exclusive staging directory"]}
	var candidate := staging.path_join("candidate.tres")
	if ResourceSaver.save(profile, candidate) != OK: return {"errors": ["resource save failed; retained staging: " + staging]}
	var text := FileAccess.get_file_as_string(candidate)
	# ResourceSaver's generated IDs depend on instance history. Canonicalize them.
	var re := RegEx.new(); re.compile('id="([^"]+)"')
	var ids := {}; var index := 0
	for match_ in re.search_all(text):
		var old := match_.get_string(1)
		if not ids.has(old): index += 1; ids[old] = "stable_%03d" % index
	for old in ids: text = text.replace('"'+old+'"', '"'+ids[old]+'"')
	var error := _store_text(candidate, text)
	if not error.is_empty(): return {"errors": [error], "recovery_directory": staging}
	var saved = ResourceLoader.load(candidate, "", ResourceLoader.CACHE_MODE_IGNORE)
	if saved == null or not saved.validate().is_empty(): return {"errors": ["saved resource failed readback"], "recovery_directory": staging}
	error = _path_error(path, false)
	if not error.is_empty(): return {"errors": [error], "recovery_directory": staging}
	if FileAccess.file_exists(path) and (known_sha256.is_empty() or FileAccess.get_sha256(path) != known_sha256):
		return {"errors": ["Output changed before publication: " + path], "recovery_directory": staging}
	# Rename replaces an entry, never truncates an aliased (hardlinked) inode.
	if DirAccess.rename_absolute(candidate, path) != OK: return {"errors": ["cannot publish output"], "recovery_directory": staging}
	DirAccess.remove_absolute(staging)
	return {"errors": [], "sha256": FileAccess.get_sha256(path)}


static func _fail_batch(summary: Dictionary, errors: Array[String]) -> Dictionary:
	summary.errors = errors
	summary.generated_count = 0
	summary.failed_count = summary.unique_count
	for entry in summary.entries:
		entry.status = "failed"
		entry.errors.append_array(errors)
	return summary

static func _path_error(path: String, directory: bool) -> String:
	# Inspect every existing component BEFORE normalization/mkdir/open. Broken
	# links count too. Godot has no openat(O_NOFOLLOW): trusted parents required.
	if ".." in path.replace("\\", "/").split("/"):
		return "Refusing parent traversal: " + path
	var absolute := ProjectSettings.globalize_path(path)
	if not absolute.begins_with("/") or "\\" in absolute:
		return "Only local POSIX absolute/res/user paths supported: " + path
	var parts := absolute.split("/", false)
	var parent := "/"
	for i in parts.size():
		var dir := DirAccess.open(parent)
		if not dir: return "Cannot inspect path parent: " + parent
		var name := parts[i]
		if dir.is_link(name): return "Refusing symlink path: " + path
		var is_dir := dir.dir_exists(name)
		var is_file := dir.file_exists(name)
		var needs_dir := i < parts.size() - 1 or directory
		if is_file and needs_dir: return "Expected directory: " + path
		if is_dir and not needs_dir: return "Expected file, found directory: " + path
		if not is_dir and not is_file: return ""
		parent = parent.path_join(name)
	return ""

static func _exclusive_directory(parent: String) -> String:
	# mkdir is the exclusive claim; never reuse an existing file/link/directory.
	var dir := DirAccess.open(parent)
	if not dir: return ""
	for attempt in 32:
		var name := ".collision-stage-%s" % Crypto.new().generate_random_bytes(16).hex_encode()
		var error := dir.make_dir(name)
		if error == OK: return parent.path_join(name)
		if error != ERR_ALREADY_EXISTS: return ""
	return ""

static func source_metadata(id: String) -> Dictionary:
	var stem := "doge" if id == "doge_man" else id
	var path := "res://scripts/core/presentation/%s_presenter.gd" % stem
	if not FileAccess.file_exists(path): path = "res://scripts/%s_visual.gd" % stem
	var text := FileAccess.get_file_as_string(path)
	var asset_re := RegEx.new(); asset_re.compile('const MODEL\\s*=\\s*preload\\("([^"]+)"\\)')
	var scale_re := RegEx.new(); scale_re.compile('scale\\s*=\\s*Vector3.ONE\\s*\\*\\s*([A-Za-z_0-9.]+)')
	var a := asset_re.search(text); var s := scale_re.search(text)
	if not a or not s: return {"errors": ["Cannot resolve authored asset/scale from " + path]}
	var token := s.get_string(1)
	if not token.is_valid_float():
		var constant_re := RegEx.new(); constant_re.compile('const ' + token + '\\s*:?=\\s*([0-9.]+)')
		var c := constant_re.search(text)
		if not c: return {"errors": ["Unresolved scale constant " + token]}
		token = c.get_string(1)
	return {"asset": a.get_string(1), "scale": token.to_float(), "presenter": path, "presenter_sha256": FileAccess.get_sha256(path), "errors": []}

static func _excluded(text: String) -> bool:
	text = text.to_lower()
	for token in ["weapon", "sword", "guitar", "hair", "wing", "staff", "wand", "cape", "horn", "hat"]:
		if token in text: return true
	return false

static func _region(name: String) -> String:
	var n := name.to_lower()
	if _excluded(n): return ""
	if "head" in n and not "end" in n and not "front" in n: return "head"
	if "hip" in n or "pelvis" in n or "spine" in n or "chest" in n: return "torso"
	if "arm" in n or "hand" in n: return "arm"
	if "leg" in n or "foot" in n or "toe" in n: return "leg"
	return ""

static func _relative(node: Node3D, model: Node3D) -> Transform3D:
	# Includes model's own imported transform; excludes any external scene parent.
	var t := node.transform
	var parent := node.get_parent()
	while node != model and parent is Node3D:
		t = parent.transform * t
		if parent == model: break
		parent = parent.get_parent()
	return t

static func _valid_transform(t: Transform3D) -> bool:
	var scales := t.basis.get_scale()
	return t.is_finite() and scales.x > 0 and scales.is_equal_approx(Vector3.ONE * scales.x) and t.basis.determinant() > 0

static func analyze(model: Node3D, id: String, visual_scale: float) -> Dictionary:
	var errors: Array[String] = []
	var p = Profile.new(); p.character_id = id; p.visual_scale = visual_scale
	if not is_finite(visual_scale) or visual_scale <= 0: return {"errors": ["invalid visual scale"]}
	var core := PackedVector3Array()
	var bone_points := {}
	var rigs: Array[Skeleton3D] = []
	for n in model.find_children("*", "Skeleton3D", true, false): rigs.append(n)
	if rigs.size() > 1: return {"errors": ["multiple skeletons unsupported; author explicit mapping"]}
	var vertex_count := 0; var surface_count := 0; var excluded: Array[String] = []
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if _excluded(str(mesh.name)):
			excluded.append(str(mesh.name)); continue
		if not mesh.mesh: errors.append("missing mesh " + str(mesh.name)); continue
		var mt := _relative(mesh, model)
		if not _valid_transform(mt): errors.append("unsupported nonuniform/reflected/invalid mesh scale " + str(mesh.name)); continue
		var rig: Skeleton3D = mesh.get_node_or_null(mesh.skeleton) if not mesh.skeleton.is_empty() else null
		var skin: Skin = mesh.skin
		if skin and not rig: errors.append("skin has no skeleton " + str(mesh.name)); continue
		if rig and not skin: errors.append("skeleton mesh missing skin " + str(mesh.name)); continue
		var rt := _relative(rig, model) if rig else Transform3D.IDENTITY
		if rig and not _valid_transform(rt): errors.append("unsupported skeleton scale"); continue
		for surface in mesh.mesh.get_surface_count():
			if mesh.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: errors.append("unsupported primitive " + str(mesh.name)); continue
			var material: Material = mesh.get_active_material(surface)
			if material and _excluded(material.resource_name): excluded.append(str(mesh.name) + ":" + material.resource_name); continue
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if vertices.is_empty(): errors.append("empty surface"); continue
			vertex_count += vertices.size(); surface_count += 1
			var bones = arrays[Mesh.ARRAY_BONES]; var weights = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := 0
			if skin:
				if bones == null or weights == null or bones.size() != weights.size() or bones.size() % vertices.size() != 0:
					errors.append("missing/malformed skin arrays"); continue
				stride = bones.size() / vertices.size()
				if stride != 4 and stride != 8: errors.append("unsupported skin influence count"); continue
			for i in vertices.size():
				var v: Vector3 = vertices[i]
				if not v.is_finite(): errors.append("nonfinite vertex"); break
				if not skin:
					core.append((mt * v) * visual_scale); continue
				var skinned := Vector3.ZERO; var total := 0.0; var dominant := -1; var maximum := -1.0
				for j in stride:
					var w: float = weights[i*stride+j]
					if not is_finite(w) or w < 0: errors.append("invalid weight"); continue
					if w == 0: continue
					var bind: int = bones[i*stride+j]
					if bind < 0 or bind >= skin.get_bind_count(): errors.append("invalid skin bind index"); continue
					var bn := skin.get_bind_name(bind)
					var b := rig.find_bone(bn) if not bn.is_empty() else skin.get_bind_bone(bind)
					if b < 0 or b >= rig.get_bone_count(): errors.append("missing skin bone " + str(bn)); continue
					var rest := rig.get_bone_global_rest(b)
					var bind_pose := skin.get_bind_pose(bind)
					if not rest.is_finite() or not bind_pose.is_finite(): errors.append("nonfinite rest/bind"); continue
					# Godot skin matrices operate on surface coordinates in skeleton space.
					skinned += (rest * bind_pose * v) * w; total += w
					if w > maximum: maximum = w; dominant = b
				if dominant < 0 or absf(total-1.0) > 0.02: errors.append("unnormalized/empty vertex influences"); continue
				skinned /= total
				var name := rig.get_bone_name(dominant)
				var region := _region(name)
				if region.is_empty(): continue
				if not bone_points.has(dominant): bone_points[dominant] = PackedVector3Array()
				bone_points[dominant].append(rig.get_bone_global_rest(dominant).affine_inverse() * skinned)
				if region in ["torso", "leg"]: core.append((rt * skinned) * visual_scale)
	if not errors.is_empty(): return {"errors": errors}
	if core.is_empty(): return {"errors": ["no supported core envelope"]}
	var lo := core[0]; var hi := core[0]
	for v in core: lo = lo.min(v); hi = hi.max(v)
	p.foot_origin = Vector3(0, lo.y, 0)
	var center := (lo+hi)*0.5
	var radius := 0.0
	for v in core: radius = maxf(radius, Vector2(v.x-center.x,v.z-center.z).length())
	p.body_radius = maxf(radius, 0.001)
	p.body_height = maxf(hi.y-lo.y, 2*p.body_radius)
	p.body_center = Vector3(center.x, p.body_height/2, center.z)
	p.warnings.append("Body is a grounded gameplay capsule fit to core extrema, not a full mesh containment guarantee at rounded caps.")
	p.warnings.append("Dominant-bone segmentation cannot distinguish fused clothing/props/hair with shared weights; manual review required.")
	if rigs.is_empty(): p.warnings.append("No skeleton: static nondecorative mesh envelope only; no fabricated bone hurtboxes.")
	else:
		var rig := rigs[0]
		for b in rig.get_bone_count():
			var name := rig.get_bone_name(b)
			if _region(name).is_empty(): continue
			var points: PackedVector3Array = bone_points.get(b, PackedVector3Array())
			var fallback := points.is_empty()
			if fallback:
				points.append(Vector3.ZERO)
				for child in rig.get_bone_children(b): points.append(rig.get_bone_rest(child).origin)
				if points.size() < 2:
					p.warnings.append("No vertices/child segment for " + name + "; hurtbox omitted"); continue
				p.warnings.append("Skeleton segment fallback for " + name + "; radius heuristic, low confidence")
			var lower := points[0]; var upper := points[0]
			for point in points: lower = lower.min(point); upper = upper.max(point)
			var h = Hurtbox.new(); h.bone_name = name; h.hurtbox_id = name.to_snake_case()
			h.local_transform.origin = (lower+upper)*0.5
			var r := 0.0
			for point in points:
				var d: Vector3 = point-h.local_transform.origin
				r = maxf(r, Vector2(d.x,d.z).length())
			h.radius = maxf(r, maxf((upper-lower).length()*0.12,0.001) if fallback else 0.001)
			h.height = upper.y-lower.y+2*h.radius
			h.confidence = "low_segment_heuristic" if fallback else "medium_dominant_skin_rest"
			h.provenance = "skeleton child segment" if fallback else "dominant weighted vertices; inverse global rest; conservative local vertical capsule"
			p.hurtboxes.append(h)
		p.hurtboxes.sort_custom(func(a,b): return a.hurtbox_id < b.hurtbox_id)
	p.provenance = {"vertices": vertex_count, "surfaces": surface_count, "core_vertices": core.size(), "excluded_meshes": excluded, "space": "body: scaled model rest minus foot_origin; hurtbox: native bone local", "pose": "imported skeleton rest (not animated Idle)", "influence_policy": "dominant positive weight; ties first slot"}
	return {"profile": p, "errors": p.validate()}
