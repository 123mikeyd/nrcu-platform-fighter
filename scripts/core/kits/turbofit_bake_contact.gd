extends SceneTree
## Offline only: derive runtime curves from the installed GLB, never test fixtures.
func _init() -> void: call_deferred("run")
func run() -> void:
	var model = load("res://assets/turbofit/turbofit_animations.glb").instantiate()
	root.add_child(model)
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var data := Resource.new()
	for clip in ["AirSideKick", "AirDownKick"]:
		var side := "Right" if clip == "AirSideKick" else "Left"
		var foot := skeleton.find_bone("mixamorig_" + side + "Foot")
		var toe := skeleton.find_bone("mixamorig_" + side + "Toe_End")
		var duration := 0.5 if clip == "AirSideKick" else 38.0 / 30.0
		var points := PackedVector3Array()
		for frame in roundi(duration * 120.0) + 1:
			player.play(clip, 0.0)
			player.seek(frame / 120.0, true)
			skeleton.force_update_all_bone_transforms()
			var a := skeleton.global_transform * skeleton.get_bone_global_pose(foot).origin
			var b := skeleton.global_transform * skeleton.get_bone_global_pose(toe).origin
			points.append((a + b) * 0.5)
		data.set_meta(clip, points)
	var error := ResourceSaver.save(data, "res://data/contact/turbofit_kick_curves.tres")
	model.free()
	print("Turbofit source curve bake: ", error)
	quit(error)
