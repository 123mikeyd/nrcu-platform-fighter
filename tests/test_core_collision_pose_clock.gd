extends "res://tests/test_core_collision_pose_animation.gd"
func run() -> void:
	var a = load(SAMPLER).new()
	check(a.has_method("cache_size") and a.has_method("reset"),"bounded per-instance cache and explicit reset")
	if failures: quit(1); return
	var b = load(SAMPLER).new()
	var initial_nodes := root.get_child_count()
	for path in SOURCES:
		var packed: PackedScene = load(path)
		var oracle = packed.instantiate()
		root.add_child(oracle)
		var sk: Skeleton3D = oracle.find_children("*","Skeleton3D",true,false)[0]
		var ap: AnimationPlayer = oracle.find_children("*","AnimationPlayer",true,false)[0]
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var before := fingerprint(ap)
		for sampler in [a,b]: check(sampler.configure(packed,oracle.get_path_to(sk),oracle.get_path_to(ap)) == OK,"configure twins")
		for clip in ap.get_animation_list():
			var original := ap.get_animation(clip)
			# Independent looping AnimationPlayer oracle on private copies.
			var lib := ap.get_animation_library("")
			var private_lib: AnimationLibrary = lib.duplicate(true)
			ap.remove_animation_library("")
			ap.add_animation_library("",private_lib)
			ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			var length := original.length
			for seconds in [0.0,length,length*2,length-.0001,length+.17,-.17]:
				ap.play(clip,0)
				ap.seek(fposmod(seconds,length),true)
				sk.force_update_all_bone_transforms()
				var sampled: Dictionary = a.sample(clip,seconds,1)
				for bone in sk.get_bone_count(): check(sampled[sk.get_bone_name(bone)].is_equal_approx(sk.global_transform*sk.get_bone_global_pose(bone)),"explicit loop source oracle "+clip)
				check(a.cache_size() == 1,"bounded one pose cache")
			var snapshot: Dictionary = a.sample(clip,.17,0)
			var names := snapshot.keys()
			var sorted := names.duplicate()
			sorted.sort()
			check(names == sorted,"stable lexical bone order")
			var subset: Dictionary = a.sample(clip,.17,0,PackedStringArray([names[-1],names[0],names[-1]]))
			check(subset.keys() == [names[0],names[-1]],"batch deduped and ordered")
			subset[names[0]] = Transform3D.IDENTITY
			check(a.sample(clip,.17,0) == snapshot,"copied results cannot corrupt cache")
			b.sample(clip,.3,0)
			check(a.sample(clip,.17,0) == snapshot,"twins independent")
			var physics_before := Engine.get_physics_frames()
			for i in 120: check(a.sample(clip,.17,0) == snapshot,"unchanged committed time exact pause")
			check(Engine.get_physics_frames() == physics_before,"sampling never advances physics")
			a.reset()
			check(a.cache_size() == 0 and a.sample(clip,.17,0) == snapshot,"reset discards cache not source")
			check(a.sample(clip,.17,0,PackedStringArray(["NO_BONE"])).is_empty(),"missing bone fail closed")
			ap.remove_animation_library("")
			ap.add_animation_library("",lib)
		check(a.sample("missing",0,0).is_empty() and a.sample("Idle",NAN,0).is_empty() and a.sample("Idle",0,99).is_empty(),"invalid clip time policy")
		check(fingerprint(ap) == before,"loop copies leave source immutable")
		oracle.free()
		check(root.get_child_count() == initial_nodes,"sampler attaches no render or physics nodes")
	if not failures: print("PASS: collision pose loop oracle manual pause batch cache twins reset no physics/render dependency")
	quit(1 if failures else 0)
