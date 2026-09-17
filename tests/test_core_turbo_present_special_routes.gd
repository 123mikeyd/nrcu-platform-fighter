extends "res://tests/test_core_turbo_present_source.gd"
func run() -> void:
	var source = load("res://assets/turbofit/turbofit_animations.glb").instantiate()
	root.add_child(source)
	var ap: AnimationPlayer = source.find_children("*","AnimationPlayer",true,false)[0]
	var sk: Skeleton3D = source.find_children("*","Skeleton3D",true,false)[0]
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var before := fingerprint(ap)
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
	var k = load("res://scripts/core/kits/turbofit_specials.gd").new()
	for facing in [-1.0,1.0]:
		for route in [[Vector2.RIGHT,"TwoHandCombo",.54],[Vector2.DOWN,"BlockIdle",.6],[Vector2.UP,"Jump",.64],[Vector2.ZERO,"TwoHandCombo",1.0/3],[Vector2.ZERO,"Idle",.6]]:
			v.reset()
			k.cancel()
			k.start(str(route)+str(facing),route[0]*Vector2(facing,1),facing)
			if route[0] == Vector2.ZERO: k.tick(.01,{"held":false})
			v.present({"presentation":k.snapshot()},0)
			k.tick(route[2])
			var snap: Dictionary = k.snapshot()
			v.present({"presentation":snap,"facing":-facing,"locomotion":"landing"},40)
			check(v.output.clip == route[1],"committed special route selects source "+str(route[0]))
			var seconds: float = route[2]
			if route[0] == Vector2.RIGHT: seconds *= ap.get_animation("TwoHandCombo").length/.7
			if route[0] == Vector2.ZERO: seconds = seconds-1.0/3 if route[1] == "Idle" else seconds+19.0/30
			if route[1] == "BlockIdle": seconds = fmod(seconds,ap.get_animation("BlockIdle").length)
			seconds = minf(seconds,ap.get_animation(route[1]).length)
			check(is_equal_approx(v.output.seconds,seconds),"source rate not gameplay cooldown")
			ap.play(route[1],0)
			ap.seek(seconds,true)
			sk.force_update_all_bone_transforms()
			source.rotation.y = facing*PI/2
			source.scale = Vector3.ONE*1.25
			for b in sk.get_bone_count(): check((v.skeleton.global_transform*v.skeleton.get_bone_global_pose(b)).is_equal_approx(sk.global_transform*sk.get_bone_global_pose(b)),"special world source bones including release endpoint")
			if route[0] != Vector2.ZERO: check(not v.output.fallback.is_empty(),"missing dedicated special/effect asset explicitly labeled")
			check(k.snapshot() == snap,"render does not mutate kit")
			if route[0] == Vector2.DOWN: check(v.output.identity == str(snap.activation_id),"Orb recovery does not restart BlockIdle")
			v.present({"presentation":snap,"hit":true},40)
			check(v.output.clip == "HitReactRight","hit wins all routes")
	var untouched = load("res://assets/turbofit/turbofit_animations.glb").instantiate()
	check(fingerprint(untouched.find_children("*","AnimationPlayer",true,false)[0]) == before,"all source fingerprints immutable")
	untouched.free()
	v.free()
	source.free()
	if not failures: print("PASS: special wave orb recovery release source poses both facings immutable")
	quit(1 if failures else 0)
