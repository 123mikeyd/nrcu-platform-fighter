extends RefCounted
## Explicit derived source allowlist. Original profile anatomy stays unchanged.
const ASSET := "res://assets/teknium/teknium_animations.glb"
const BASE_SHA := "ff49950bf840889ac4537e8cf28be657c324fe42db7c741f2dec49d36d9b32e2"
# Pin the reviewed imported content too: raw GLB bytes do not authenticate remaps.
# Canonical storage graph, Godot 4.7.2; an import-format change requires review.
# v0.2 changes only the two material texture load_path leaves to .s3tc.ctex.
# Full typed graph diff and raw/source regeneration reviewed; no fields omitted.
const SOURCE_CONTENT_SHA := "1bb7ffc30041197bb3558e5a67c79d333d67e76f6d3e45d8942220ee1221d72e"
const LIBRARY := "res://data/animation/teknium_swing_v1.tres"
const SHA := "e333b4bb119d52f1a6cf8e7f1528694a5159e723576e8292263ae19ae5e125a6"
const CLIP := "SwingPunchV1"
const SKELETON := NodePath("Teknium_Master_Armature/Skeleton3D")
static func identity() -> Dictionary:
	return {"version":"teknium-swing-v1","asset":LIBRARY,"sha256":SHA,"base_asset":ASSET,"base_sha256":BASE_SHA}
