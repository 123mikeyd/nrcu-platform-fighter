extends "res://tests/test_core_top_support_lifecycle.gd"
func run():
	for upper in ["teknium","turbofit"]:
		var f = setup_pair("turbofit",upper)
		await acquire(f)
		var pose = f.m.collision_telemetry(1).pose_request
		check(pose.get("state","") == "supported" and pose.clip == "Idle","accepted neutral relation commits actual Idle, not airborne bent legs: "+upper)
		check(pose.rendering_request.clip == pose.clip,"canonical sink receives contact source")
		var relation = f.m.top_support_telemetry(1).relation
		var sole = .056 if upper == "turbofit" else .001
		check(is_equal_approx(relation.get("sole_offset",-1),sole),"authored source-derived rider sole ownership")
		check(absf(f.a.position.y+sole-relation.plane)<.0001,"actor anchor plus authored sole equals carrier plane")
		check(not f.a.runtime.grounded and f.a.runtime.air_jumps_left == 0 and f.a.runtime.recovery_spent,"support category is not terrain resource state")
		var tick_before = f.a.runtime.tick
		f.m.top_support.release(1)
		f.m._commit_collision_poses([1],"presentation")
		pose = f.m.collision_telemetry(1).pose_request
		check(pose.get("state","") != "supported" and pose.clip != "Idle","same-tick relation release restores air source: "+upper)
		check(f.a.runtime.tick == tick_before,"release does not invent pose clock")
		dispose(f)
	if not failures: print("PASS: integrated committed support pose")
	quit(1 if failures else 0)
