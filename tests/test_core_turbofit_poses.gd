extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var path := "res://scripts/core/kits/turbofit_contact_pose.gd"
	check(ResourceLoader.exists(path), "renderer-independent authored pose sampler exists")
	if failures:
		quit(1)
		return
	var sampler = load(path).new()
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/air_down_kick_export_verification.json"))
	for sample in fixture.samples:
		var a: Array = sample.bone_world.LeftFoot
		var b: Array = sample.bone_world.LeftToe_End
		var midpoint := (Vector3(a[0], a[1], a[2]) + Vector3(b[0], b[1], b[2])) * 0.5
		for facing in [1.0, -1.0]:
			var expected := Vector3(-midpoint.y * facing, midpoint.z, -midpoint.x * facing) * 1.25
			var actual: Vector3 = sampler.center("AirDownKick", (float(sample.source_frame) - 4.0) / 30.0, facing)
			var tolerance := 0.0001 if int(sample.source_frame) in [4, 16, 17, 18, 19, 42] else 0.012
			check(actual.distance_to(expected) < tolerance, "immutable source down frame %s facing %s" % [sample.source_frame, facing])
	# Side has no exported JSON oracle: independently evaluate unchanged imported
	# source via legacy pose evaluator at every 60Hz sample, both yaw facings.
	var visual = load("res://scripts/turbofit_visual.gd").new()
	root.add_child(visual)
	for facing in [1.0, -1.0]:
		for frame in 31:
			var time := frame / 60.0
			var source: Dictionary = visual.air_side_kick_volume(time, 0.5, facing)
			check(sampler.center("AirSideKick", time, facing).distance_to(source.center) < 0.0001, "side imported source sample %d facing %s" % [frame, facing])
	var retained_materials: Array = []
	for mesh in visual.model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			retained_materials.append(mesh.get_active_material(surface))
	visual.free()
	if failures == 0: print("PASS: core Turbofit immutable down fixtures and source side poses both facings")
	quit(1 if failures else 0)
