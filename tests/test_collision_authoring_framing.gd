extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func run() -> void:
	var lab = load("res://scenes/collision_authoring_lab.tscn").instantiate(); root.add_child(lab)
	lab.open_profile("res://data/collision/generated/ice_mage.tres")
	lab.scrub("Electrocution",0.3)
	await process_frame; await process_frame
	var viewport: Vector2 = lab.camera.get_viewport().size
	for wire in lab.hurt_wires:
		var box: AABB = wire.mesh.get_aabb()
		for i in range(8):
			var point: Vector2 = lab.camera.unproject_position(wire.global_transform * box.get_endpoint(i))
			if not Rect2(Vector2(12,12),viewport-Vector2(24,24)).has_point(point): failures += 1
	if failures: printerr("FAIL: ", failures, " actual hurtbox corners clipped")
	lab.free()
	print("PASS collision authoring framing" if not failures else "FAILED collision authoring framing")
	quit(1 if failures else 0)
