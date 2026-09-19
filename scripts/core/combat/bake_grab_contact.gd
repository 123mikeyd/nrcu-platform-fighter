extends SceneTree
## Offline imported GLB evaluation; independent of the immutable source oracle.
func _init(): call_deferred("run")
func run():
	var model = load("res://assets/teknium/teknium_animations.glb").instantiate(); root.add_child(model)
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var data := Resource.new()
	for clip in {"GrabStart": 17, "GrabLoop": 30, "GrabEnd": 13}:
		# Disable looping only on this offline instance to retain inclusive frame58.
		player.get_animation(clip).loop_mode = Animation.LOOP_NONE
		var points := PackedVector3Array()
		for frame in {"GrabStart": 17, "GrabLoop": 30, "GrabEnd": 13}[clip] + 1:
			player.play(clip, 0.0); player.seek(frame / 24.0, true); player.pause()
			skeleton.force_update_all_bone_transforms()
			points.append(model.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")) * Vector3(0, 19.50612449645996, 0))
		data.set_meta(clip, points)
	var error := ResourceSaver.save(data, "res://data/contact/grab_curve.tres")
	print("PASS: independent GLB grab curve bake save=", error)
	model.free(); quit(error)
