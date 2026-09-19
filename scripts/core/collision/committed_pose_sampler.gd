extends RefCounted
## Pure caller-clocked evaluation of private imported bone tracks; no scene tree.
enum TimePolicy { CLAMP, LOOP }
var _rest: Dictionary = {}
var _names: Array = []
var _parents: Array = []
var _local_rest: Array = []
var _placement := Transform3D.IDENTITY
var _clips: Dictionary = {}
var _cache_key: Array = []
var _cache: Dictionary = {}

func configure(source: PackedScene, skeleton_path: NodePath, player_path: NodePath) -> Error:
	reset()
	_rest.clear()
	_names.clear()
	_parents.clear()
	_local_rest.clear()
	_clips.clear()
	if source == null: return ERR_INVALID_PARAMETER
	var state := source.get_state()
	if not pose_safe_state(state): return ERR_UNAVAILABLE
	var nodes := _state_nodes(state)
	var skeleton_key := _resolve_path(".", skeleton_path, nodes)
	var player_key := _resolve_path(".", player_path, nodes)
	if not nodes.has(skeleton_key) or not nodes.has(player_key): return ERR_INVALID_PARAMETER
	if nodes[skeleton_key].type != "Skeleton3D" or nodes[player_key].type != "AnimationPlayer": return ERR_INVALID_PARAMETER
	if not _player_tracks_safe(nodes, player_key, skeleton_key): return ERR_UNAVAILABLE
	var model := _instantiate_source(source)
	var skeleton := model.get_node_or_null(skeleton_path) as Skeleton3D
	var player := model.get_node_or_null(player_path) as AnimationPlayer
	if skeleton == null or player == null:
		model.free()
		return ERR_INVALID_PARAMETER
	var animation_root := player.get_node_or_null(player.root_node)
	for clip in player.get_animation_list():
		var a := player.get_animation(clip)
		for t in a.get_track_count():
			var track_path := a.track_get_path(t)
			if a.track_get_type(t) not in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D] or track_path.get_subname_count() != 1:
				model.free()
				return ERR_UNAVAILABLE
			if animation_root == null or animation_root.get_node_or_null(NodePath(track_path.get_concatenated_names())) != skeleton or skeleton.find_bone(track_path.get_subname(0)) < 0:
				model.free()
				return ERR_UNAVAILABLE
	_placement = Transform3D.IDENTITY
	var node: Node = skeleton
	while node != null:
		if node is Node3D: _placement = node.transform * _placement
		node = node.get_parent()
	for b in skeleton.get_bone_count():
		_names.append(String(skeleton.get_bone_name(b)))
		_parents.append(skeleton.get_bone_parent(b))
		_local_rest.append(skeleton.get_bone_rest(b))
	var sorted := _names.duplicate()
	sorted.sort()
	for bone_name in sorted:
		_rest[bone_name] = _placement * skeleton.get_bone_global_rest(skeleton.find_bone(bone_name))
	for clip in player.get_animation_list():
		var animation: Animation = player.get_animation(clip).duplicate(true)
		animation.loop_mode = Animation.LOOP_NONE
		var bones := []
		for t in animation.get_track_count():
			var path := animation.track_get_path(t)
			bones.append(skeleton.find_bone(path.get_subname(0)) if path.get_subname_count() == 1 else -1)
		_clips[String(clip)] = {"animation":animation,"bones":bones}
	model.free()
	return OK

func _instantiate_source(source: PackedScene) -> Node:
	# Single detached-instantiation seam; tests count attempts, not callbacks.
	return source.instantiate()

func pose_safe_state(state: SceneState) -> bool:
	var nodes := _state_nodes(state)
	if nodes.is_empty(): return false
	for path in nodes:
		if nodes[path].type == "AnimationPlayer" and not _player_tracks_safe(nodes, path): return false
	return true

func _state_nodes(state: SceneState) -> Dictionary:
	# Do not flatten inherited/instanced wrappers: overrides are ambiguous here.
	if state == null or state.get_base_scene_state() != null: return {}
	var nodes := {}
	for n in state.get_node_count():
		if state.get_node_instance(n) != null: return {}
		var type := String(state.get_node_type(n))
		if type not in ["Node3D","Skeleton3D","MeshInstance3D","AnimationPlayer"]: return {}
		var properties := {}
		for p in state.get_node_property_count(n):
			var name := String(state.get_node_property_name(n,p))
			var value = state.get_node_property_value(n,p)
			if name == "script" and value != null: return {}
			if properties.has(name): return {}
			properties[name] = value
		var path := _resolve_path(".",state.get_node_path(n))
		if path.is_empty() or nodes.has(path): return {}
		nodes[path] = {"type":type,"properties":properties}
	return nodes

