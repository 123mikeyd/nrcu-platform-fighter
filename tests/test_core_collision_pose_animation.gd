extends "res://tests/test_core_collision_pose.gd"
func fingerprint(player: AnimationPlayer) -> String:
	var data := []
	for clip in player.get_animation_list():
		var a := player.get_animation(clip)
		var tracks := []
		for t in a.get_track_count():
			var keys := []
			for k in a.track_get_key_count(t): keys.append([a.track_get_key_time(t,k),a.track_get_key_value(t,k),a.track_get_key_transition(t,k)])
			tracks.append([a.track_get_type(t),a.track_get_path(t),a.track_is_enabled(t),a.track_is_imported(t),a.track_get_interpolation_type(t),a.track_get_interpolation_loop_wrap(t),keys])
		data.append([clip,a.length,a.loop_mode,a.step,tracks])
	return var_to_str(data)
func run() -> void:
	var sampler = load(SAMPLER).new()
	check(sampler.has_method("sample"), "explicit committed clip-time sampling exists")
	if failures: quit(1); return
	for path in SOURCES:
		var packed: PackedScene = load(path)
		var oracle = packed.instantiate()
		root.add_child(oracle)
		var sk: Skeleton3D = oracle.find_children("*","Skeleton3D",true,false)[0]
		var ap: AnimationPlayer = oracle.find_children("*","AnimationPlayer",true,false)[0]
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var before := fingerprint(ap)
		check(sampler.configure(packed,oracle.get_path_to(sk),oracle.get_path_to(ap)) == OK,"configure")
		for libname in ap.get_animation_library_list():
			var lib := AnimationLibrary.new()
			var original := ap.get_animation_library(libname)
			for clip in original.get_animation_list():
				var a: Animation = original.get_animation(clip).duplicate(true)
				a.loop_mode = Animation.LOOP_NONE
				lib.add_animation(clip,a)
			ap.remove_animation_library(libname)
			ap.add_animation_library(libname,lib)
		for clip in ap.get_animation_list():
			var length := ap.get_animation(clip).length
			print("CLIP ",path," ",clip," length=",length)
			for seconds in [0.0,0.17,length,length+0.2,-0.1]:
				ap.play(clip,0)
				ap.seek(clampf(seconds,0,length),true)
				sk.force_update_all_bone_transforms()
				var pose: Dictionary = sampler.sample(clip,seconds,0)
				check(pose.size() == sk.get_bone_count(),"all animated bones")
				for facing in [-1.0,1.0]:
					var world := Transform3D(Basis(Vector3.UP,facing*PI/2).scaled(Vector3.ONE*(1.15 if "ice_mage" in path else 1.25)), Vector3(3,.035,-2))
					oracle.transform = world
					for b in sk.get_bone_count():
						check((world*pose[sk.get_bone_name(b)]).is_equal_approx(sk.global_transform*sk.get_bone_global_pose(b)),"source animated world parity "+clip+" "+str(seconds)+" "+str(b))
				oracle.transform = Transform3D.IDENTITY
		var untouched = packed.instantiate()
		check(fingerprint(untouched.find_children("*","AnimationPlayer",true,false)[0]) == before,"immutable animation fingerprint")
		untouched.free()
		oracle.free()
	if not failures: print("PASS: collision pose all imported clips clamp endpoints both facings immutable")
	quit(1 if failures else 0)
