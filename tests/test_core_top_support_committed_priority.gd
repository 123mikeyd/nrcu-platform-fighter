extends "res://tests/test_core_collision_pose_policy.gd"
func run():
	for id in ["teknium","turbofit"]:
		var p = load(POLICY).new(); check(p.configure(metadata(id)).is_empty(),"source configured")
		var c = context(); c.grounded = false; c.locomotion = "falling"
		c.support = {"carrier":2,"generation":1}
		var pose = p.sample(c,10)
		check(pose.state == "supported","actual supported policy prerequisite")
		var held = p.sample(c,10)
		check(held == pose,"unchanged committed tick holds whole request")
		c.hit = true; c.hit_id = "new-hit"
		pose = p.sample(c,10)
		check(pose.state == "hit","explicit committed hit wins over lower-priority support even before status reconciliation")
		c.erase("hit"); c.support.clear(); p.sample(c,11)
		c.support = {"carrier":2,"generation":1}; pose = p.sample(c,12)
		check(pose.state == "supported","second genuine support episode prerequisite")
		c.stopped = true
		check(p.sample(c,15) == pose,"stopped source and whole pose hold")
		c.support.clear(); pose = p.sample(c,15)
		check(pose.state != "supported" and pose.clip != "Idle","synchronous stopped release cannot retain stale supported category")
	if not failures: print("PASS: supported policy priority and stopped release")
	quit(1 if failures else 0)
