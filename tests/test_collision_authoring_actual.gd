extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var lab = load("res://scenes/collision_authoring_lab.tscn").instantiate(); root.add_child(lab)
	for id in ["teknium","ice_mage"]:
		var path: String = "res://data/collision/generated/" + id + ".tres"
		check(lab.open_profile(path), "actual generated " + id)
		var bytes := FileAccess.get_file_as_bytes(path)
		check(lab.model.position.is_equal_approx(-lab.working.foot_origin), "foot origin already scaled model space")
		check(lab.hurt_wires.size() == lab.working.hurtboxes.size(), "all actual bones resolved")
		var body: Transform3D = lab.body_wire.transform
		var clip: String = lab.animation_player.get_animation_list()[0]
		lab.scrub(clip,0.1)
		check(lab.body_wire.transform == body, "actual body stable")
		var first: Transform3D = lab.hurt_wires[0].transform
		lab.scrub(clip,0.3)
		check(not lab.hurt_wires[0].transform.is_equal_approx(first), "actual hurtbox moves with scrub")
		check(lab.save_override("user://collision_authoring_" + id + ".tres"), "actual override save")
		check(lab.reload_override("user://collision_authoring_" + id + ".tres"), "actual override reload")
		check(bytes == FileAccess.get_file_as_bytes(path), "actual source preserved")
		if DisplayServer.get_name() != "headless":
			await process_frame; await process_frame
			root.get_texture().get_image().save_png("res://.verification/core/collision-authoring-ui/native-"+id+"-"+str(root.size.x)+".png")
	var p = lab.generated.duplicate(true); p.foot_origin = Vector3(0,0.5,0); p.visual_scale = 2
	ResourceSaver.save(p,"user://collision_authoring_origin.tres"); lab.open_profile("user://collision_authoring_origin.tres")
	check(lab.model.position == -p.foot_origin,"nonzero origin is not double-scaled")
	ResourceSaver.save(p,"user://collision_authoring_protected.tres")
	check(not lab.save_override("user://collision_authoring_protected.tres"),"other generated resource protected")
	lab.free()
	print("PASS collision authoring actual" if not failures else "FAILED collision authoring actual")
	quit(1 if failures else 0)
