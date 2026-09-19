extends "res://tests/test_core_top_support_lifecycle.gd"
func run():
	for upper in ["teknium","turbofit"]:
		var f = setup_pair("teknium",upper)
		await acquire(f)
		var before = f.m.collision_telemetry(1)
		check(before.pose_request.state == "supported","actual supported contact witness before carrier stock")
		f.m.configure_rules(load("res://scripts/core/match/match_rules.gd").new())
		for id in [1,2]: f.m.fighters[id].stocks = 3
		f.b.position.y = -9
		var clock = f.a.runtime.tick
		# This is the real final commit seam, after pre/post-contact pose commits.
		f.m._commit_stocks([1,2])
		check(not f.m.lifecycle_events.is_empty() and f.m.fighters[2].stocks == 2,"actual carrier KO/respawn committed")
		var after = f.m.collision_telemetry(1)
		check(f.m.top_support_telemetry(1).relation.is_empty(),"carrier stock retires relation immediately")
		check(after.pose_request.state != "supported" and after.pose_request.clip != "Idle","same stock commit restores surviving rider air pose")
		check(after.contact_snapshot == before.contact_snapshot,"stock release preserves pre-contact witness")
		check(f.a.runtime.tick == clock,"stock release adds no actor/policy clock")
		dispose(f)
	if not failures: print("PASS: same-commit carrier stock releases surviving supported pose")
	quit(1 if failures else 0)
