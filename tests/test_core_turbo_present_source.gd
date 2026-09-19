extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)
func _init() -> void: call_deferred("run")
func fingerprint(player: AnimationPlayer) -> String:
	var all: Array = []
	for clip in player.get_animation_list():
		var a := player.get_animation(clip)
		var tracks: Array = []
		for t in a.get_track_count():
			var keys: Array = []
			for k in a.track_get_key_count(t): keys.append([a.track_get_key_time(t,k), a.track_get_key_transition(t,k), a.track_get_key_value(t,k)])
			tracks.append([a.track_get_path(t), a.track_get_type(t), a.track_is_enabled(t), a.track_is_imported(t), a.track_get_interpolation_type(t), a.track_get_interpolation_loop_wrap(t), keys])
		all.append([clip,a.length,a.loop_mode,a.step,tracks])
	return var_to_str(all)
func run() -> void:
	var path := "res://scripts/core/presentation/turbofit_presenter.gd"
	check(ResourceLoader.exists(path), "independent committed presenter exists")
	if failures:
		quit(1)
		return
	var source = load("res://assets/turbofit/turbofit_animations.glb").instantiate()
	root.add_child(source)
	var ap: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var before := fingerprint(ap)
	# Private oracle copies allow inclusive endpoints without source loop wrap.
	for libname in ap.get_animation_library_list():
		var lib := AnimationLibrary.new()
		var original := ap.get_animation_library(libname)
		for clip in original.get_animation_list():
			var a: Animation = original.get_animation(clip).duplicate(true)
			a.loop_mode = Animation.LOOP_NONE
			lib.add_animation(clip,a)
		ap.remove_animation_library(libname)
		ap.add_animation_library(libname,lib)
	var v = load(path).new()
	var twin = load(path).new()
	root.add_child(v)
	root.add_child(twin)
	var kit = load("res://scripts/core/kits/turbofit_kit.gd").new()
	var routes := [[Vector2.RIGHT,false,"MeleeHorizontal",0.8],[Vector2.UP,false,"MeleeBackhand",0.8],[Vector2.DOWN,false,"GoalkeeperKick",59.0/60],[Vector2.RIGHT,true,"AirSideKick",0.5],[Vector2.UP,true,"MeleeBackhand",0.8],[Vector2.DOWN,true,"AirDownKick",38.0/30]]
	for facing in [-1.0,1.0]:
		for route in routes:
			kit.cancel()
			var aim: Vector2 = route[0]
			aim.x *= facing
			kit.start(str(route)+str(facing),aim,route[1],facing)
			for elapsed in [0.0,5.0/30,0.2,0.4,0.45,0.5,0.7,route[3]]:
				var request: Dictionary = kit.snapshot().presentation
				request.elapsed = elapsed
				v.present({"presentation":request,"grounded":not route[1]},int(elapsed*60))
				ap.play(route[2],0)
				ap.seek(clampf(elapsed/route[3],0,1)*ap.get_animation(route[2]).length,true)
				sk.force_update_all_bone_transforms()
				check(v.animation_player.assigned_animation == route[2], "six routes reach imported clip")
				for b in sk.get_bone_count(): check(v.skeleton.get_bone_pose(b).is_equal_approx(sk.get_bone_pose(b)), "actual source bone parity "+route[2]+" "+str(b))
				check(is_equal_approx(v.model.rotation.y,facing*PI/2) and v.scale == Vector3.ONE*1.25, "positive scale yaw both facings")
				check(v.position == Vector3.ZERO, "no invented floor offsets")
	# Non-ability mappings compare after the source's .06 transition blend.
	for facing in [-1.0,1.0]:
		for pair in [[{"locomotion":"idle"},"Idle"],[{"locomotion":"walk"},"Walk"],[{"locomotion":"run"},"Run"],[{"locomotion":"rising"},"Jump"],[{"locomotion":"falling"},"FallLoop"],[{"locomotion":"landing"},"Landing"],[{"status":"hitstun","hit_id":1},"HitReactRight"],[{"shielding":true},"BlockIdle"],[{"action":"recovery"},"Jump"]]:
			v.reset()
			var snap: Dictionary = pair[0]
			snap.facing = facing
			v.present(snap,0)
			v.present(snap,12)
			source.rotation.y = facing*PI/2
			source.scale = Vector3.ONE*1.25
			ap.play(pair[1],0)
			ap.seek(0.2,true)
			sk.force_update_all_bone_transforms()
			for b in sk.get_bone_count():
				check((v.skeleton.global_transform*v.skeleton.get_bone_global_pose(b)).is_equal_approx(sk.global_transform*sk.get_bone_global_pose(b)),"world source parity both yaw facings "+pair[1])
	var untouched = load("res://assets/turbofit/turbofit_animations.glb").instantiate()
	check(fingerprint(untouched.find_children("*","AnimationPlayer",true,false)[0]) == before,"source keys duration loops unchanged")
	untouched.free()
	source.free()
	v.free()
	twin.free()
	await process_frame
	if not failures: print("PASS: core turbo presenter source poses six routes both facings immutable duplicate teardown")
	quit(1 if failures else 0)
