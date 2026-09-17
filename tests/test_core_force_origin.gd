extends SceneTree
func _init(): call_deferred("run")
func run():
	var path := "res://data/contact/force_event.tres"
	if not ResourceLoader.exists(path):
		printerr("FAIL: independent authored force contact bake exists"); quit(1); return
	var data = load(path)
	var samples = JSON.parse_string(FileAccess.get_file_as_string("res://assets/teknium/magic_source_samples.json"))
	var p: Array
	for sample in samples.ForcePush:
		if sample.frame == 46: p = sample.hands.RightHand
	var expected := Vector3(p[0], p[1], p[2])
	var maximum := 0.0
	for facing in [1.0, -1.0]:
		var result: Vector3 = Basis(Vector3.UP, facing * PI / 2) * data.get_meta("model_hand") * 1.25
		maximum = maxf(maximum, result.distance_to(Vector3(expected.x * facing, expected.y, expected.z * facing)))
	print("SOURCE event46 both facings max_world_error=", maximum)
	if maximum > 0.002: printerr("FAIL: authored source event origin"); quit(1)
	else: print("PASS: independent force origin"); quit(0)
