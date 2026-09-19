extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ",label)
func _init() -> void: call_deferred("run")
func fingerprint(player: AnimationPlayer) -> String:
	var all: Array = []
	for clip in player.get_animation_list():
		var a := player.get_animation(clip)
		var tracks: Array = []
		for t in a.get_track_count():
			var keys: Array = []
			for k in a.track_get_key_count(t): keys.append([a.track_get_key_time(t,k),a.track_get_key_transition(t,k),a.track_get_key_value(t,k)])
			tracks.append([a.track_get_path(t),a.track_get_type(t),a.track_is_enabled(t),a.track_is_imported(t),a.track_get_interpolation_type(t),a.track_get_interpolation_loop_wrap(t),keys])
		all.append([clip,a.length,a.loop_mode,a.step,tracks])
	return var_to_str(all)
func run() -> void:
	var path := "res://scripts/core/presentation/ice_mage_presenter.gd"
	check(ResourceLoader.exists(path),"independent Ice committed presenter exists")
	if failures: quit(1); return
	var source = load("res://assets/ice_mage/ice_mage_combat.glb").instantiate()
	root.add_child(source)
	var ap: AnimationPlayer = source.find_children("*","AnimationPlayer",true,false)[0]
	var sk: Skeleton3D = source.find_children("*","Skeleton3D",true,false)[0]
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var before := fingerprint(ap)
	for clip in ap.get_animation_list(): print("INSTALLED ",clip," length=",ap.get_animation(clip).length," loop=",ap.get_animation(clip).loop_mode)
	check(FileAccess.get_sha256("res://assets/ice_mage/ice_mage_combat.glb")=="b9bb3756bc2c359e496a9c43b64124a070a83efa838fdef1a46ec6aa02098712","pin actual installed binary, not mismatching manifest")
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
	var host = load("res://scripts/core/kits/ice_mage_host.gd").new()
	for facing in [-1.0,1.0]:
		for airborne in [false,true]:
			for aim in [Vector2.ZERO,Vector2.UP,Vector2.DOWN,Vector2(facing,0)]:
				host.cancel(true)
				check(host.start_basic(str(aim)+str(airborne)+str(facing),aim,airborne,facing),"real basic accepted")
				for step in 33:
					var request: Dictionary = host.snapshot().presentation
					v.present({"presentation":request,"grounded":not airborne},step)
					ap.play("IceStrike",0)
					ap.seek(request.elapsed,true)
					sk.force_update_all_bone_transforms()
					source.rotation.y = facing*PI/2
					source.scale = Vector3.ONE*1.15
					source.position.y = .035
					check(v.output.clip == "IceStrike" and is_equal_approx(v.output.seconds,request.elapsed),"source raw elapsed, not retimed")
					for b in sk.get_bone_count(): check((v.skeleton.global_transform*v.skeleton.get_bone_global_pose(b)).is_equal_approx(sk.global_transform*sk.get_bone_global_pose(b)),"world skeleton source parity both facings bone "+str(b))
					host.prepare(false)
				check(v.scale == Vector3.ONE*1.15 and is_equal_approx(v.position.y,.035),"legacy placement and positive scale")
	# Expanded characterization: raw source seconds for casts, relation and loops.
	for facing in [-1.0,1.0]:
		for clip in ["IceCast","Electrocution","Idle","Walk","Run"]:
			for seconds in [.0,.2,.4]:
				v.reset()
				var snap := {"facing":facing,"grounded":true}
				if clip == "IceCast":
					host.cancel(true)
					host.start_special("cast-oracle",Vector2.UP,facing,true)
					for i in int(round(seconds*60)): host.prepare(false)
					snap.presentation = host.snapshot().presentation
				elif clip == "Electrocution": snap.electrocution = {"activation_id":"relation","elapsed":seconds}
				else: snap.velocity = Vector3(0 if clip == "Idle" else 2 if clip == "Walk" else 5,0,0)
				v.present(snap,0)
				if clip in ["Idle","Walk","Run"]: v.present(snap,int(round(seconds*60)))
				source.rotation.y = facing*PI/2
				ap.play(clip,0)
				ap.seek(seconds,true)
				sk.force_update_all_bone_transforms()
				for b in sk.get_bone_count(): check((v.skeleton.global_transform*v.skeleton.get_bone_global_pose(b)).is_equal_approx(sk.global_transform*sk.get_bone_global_pose(b)),"cast/relation/locomotion world source parity "+clip)
	v.present({"electrocution":{"activation_id":"end","elapsed":2.375}},30)
	ap.play("Electrocution",0)
	ap.seek(2.375,true)
	for b in sk.get_bone_count(): check(v.skeleton.get_bone_pose(b).is_equal_approx(sk.get_bone_pose(b)),"inclusive electrocution endpoint no loop wrap")
	check(twin.output.is_empty(),"duplicate presenter remains independent")
	var untouched = load("res://assets/ice_mage/ice_mage_combat.glb").instantiate()
	check(fingerprint(untouched.find_children("*","AnimationPlayer",true,false)[0])==before,"immutable imported keys loops durations")
	untouched.free()
	source.free()
	v.free()
	twin.free()
	await process_frame
	if not failures: print("PASS: core Ice presentation source poses real host both facings immutable duplicate teardown")
	quit(1 if failures else 0)
