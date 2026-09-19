extends "res://tests/test_core_collision_pose_safety.gd"
func run() -> void:
	var packed := fixture(Animation.TYPE_POSITION_3D)
	var oracle = packed.instantiate()
	var ap: AnimationPlayer = oracle.get_node("Player")
	var sk: Skeleton3D = oracle.get_node("Rig")
	var animation := ap.get_animation("Test")
	animation.length = 1.0
	animation.track_remove_key(0,0)
	animation.position_track_insert_key(0,.2,Vector3(1,2,3))
	animation.position_track_insert_key(0,.8,Vector3(4,5,6))
	animation.loop_mode = Animation.LOOP_LINEAR
	var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(rotation_track,NodePath("Rig:Root"))
	animation.rotation_track_insert_key(rotation_track,0,Quaternion(Vector3.UP,.7))
	var scale_track := animation.add_track(Animation.TYPE_SCALE_3D)
	animation.track_set_path(scale_track,NodePath("Rig:Root"))
	animation.scale_track_insert_key(scale_track,0,Vector3(1,2,3))
	oracle.transform = Transform3D(Basis(Vector3.UP,.3),Vector3(2,1,0))
	sk.transform = Transform3D(Basis(Vector3.RIGHT,.2),Vector3(0,2,0))
	packed = PackedScene.new()
	packed.pack(oracle)
	root.add_child(oracle)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var sampler = load(SAMPLER).new()
	check(sampler.configure(packed,NodePath("Rig"),NodePath("Player")) == OK,"static nested placement fixture")
	for seconds in [0.0,.1,.9,1.0,1.1,-.1]:
		ap.play("Test",0)
		ap.seek(fposmod(seconds,1.0),true)
		sk.force_update_all_bone_transforms()
		check(sampler.sample("Test",seconds,1)["Root"].is_equal_approx(sk.global_transform*sk.get_bone_global_pose(0)),"sparse looping boundary oracle "+str(seconds))
	oracle.free()
	if not failures: print("PASS: collision pose sparse loop interpolation and nested model placement")
	quit(1 if failures else 0)
