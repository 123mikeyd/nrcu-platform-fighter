extends "res://tests/test_core_collision_pose_policy.gd"
func run():
	var policy = load(POLICY).new(); check(policy.configure(metadata("teknium")).is_empty(),"actual metadata")
	var c := context(); c.strike_id = "new-contact"; c.strike_move = "SIDE STRIKE"; c.strike_elapsed = .16; c.source_melee = true
	var pose: Dictionary = policy.sample(c,0)
	check(is_equal_approx(pose.source_seconds,.16/.32*(31.0/24)),"source melee side retimes actual imported punch within unchanged episode")
	check(pose.modelplacement.origin == Vector3.ZERO,"timing-only side change preserves existing grounded visual placement")
	c.strike_elapsed = -1.0
	check(not policy.sample(c,1).get("ok",false),"source-melee side requires a finite nonnegative committed age")
	if not failures: print("PASS: melee canonical timing and placement")
	quit(1 if failures else 0)
