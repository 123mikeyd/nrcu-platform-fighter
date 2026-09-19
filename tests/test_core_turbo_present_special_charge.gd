extends "res://tests/test_core_turbo_present_source.gd"
func run() -> void:
	var raw = load("res://assets/turbofit/turbofit_animations.glb").instantiate()
	root.add_child(raw)
	var ap: AnimationPlayer = raw.find_children("*","AnimationPlayer",true,false)[0]
	var sk: Skeleton3D = raw.find_children("*","Skeleton3D",true,false)[0]
	var before := fingerprint(ap)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for name in ap.get_animation_library_list():
		var lib := AnimationLibrary.new()
		for clip in ap.get_animation_library(name).get_animation_list():
			var a: Animation = ap.get_animation_library(name).get_animation(clip).duplicate(true)
			a.loop_mode = Animation.LOOP_NONE
			lib.add_animation(clip,a)
		ap.remove_animation_library(name)
		ap.add_animation_library(name,lib)
	var v = load("res://scripts/core/presentation/turbofit_presenter.gd").new()
	root.add_child(v)
	var kit = load("res://scripts/core/kits/turbofit_specials.gd").new()
	for facing in [-1.0,1.0]:
		kit.cancel()
		v.reset()
		kit.start("charge"+str(facing),Vector2.ZERO,facing)
		var previous := 0.0
		for age in [0.0,0.125,0.25,0.7,1.15,1.5,4.3,10.6]:
			kit.tick(age-previous)
			previous = age
			var snap: Dictionary = kit.snapshot()
			var saved := snap.duplicate(true)
			v.present({"presentation":snap,"facing":-facing},int(age*60))
			var frame := lerpf(1,16,sin(minf(age/.25,1)*PI/2))
			if age > .25: frame = 15+cos((age-.25)*TAU/.9)
			check(v.output.clip == "TwoHandCombo", "actual special snapshot selects charge source")
			check(is_equal_approx(v.output.seconds,(frame-1)/30),"uncapped anticipation source clock")
			ap.play("TwoHandCombo",0)
			ap.seek((frame-1)/30,true)
			sk.force_update_all_bone_transforms()
			raw.rotation.y = facing*PI/2
			raw.scale = Vector3.ONE*1.25
			for b in sk.get_bone_count(): check((v.skeleton.global_transform*v.skeleton.get_bone_global_pose(b)).is_equal_approx(sk.global_transform*sk.get_bone_global_pose(b)),"charge world source pose both facings")
			check(snap == saved and kit.snapshot() == saved,"presentation does not mutate committed state")
			if age > 1.5: check(snap.power == 1 and snap.phase == "anticipation","power caps not anticipation")
	var untouched = load("res://assets/turbofit/turbofit_animations.glb").instantiate()
	check(fingerprint(untouched.find_children("*","AnimationPlayer",true,false)[0]) == before,"source keys duration loops unchanged")
	untouched.free()
	v.free()
	raw.free()
	if not failures: print("PASS: special charge real source both facings indefinite hold immutable")
	quit(1 if failures else 0)
