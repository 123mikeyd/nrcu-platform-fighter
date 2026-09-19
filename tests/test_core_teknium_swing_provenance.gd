extends SceneTree
const D = preload("res://scripts/core/presentation/teknium_swing_source.gd")
var failures := 0
func check(ok: bool, label: String):
	if not ok: failures += 1; print("FAIL: ", label)
func _initialize():
	if "derived-proof-failure" in OS.get_cmdline_user_args():
		var source: PackedScene = load(D.ASSET)
		var errors := []
		check(D.assembled_source(source, errors) == null, "invalid derived proof refused")
		check(not errors.is_empty(), "derived proof refusal has explicit diagnostic")
		if not failures: print("PASS: Teknium derived proof refusal")
		quit(1 if failures else 0)
		return
	var source: PackedScene = load(D.ASSET)
	# A raw GLB hash alone must not bless a substituted imported artifact.
	var validator = D.new()
	check(validator.has_method("source_content_authenticated"), "imported source content has its own authenticated pin")
	if validator.has_method("source_content_authenticated"):
		check(validator.call("source_content_authenticated", source), "reviewed source content accepted")
		var replacement := source.instantiate()
		replacement.position.x += 10
		var substituted := PackedScene.new()
		check(substituted.pack(replacement) == OK, "pack substituted import fixture")
		check(not validator.call("source_content_authenticated", substituted), "substituted import rejected despite unchanged GLB hash")
		replacement.free()
	var before := snapshot(source)
	var errors := []
	var derived := D.assembled_source(source, errors)
	check(derived != null and errors.is_empty(), "authenticated imported source accepted")
	check(D.assembled_source(source.duplicate(true)) != null, "exact private source copy accepted")
	check(snapshot(source) == before, "assembly preserves full original scene and clips")
	if derived != null:
		check(snapshot(derived) == before, "derived scene preserves original placement, hierarchy, rests and clips")
		var private_model := derived.instantiate()
		var animation: Animation = private_model.get_node("AnimationPlayer").get_animation(D.CLIP)
		var original_key: Vector3 = animation.track_get_key_value(0, 0)
		animation.track_set_key_value(0, 0, original_key + Vector3(10, 0, 0))
		check(animation.track_get_key_value(0, 0) != original_key, "private derived key actually changed")
		private_model.free()
		check(snapshot(source) == before, "private derived key mutation leaves source immutable")
	# Every fixture keeps original bone identities/rests and animation resources.
	for target in [".", "Teknium_Master_Armature", str(D.SKELETON)]:
		for mutation in ["translation", "rotation", "scale"]:
			var model := source.instantiate()
			var node: Node3D = model.get_node(NodePath(target))
			match mutation:
				"translation": node.position.x += 10
				"rotation": node.rotate_y(0.5)
				"scale": node.scale *= Vector3(2, 1, 1)
			var changed := PackedScene.new()
			check(changed.pack(model) == OK, "pack placement fixture")
			errors.clear()
			check(D.assembled_source(changed, errors) == null, "reject " + target + " " + mutation)
			check(not errors.is_empty(), "placement refusal explains source identity mismatch")
			model.free()
	var model := source.instantiate()
	var armature: Node3D = model.get_node("Teknium_Master_Armature")
	var extra := Node3D.new()
	extra.name = "ExtraAncestor"
	model.add_child(extra); extra.owner = model
	armature.owner = null
	armature.reparent(extra, false)
	armature.owner = model
	var changed := PackedScene.new()
	check(changed.pack(model) == OK, "pack extra ancestor fixture")
	check(D.assembled_source(changed) == null, "reject extra ancestor even with identity transform")
	model.free()
	for mutation in ["rest", "parent", "name", "clip", "unsupported_node", "script"]:
		model = source.instantiate()
		var skeleton: Skeleton3D = model.get_node(D.SKELETON)
		match mutation:
			"rest": skeleton.set_bone_rest(1, Transform3D.IDENTITY)
			"parent": skeleton.set_bone_parent(1, -1)
			"name": skeleton.set_bone_name(1, "NotTheSourceBone")
			"clip":
				var player: AnimationPlayer = model.get_node("AnimationPlayer")
				var library: AnimationLibrary = player.get_animation_library("").duplicate(true)
				player.remove_animation_library(""); player.add_animation_library("", library)
				library.get_animation("Punch").length += 1.0
			"unsupported_node":
				var unsupported := Node.new()
				model.add_child(unsupported); unsupported.owner = model
			"script":
				var script := GDScript.new()
				script.source_code = "extends Node3D\nfunc _init():\n	Engine.set_meta(\"teknium_provenance_instantiated\", true)\n"
				check(script.reload() == OK, "synthetic script compiles")
				model.set_script(script)
		changed = PackedScene.new()
		check(changed.pack(model) == OK, "pack identity fixture")
		Engine.remove_meta("teknium_provenance_instantiated")
		errors.clear()
		check(D.assembled_source(changed, errors) == null, "reject " + mutation)
		check(not errors.is_empty(), "explicit refusal for " + mutation)
		check(not Engine.has_meta("teknium_provenance_instantiated"), "no caller script instantiated")
		model.free()
	check(snapshot(source) == before, "all rejected fixtures leave source unchanged")
	check(FileAccess.get_sha256(D.ASSET) == D.BASE_SHA, "original GLB unchanged")
	check(FileAccess.get_sha256(D.LIBRARY) == D.SHA, "derived resource unchanged")
	if not failures: print("PASS: Teknium swing provenance")
	quit(1 if failures else 0)

func snapshot(source: PackedScene) -> PackedByteArray:
	# Independent behavioral snapshot: full hierarchy/placement/rests and all keys.
	var model := source.instantiate()
	var values := []
	var pending := [model]
	while not pending.is_empty():
		var node: Node = pending.pop_front()
		values.append([model.get_path_to(node), node.get_class()])
		if node is Node3D: values.append(node.transform)
		if node is Skeleton3D:
			for bone in node.get_bone_count():
				values.append([node.get_bone_name(bone), node.get_bone_parent(bone), node.get_bone_rest(bone)])
		if node is AnimationPlayer:
			values.append(node.root_node)
			for clip in node.get_animation_list():
				if clip == D.CLIP: continue
				var animation: Animation = node.get_animation(clip)
				values.append([clip, animation.length, animation.loop_mode, animation.step])
				for track in animation.get_track_count():
					values.append([animation.track_get_type(track), animation.track_get_path(track), animation.track_is_enabled(track), animation.track_get_interpolation_type(track), animation.track_get_interpolation_loop_wrap(track)])
					for key in animation.track_get_key_count(track):
						values.append([animation.track_get_key_time(track, key), animation.track_get_key_value(track, key), animation.track_get_key_transition(track, key)])
		pending.append_array(node.get_children())
	model.free()
	return var_to_bytes(values)