static func validated_library(skeleton: Skeleton3D) -> AnimationLibrary:
	if skeleton == null or FileAccess.get_sha256(ASSET) != BASE_SHA or FileAccess.get_sha256(LIBRARY) != SHA: return null
	var library = ResourceLoader.load(LIBRARY,"AnimationLibrary",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not library is AnimationLibrary or library.get_script() != null: return null
	if library.get_meta("derivation_version","") != "teknium-swing-v1" or library.get_meta("base_asset","") != ASSET or library.get_meta("base_sha256","") != BASE_SHA: return null
	var names = library.get_meta("names",[]); var parents = library.get_meta("parents",[]); var rests = library.get_meta("rests",[])
	if names.size() != skeleton.get_bone_count() or parents.size() != names.size() or rests.size() != names.size(): return null
	for b in names.size():
		if names[b] != str(skeleton.get_bone_name(b)) or parents[b] != skeleton.get_bone_parent(b) or not rests[b].is_equal_approx(skeleton.get_bone_rest(b)): return null
	if library.get_animation_list().size() != 1 or not library.has_animation(CLIP): return null
	return library
static func assembled_source(packed: PackedScene, errors: Array = []) -> PackedScene:
	var sampler = preload("res://scripts/core/collision/committed_pose_sampler.gd").new()
	if packed == null or not sampler.pose_safe_state(packed.get_state()):
		errors.append("unsafe or missing Teknium source scene")
		return null
	if FileAccess.get_sha256(ASSET) != BASE_SHA:
		errors.append("Teknium base source fingerprint mismatch")
		return null
	# Authenticate the supplied complete serialized scene before instantiation.
	# Paths alone or bone rests do not prove root/ancestor coordinate identity.
	var trusted = ResourceLoader.load(ASSET, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not trusted is PackedScene or not sampler.pose_safe_state(trusted.get_state()) or not source_content_authenticated(trusted) or not source_content_authenticated(packed):
		errors.append("Teknium source identity mismatch (scene placement, hierarchy or resources)")
		return null
	# Never instantiate caller-owned data, even after comparison.
	var model := (trusted as PackedScene).instantiate()
	var library := validated_library(model.get_node_or_null(SKELETON))
	if library == null:
		errors.append("Teknium derived library fingerprint, metadata or skeleton proof mismatch")
		model.free()
		return null
	var player: AnimationPlayer = model.get_node("AnimationPlayer")
	var merged: AnimationLibrary = player.get_animation_library("").duplicate(true)
	merged.add_animation(CLIP,library.get_animation(CLIP))
	player.remove_animation_library(""); player.add_animation_library("",merged)
	var result := PackedScene.new()
	var error := result.pack(model)
	model.free()
	if error != OK or not sampler.pose_safe_state(result.get_state()):
		errors.append("Teknium derived scene packing or final pose safety validation failed")
		return null
	return result

static func source_content_authenticated(source: PackedScene) -> bool:
	if source == null: return false
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var errors := []
	var content = _source_content(source, 0, errors)
	if not errors.is_empty(): return false
	hash.update(var_to_bytes(content))
	return hash.finish().hex_encode() == SOURCE_CONTENT_SHA

static func _source_content(value: Variant, depth: int = 0, errors: Array = []) -> Variant:
	# Typed, deterministic storage graph: no resource paths/IDs as stand-ins for
	# content. Invalid branches cannot equal the pinned, fully valid graph.
	if depth > 64: errors.append("recursive source content"); return null
	if value is Object:
		if not value is Resource or value.get_script() != null: errors.append("unsupported source object"); return null
		var properties := {}
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE: properties[property.name] = value.get(property.name)
		if value is PackedScene:
			# Scene IDs are random import-time recovery identifiers, not placement.
			# Exclusion is safe ONLY for this standalone, non-inherited scene:
			# inheritance/ID-path lookup can otherwise give these IDs semantics.
			var state: SceneState = value.get_state()
			var bundle: Dictionary = properties[&"_bundled"].duplicate()
			if state.get_base_scene_state() != null or not bundle.get("id_paths", []).is_empty() or not bundle.get("node_paths", []).is_empty():
				errors.append("source scene uses ID recovery paths"); return null
			for node in state.get_node_count():
				if state.get_node_instance(node) != null or not state.get_node_instance_placeholder(node).is_empty():
					errors.append("source scene uses instances"); return null
			bundle.erase("node_ids")
			properties[&"_bundled"] = bundle
		return [TYPE_OBJECT, value.get_class(), _source_content(properties, depth + 1, errors)]
	if value is Dictionary:
		var entries := []
		var keys: Array = value.keys()
		for key in keys:
			if not key is String and not key is StringName: errors.append("unsupported source key"); return null
		# StringName ordering follows intern IDs; sort text, not load order.
		keys.sort_custom(func(a: Variant, b: Variant): return str(a) < str(b))
		for key in keys: entries.append([_source_content(key, depth + 1, errors), _source_content(value[key], depth + 1, errors)])
		return [TYPE_DICTIONARY, entries]
	if value is Array:
		var entries := []
		for entry in value: entries.append(_source_content(entry, depth + 1, errors))
		return [TYPE_ARRAY, entries]
	# Do not let Variant serialization choose float32 versus float64 storage.
	# Every floating component is an exact binary64 LE token, with its type tag;
	# no rounding/tolerances can erase root, bone or animation-key tampering.
	if value is float:
		var bytes := PackedByteArray(); bytes.resize(8); bytes.encode_double(0, value)
		return [TYPE_FLOAT, "f64le", bytes.hex_encode()]
	var components: Array = []
	match typeof(value):
		TYPE_VECTOR2: components = [value.x, value.y]
		TYPE_VECTOR3: components = [value.x, value.y, value.z]
		TYPE_VECTOR4, TYPE_QUATERNION: components = [value.x, value.y, value.z, value.w]
		TYPE_COLOR: components = [value.r, value.g, value.b, value.a]
		TYPE_RECT2: components = [value.position, value.size]
		TYPE_AABB: components = [value.position, value.size]
		TYPE_PLANE: components = [value.normal, value.d]
		TYPE_BASIS: components = [value.x, value.y, value.z]
		TYPE_TRANSFORM2D: components = [value.x, value.y, value.origin]
		TYPE_TRANSFORM3D: components = [value.basis, value.origin]
		TYPE_PROJECTION: components = [value.x, value.y, value.z, value.w]
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			for item in value: components.append(item)
			return [typeof(value), _source_content(components, depth + 1, errors)]
	if not components.is_empty(): return [typeof(value), _source_content(components, depth + 1, errors)]
	return [typeof(value), value]
