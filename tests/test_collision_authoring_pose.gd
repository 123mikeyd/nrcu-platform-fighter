extends SceneTree
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + text)
func _init() -> void: call_deferred("run")
func run() -> void:
	var p = load("res://scripts/core/collision/character_collision_profile.gd").new()
	p.character_id = "teknium_fixture"; p.body_radius = 0.3; p.body_height = 2.0; p.body_center = Vector3(0,1,0)
	p.source_asset = "res://assets/teknium/teknium_animations.glb"; p.visual_scale = 0.01
	var source = load(p.source_asset).instantiate(); root.add_child(source)
	var skeleton = source.find_children("*","Skeleton3D",true,false)[0]
	var h = load("res://scripts/core/collision/generated_hurtbox.gd").new()
	h.hurtbox_id = "fixture_bone"; h.bone_name = skeleton.get_bone_name(0); h.radius = 0.15; h.height = 0.4
	p.hurtboxes.append(h); source.free()
	ResourceSaver.save(p,"user://collision_authoring_teknium_fixture.tres")
	var lab = load("res://scenes/collision_authoring_lab.tscn").instantiate(); root.add_child(lab); lab.open_profile("user://collision_authoring_teknium_fixture.tres")
	check(lab.has_method("scrub"), "manual animation scrub exists")
	if lab.has_method("scrub"):
		check(lab.model != null and lab.skeleton != null, "actual imported model skeleton")
		check(lab.animation_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "manual source clock")
		var clip: String = lab.animation_player.get_animation_list()[0]
		var frozen: Transform3D = lab.body_wire.transform
		check(lab.scrub(clip,0.2), "actual source seek")
		check(lab.body_wire.transform == frozen, "body frozen during animation")
		var expected: Transform3D = lab.skeleton.global_transform * lab.skeleton.get_bone_global_pose(0) * h.local_transform
		check(lab.hurt_wires[0].global_transform.is_equal_approx(expected), "wire follows actual sampled bone")
		check(lab.edit_hurtbox(0,h.bone_name,"0.2","0.5","0.1","0","0"), "editable selected bone capsule")
		check(not lab.edit_hurtbox(0,"absent","0.2","0.5","0","0","0"), "missing bone rejected")
		check(lab.save_override("user://collision_authoring_pose_override.tres") and lab.reload_override("user://collision_authoring_pose_override.tres"), "hurt edit roundtrip")
		check(is_equal_approx(lab.working.hurtboxes[0].local_transform.origin.x, 0.1), "offset preserved")
		check(lab.find_child("AnimationSelector",true,false) != null, "animation controls reachable")
		check(lab.find_child("ProfileSelector",true,false) != null, "discovery selector reachable")
		check(lab.has_method("download_override"), "honest web download route")
		lab.reset_to_generated(true)
		check(is_equal_approx(lab.hurt_fields[0].text.to_float(), p.hurtboxes[0].radius), "reset synchronizes visible hurtbox fields")
		if not DisplayServer.get_name() == "headless":
			await process_frame; await process_frame
			root.get_texture().get_image().save_png("res://.verification/core/collision-authoring-ui/native-1280.png")
	lab.free()
	print("PASS collision authoring pose" if failures == 0 else "FAILED collision authoring pose")
	quit(1 if failures else 0)
