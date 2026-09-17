extends "res://tests/test_core_tek_swing_source.gd"
func _initialize():
	var m = load("res://assets/teknium/teknium_animations.glb").instantiate()
	var original: Animation = m.get_node("AnimationPlayer").get_animation("Punch")
	var a: Animation = load("res://data/animation/teknium_swing_v1.tres").get_animation("SwingPunchV1")
	var references := [0.0,.20,.42,.70,.80,1.0,1.2916666]
	check(a.length == .32 and a.loop_mode == Animation.LOOP_NONE,"unchanged finite episode")
	check(a.get_track_count() == original.get_track_count(),"no extra translation/scale/offset tracks")
	for track in a.get_track_count():
		check(a.track_get_path(track) == original.track_get_path(track),"same bone track identity")
		var bone := str(a.track_get_path(track).get_subname(0))
		for k in references.size():
			match a.track_get_type(track):
				Animation.TYPE_POSITION_3D: check(a.track_get_key_value(track,k).is_equal_approx(original.position_track_interpolate(track,references[k])),"unchanged connected bone translations "+bone)
				Animation.TYPE_SCALE_3D: check(a.track_get_key_value(track,k).is_equal_approx(original.scale_track_interpolate(track,references[k])),"no stretch "+bone)
				Animation.TYPE_ROTATION_3D:
					if bone not in ["Spine","Spine01","LeftArm","LeftForeArm"] or k in [0,6]:
						check(absf(a.track_get_key_value(track,k).normalized().dot(original.rotation_track_interpolate(track,references[k]).normalized())) > .999999,"unchanged other bones and endpoint rotation "+bone)
	m.free()
	if not failures: print("PASS: connected rotation-only swing authoring preserves root, limbs, original endpoint poses")
	quit(1 if failures else 0)
