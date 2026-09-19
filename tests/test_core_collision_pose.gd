extends SceneTree
var failures := 0
const SAMPLER = "res://scripts/core/collision/committed_pose_sampler.gd"
const SOURCES = ["res://assets/teknium/teknium_animations.glb", "res://assets/ice_mage/ice_mage_combat.glb"]
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	check(ResourceLoader.exists(SAMPLER), "committed pose sampler exists")
	if failures: quit(1); return
	for path in SOURCES:
		var packed: PackedScene = load(path)
		var source = packed.instantiate()
		root.add_child(source)
		var sk: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		print("SOURCE ",path," skeleton=",source.get_path_to(sk)," player=",source.get_path_to(ap)," clips=",ap.get_animation_list())
		var sampler = load(SAMPLER).new()
		check(sampler.configure(packed, source.get_path_to(sk), source.get_path_to(ap)) == OK, "configure actual source")
		var pose: Dictionary = sampler.sample_rest()
		check(pose.size() == sk.get_bone_count(), "all rest bones")
		for bone in sk.get_bone_count():
			check(pose[sk.get_bone_name(bone)].is_equal_approx(sk.global_transform * sk.get_bone_global_rest(bone)), "model local rest oracle")
		source.free()
	if not failures: print("PASS: collision pose imported rest oracle")
	quit(1 if failures else 0)
