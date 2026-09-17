extends "res://tests/test_core_collision_pose_policy.gd"
func run() -> void:
	var policy = load(POLICY).new(); policy.configure(metadata("teknium"))
	var c := context()
	var first: Dictionary = policy.sample(c,0)
	check(first.has("episode_id") and first.has("pose_revision") and first.has("modelplacement") and first.has("rendering_request"),"complete canonical descriptor")
	var advanced: Dictionary = policy.sample(c,12)
	check(is_equal_approx(advanced.source_seconds,.2),"actor tick local clock")
	check(policy.sample(c,12) == advanced,"unchanged tick idempotent")
	c.status = "frozen"
	check(policy.sample(c,20).source_seconds == advanced.source_seconds,"frozen retains complete initialized pose")
	c.status = "normal"
	check(is_equal_approx(policy.sample(c,21).source_seconds,.2+1.0/60),"thaw no catch-up")
	c.status = "hitstun"; c.hit_id = "new-hit"
	var hit: Dictionary = policy.sample(c,21)
	check(hit.clip == "Hit" and hit.source_seconds == 0,"same tick higher priority interrupts")
	var hit_later: Dictionary = policy.sample(c,27)
	c.locomotion = "rising"; c.air_jumps_left = 1
	check(is_equal_approx(policy.sample(c,28).source_seconds,7.0/60),"lower jump cannot restart hit")
	c.hit_id = "another-hit"
	check(policy.sample(c,28).source_seconds == 0,"same clip new hit restarts synchronously")
	check(policy.sample(c,28).get("episode_id") != hit_later.get("episode_id"),"same clip new episode identity")
	c = context(); c.generation = 2
	check(policy.sample(c,0).source_seconds == 0,"generation resets history")
	policy.sample(c,10); policy.reset()
	check(policy.sample(c,10).source_seconds == 0,"explicit lifecycle reset")
	for facing in [-1.0,1.0]:
		policy.reset(); c.facing = facing
		var pose: Dictionary = policy.sample(c,0)
		if pose.has("modelplacement"):
			var expected := Transform3D(Basis(Vector3.UP,facing*PI/2).scaled(Vector3.ONE*1.25),Vector3(0,-.224,0))
			check(pose.modelplacement.is_equal_approx(expected),"grounded offset in actor space; yaw and scale once")
			check(pose.rendering_request.modelplacement == pose.modelplacement and pose.rendering_request.blend_policy == "discrete_committed_no_blend","render host canonical unblended request")
	var other = load(POLICY).new(); other.configure(metadata("teknium"))
	other.sample(context(),0); other.sample(context(),9)
	policy.reset(); check(is_equal_approx(other.sample(context(),10).source_seconds,10.0/60),"duplicate instance independent")
	var stopped := context(); stopped.hitstop = true
	check(other.sample(stopped,11).source_seconds == 10.0/60,"final stopped interval retained regardless remaining")
	if not failures: print("PASS: committed pose policy lifecycle placement")
	quit(1 if failures else 0)