func _resolve_path(base: String, path: NodePath, nodes: Dictionary = {}) -> String:
	# Only explicit relative node paths, never scene-tree or unique-name lookup.
	if path.is_empty() or path.is_absolute() or path.get_subname_count() != 0: return ""
	var parts := []
	if base != ".": parts.assign(base.split("/"))
	for name in path.get_concatenated_names().split("/"):
		if name == ".": continue
		if name == "..":
			if parts.is_empty(): return ""
			parts.pop_back()
		elif name.is_empty() or name.begins_with("%"):
			return ""
		else: parts.append(name)
		var current := "." if parts.is_empty() else "/".join(parts)
		if not nodes.is_empty() and not nodes.has(current): return ""
	return "." if parts.is_empty() else "/".join(parts)

func _player_tracks_safe(nodes: Dictionary, player_path: String, skeleton_path := "") -> bool:
	var properties: Dictionary = nodes[player_path].properties
	var root_path = properties.get("root_node",NodePath(".."))
	if not root_path is NodePath: return false
	var animation_root := _resolve_path(player_path,root_path,nodes)
	if not nodes.has(animation_root): return false
	for property in properties:
		if property == "libraries" or property == "_libraries": return false
		if not property.begins_with("libraries/"): continue
		var library = properties[property]
		if not library is AnimationLibrary or library.get_script() != null: return false
		for clip in library.get_animation_list():
			var animation: Animation = library.get_animation(clip)
			if animation == null or animation.get_script() != null: return false
			for t in animation.get_track_count():
				if animation.track_get_type(t) not in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]: return false
				var track_path := animation.track_get_path(t)
				if track_path.get_subname_count() != 1: return false
				var target := _resolve_path(animation_root,NodePath(track_path.get_concatenated_names()),nodes)
				if not nodes.has(target) or nodes[target].type != "Skeleton3D": return false
				if not skeleton_path.is_empty() and target != skeleton_path: return false
				var found := false
				var bones: Dictionary = nodes[target].properties
				for bone_property in bones:
					if bone_property.begins_with("bones/") and bone_property.ends_with("/name") and bones[bone_property] == track_path.get_subname(0):
						found = true
				if not found: return false
	return true

func sample_rest() -> Dictionary:
	return _rest.duplicate()

func reset() -> void:
	_cache_key.clear()
	_cache.clear()

func cache_size() -> int:
	return 0 if _cache_key.is_empty() else 1

func sample(clip: String, seconds: float, policy: int, bones: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not _clips.has(clip) or not is_finite(seconds) or policy not in [TimePolicy.CLAMP,TimePolicy.LOOP]: return {}
	for bone_name in bones:
		if not _rest.has(bone_name): return {}
	var key := [clip,seconds,policy]
	if key != _cache_key:
		_cache = pose_evaluate(clip,seconds,policy)
		_cache_key = key
	if bones.is_empty(): return _cache.duplicate()
	var selected := {}
	for bone_name in _cache:
		if bone_name in bones: selected[bone_name] = _cache[bone_name]
	return selected

func pose_evaluate(clip: String, seconds: float, policy: int) -> Dictionary:
	var entry: Dictionary = _clips[clip]
	var animation: Animation = entry.animation
	animation.loop_mode = Animation.LOOP_LINEAR if policy == TimePolicy.LOOP else Animation.LOOP_NONE
	var time := clampf(seconds,0,animation.length)
	if policy == TimePolicy.LOOP: time = fposmod(seconds,animation.length)
	var positions := []
	var rotations := []
	var scales := []
	for rest: Transform3D in _local_rest:
		positions.append(rest.origin)
		rotations.append(rest.basis.get_rotation_quaternion())
		scales.append(rest.basis.get_scale())
	for t in animation.get_track_count():
		var b: int = entry.bones[t]
		if b < 0 or not animation.track_is_enabled(t) or animation.track_get_key_count(t) == 0: continue
		match animation.track_get_type(t):
			Animation.TYPE_POSITION_3D: positions[b] = animation.position_track_interpolate(t,time)
			Animation.TYPE_ROTATION_3D: rotations[b] = animation.rotation_track_interpolate(t,time)
			Animation.TYPE_SCALE_3D: scales[b] = animation.scale_track_interpolate(t,time)
	var locals := []
	for b in _names.size(): locals.append(Transform3D(Basis(rotations[b]) * Basis.from_scale(scales[b]),positions[b]))
	var result := {}
	for bone_name in _rest:
		var b := _names.find(bone_name)
		var pose: Transform3D = locals[b]
		var parent: int = _parents[b]
		while parent >= 0:
			pose = locals[parent] * pose
			parent = _parents[parent]
		result[bone_name] = _placement * pose
	return result
