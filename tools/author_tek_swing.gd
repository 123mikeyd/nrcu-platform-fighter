extends SceneTree
## Reproducible offline authoring: private bone keys, never runtime overrides.
const SOURCE := "res://assets/teknium/teknium_animations.glb"
const OUT := "res://data/animation/teknium_swing_v1.tres"
func _initialize():
	var model = load(SOURCE).instantiate()
	var player: AnimationPlayer = model.get_node("AnimationPlayer")
	var original: Animation = player.get_animation("Punch")
	var animation := Animation.new(); animation.resource_scene_unique_id = "TekniumSwingPunchV1"; animation.length = .32; animation.loop_mode = Animation.LOOP_NONE
	var times := [0.0,.075,.115, .167,.20,.25,.32]
	var reference := [0.0,.20,.42,.70,.80,1.0,1.2916666]
	var twist := [0.0,-1.20,-.70,.50,.80,.25,0.0]
	for track in original.get_track_count():
		var t := animation.add_track(original.track_get_type(track))
		animation.track_set_path(t,original.track_get_path(track))
		var bone := str(original.track_get_path(track).get_subname(0))
		for k in times.size():
			match original.track_get_type(track):
				Animation.TYPE_POSITION_3D: animation.position_track_insert_key(t,times[k],original.position_track_interpolate(track,reference[k]))
				Animation.TYPE_SCALE_3D: animation.scale_track_insert_key(t,times[k],original.scale_track_interpolate(track,reference[k]))
				Animation.TYPE_ROTATION_3D:
					var q := original.rotation_track_interpolate(track,reference[k])
					if bone == "Spine": q = Quaternion(Vector3.UP,twist[k])*q
					animation.rotation_track_insert_key(t,times[k],q)
	# Back-contact intent: rotate the connected chain toward a forward extension.
	# Offline keys only: no runtime IK, root warp, scale or position correction.
	var rig: Skeleton3D = model.get_node("Teknium_Master_Armature/Skeleton3D")
	for k in [3,4]:
		_sample_rig(rig,animation,times[k])
		_rotate_global(rig,"Spine01",Quaternion(Vector3.RIGHT,.16))
		var target := Vector3(.025,1.20,.70) if k == 3 else Vector3(-.025,1.20,.69)
		_extend_arm(rig,target / .01)
		for track in animation.get_track_count():
			var bone := str(animation.track_get_path(track).get_subname(0))
			if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D and bone in ["Spine01","LeftArm","LeftForeArm"]:
				animation.track_set_key_value(track,k,rig.get_bone_pose_rotation(rig.find_bone(bone)))
	var library := AnimationLibrary.new(); library.add_animation("SwingPunchV1",animation)
	library.set_meta("derivation_version","teknium-swing-v1")
	library.set_meta("base_asset",SOURCE); library.set_meta("base_sha256",FileAccess.get_sha256(SOURCE))
	var s: Skeleton3D = model.get_node("Teknium_Master_Armature/Skeleton3D")
	var names := []; var parents := []; var rests := []
	for b in s.get_bone_count():
		names.append(str(s.get_bone_name(b))); parents.append(s.get_bone_parent(b)); rests.append(s.get_bone_rest(b))
	library.set_meta("names",names); library.set_meta("parents",parents); library.set_meta("rests",rests)
	DirAccess.make_dir_recursive_absolute("res://data/animation")
	var error := ResourceSaver.save(library,OUT)
	print("AUTHOR ",error," HASH ",FileAccess.get_sha256(OUT))
	model.free(); quit(error)

func _sample_rig(rig: Skeleton3D, animation: Animation, time: float) -> void:
	for track in animation.get_track_count():
		var bone := rig.find_bone(str(animation.track_get_path(track).get_subname(0)))
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D: rig.set_bone_pose_position(bone,animation.position_track_interpolate(track,time))
			Animation.TYPE_SCALE_3D: rig.set_bone_pose_scale(bone,animation.scale_track_interpolate(track,time))
			Animation.TYPE_ROTATION_3D: rig.set_bone_pose_rotation(bone,animation.rotation_track_interpolate(track,time))

func _rotate_global(rig: Skeleton3D, name: String, delta: Quaternion) -> void:
	var b := rig.find_bone(name)
	var parent := _global_pose(rig,rig.get_bone_parent(b)).basis.orthonormalized().get_rotation_quaternion()
	rig.set_bone_pose_rotation(b,(parent.inverse()*delta*parent*rig.get_bone_pose_rotation(b)).normalized())

func _extend_arm(rig: Skeleton3D, target: Vector3) -> void:
	var a := rig.find_bone("LeftArm"); var e := rig.find_bone("LeftForeArm"); var h := rig.find_bone("LeftHand")
	var shoulder := _global_pose(rig,a).origin
	var elbow := _global_pose(rig,e).origin
	var hand := _global_pose(rig,h).origin
	var upper := shoulder.distance_to(elbow); var lower := elbow.distance_to(hand)
	var direction := (target-shoulder).normalized()
	# Retain at least a small elbow bend; never lengthen either segment.
	var reach := minf(shoulder.distance_to(target),sqrt(upper*upper+lower*lower+2*upper*lower*cos(.22)))
	target = shoulder+direction*reach
	var along := (upper*upper-lower*lower+reach*reach)/(2*reach)
	var side := (Vector3.RIGHT-direction*direction.dot(Vector3.RIGHT)).normalized()
	var desired_elbow := shoulder+direction*along+side*sqrt(maxf(0,upper*upper-along*along))
	_rotate_global(rig,"LeftArm",Quaternion((elbow-shoulder).normalized(),(desired_elbow-shoulder).normalized()))
	elbow = _global_pose(rig,e).origin; hand = _global_pose(rig,h).origin
	_rotate_global(rig,"LeftForeArm",Quaternion((hand-elbow).normalized(),(target-elbow).normalized()))

func _global_pose(rig: Skeleton3D, bone: int) -> Transform3D:
	# Detached Skeleton3D caches do not invalidate after every pose mutation.
	# Compose fresh local poses for the offline authoring chain instead.
	var result := rig.get_bone_pose(bone)
	var parent := rig.get_bone_parent(bone)
	while parent >= 0:
		result = rig.get_bone_pose(parent)*result
		parent = rig.get_bone_parent(parent)
	return result
