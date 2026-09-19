extends "res://tests/test_core_collision_pose.gd"
func fixture(kind: int) -> PackedScene:
	var model := Node3D.new()
	model.name = "Model"
	var sk := Skeleton3D.new()
	sk.name = "Rig"
	model.add_child(sk)
	sk.owner = model
	sk.add_bone("Root")
	var ap := AnimationPlayer.new()
	ap.name = "Player"
	model.add_child(ap)
	ap.owner = model
	var a := Animation.new()
	var t := a.add_track(kind)
	a.track_set_path(t,NodePath("Rig:Root"))
	if kind == Animation.TYPE_POSITION_3D: a.position_track_insert_key(t,0,Vector3.ONE)
	var lib := AnimationLibrary.new()
	lib.add_animation("Test",a)
	ap.add_animation_library("",lib)
	var packed := PackedScene.new()
	packed.pack(model)
	model.free()
	return packed
func run() -> void:
	var sampler = load(SAMPLER).new()
	for kind in [Animation.TYPE_METHOD,Animation.TYPE_AUDIO,Animation.TYPE_ANIMATION,Animation.TYPE_VALUE,Animation.TYPE_BEZIER]:
		check(sampler.configure(fixture(kind),NodePath("Rig"),NodePath("Player")) == ERR_UNAVAILABLE,"reject executable/non-bone track "+str(kind))
		check(sampler.sample_rest().is_empty(),"failure leaves no usable stale source")
	var scripted := Node3D.new()
	var script := GDScript.new()
	script.source_code = "extends Node3D\nfunc _init(): Engine.set_meta(\"pose_safety_probe\",true)\n"
	script.reload()
	scripted.set_script(script)
	var packed := PackedScene.new()
	packed.pack(scripted)
	scripted.free()
	Engine.remove_meta("pose_safety_probe")
	check(sampler.configure(packed,NodePath("Rig"),NodePath("Player")) == ERR_UNAVAILABLE,"reject script before instantiate")
	check(not Engine.has_meta("pose_safety_probe"),"script constructor did not execute")
	if failures: quit(1); return
	check(sampler.configure(null,NodePath("Rig"),NodePath("Player")) == ERR_INVALID_PARAMETER,"null source rejected")
	if not failures: print("PASS: collision pose fail closed tracks scripts null no callbacks")
	quit(1 if failures else 0)
