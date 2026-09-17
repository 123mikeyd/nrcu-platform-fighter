extends SceneTree
## Offline GLB sampler. Never reads or overwrites the independent JSON oracle.
func _init(): call_deferred("run")
func run():
	var model = load("res://assets/teknium/teknium_animations.glb").instantiate()
	root.add_child(model)
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play("ForcePush", 0.0)
	player.seek(16.0 / 24.0, true)
	player.pause()
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	skeleton.force_update_all_bone_transforms()
	var hand: Vector3 = model.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")) * Vector3(0, 19.50612449645996, 0)
	var data := Resource.new()
	data.set_meta("model_hand", hand)
	data.set_meta("source_seconds", 16.0 / 24.0)
	data.set_meta("source_frame", 46)
	DirAccess.make_dir_recursive_absolute("res://data/contact")
	var error := ResourceSaver.save(data, "res://data/contact/force_event.tres")
	print("BAKE real GLB model-space RightHand tip=", hand, " save=", error)
	model.free(); quit(error)
