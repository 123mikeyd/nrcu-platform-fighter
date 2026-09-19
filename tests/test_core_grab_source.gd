extends "res://tests/test_core_grab_slice.gd"
const Grab = preload("res://scripts/core/combat/grab_ability.gd")
func run():
	var oracle = JSON.parse_string(FileAccess.get_file_as_string("res://assets/teknium/magic_source_samples.json"))
	var count := 0; var maximum := 0.0
	for clip in ["GrabStart", "GrabLoop", "GrabEnd"]:
		var first: float = oracle[clip][0].frame
		for point in oracle[clip]:
			var xyz: Array = point.hands.RightHand
			for facing in [1.0, -1.0]:
				var expected := Vector3(xyz[0] * facing, xyz[1], xyz[2] * facing)
				var actual := Grab.sample(clip, (point.frame - first) / 24.0, facing)
				maximum = maxf(maximum, actual.distance_to(expected))
				check(actual.distance_to(expected) <= 0.002, "immutable source " + clip + str(point.frame))
			count += 1
	check(count == 63, "all relevant 63 grab source samples included")
	print("SOURCE grab samples=", count, " both facings maximum_error=", maximum)
	if not failures: print("PASS: grab source (%d checks)" % checks)
	quit(1 if failures else 0)
