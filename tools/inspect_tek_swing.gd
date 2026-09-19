extends SceneTree
func _initialize():
	var m = load("res://assets/teknium/teknium_animations.glb").instantiate()
	var s: Skeleton3D = m.get_node("Teknium_Master_Armature/Skeleton3D")
	var p: AnimationPlayer = m.get_node("AnimationPlayer")
	print("SHA ",FileAccess.get_sha256("res://assets/teknium/teknium_animations.glb"))
	for b in s.get_bone_count():
		if str(s.get_bone_name(b)) in ["Hips","Spine","Spine1","Spine2","LeftShoulder","LeftArm","LeftForeArm","LeftHand"]: print(s.get_bone_name(b)," REST ",s.get_bone_rest(b)," GLOBAL ",s.get_bone_global_rest(b))
	for name in ["Idle","Punch"]:
		var a = p.get_animation(name)
		print(name," length ",a.length)
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D and str(a.track_get_path(t).get_subname(0)) in ["Spine","Spine1","Spine2","LeftShoulder","LeftArm","LeftForeArm"]:
				for time in [0.0,.3,.6,.7,1.0]: print(a.track_get_path(t)," ",time," ",a.rotation_track_interpolate(t,time))
	m.free(); quit()
