extends "res://tests/test_core_collision_pose_policy.gd"
func run() -> void:
	var policy = load(POLICY).new(); policy.configure(metadata("teknium"))
	var presenter = load("res://scripts/core/presentation/teknium_presenter.gd").new(); root.add_child(presenter)
	var grab = load("res://scripts/core/combat/grab_ability.gd").new(-1.0,"grab1")
	for phase in ["startup","hold","ending"]:
		for age in [0.0,.1,.2,.3,1.25,1.3,2.5]:
			grab.phase = phase; grab.elapsed = age
			var c := context(); c.facing = grab.facing; c.grab = {"activation_id":grab.activation_id,"phase":grab.phase,"elapsed":grab.elapsed,"facing":grab.facing}
			var seconds: float = age
			var clip := "GrabEnd"
			if phase == "startup": clip = "GrabStart"; seconds = age*(13.0/24)/.20 if age <= .20 else 13.0/24+age-.20
			elif phase == "hold": clip = "GrabLoop"; seconds = fmod(age,1.25) if age > 1.25 else age
			c.grab_pose = {"clip":clip,"seconds":seconds}
			policy.reset(); presenter.reset()
			var pose: Dictionary = policy.sample(c,0); presenter.present(c,0)
			check(pose.get("ok",false) and pose.get("clip","") == presenter.animation_player.assigned_animation,"grab phase source clip")
			check(is_equal_approx(pose.get("source_seconds",-1),presenter.animation_player.current_animation_position),"grab inclusive phase source time")
	var c := context(); c.status = "caught"; c.caught = {"activation_id":"captor:hold","elapsed":.6}
	var pose: Dictionary = policy.sample(c,0)
	check(pose.get("clip","") == "Electrocution" and is_equal_approx(pose.get("source_seconds",-1),.6),"caught source age")
	c = context()
	check(policy.sample(c,0).get("clip","") == "Idle","same tick release discards override")
	c.grab = {"activation_id":"g","phase":"hold","elapsed":.3,"facing":1.0}; c.status = "hitstun"; c.hit_id = "h"
	check(policy.sample(c,0).get("clip","") == "Hit","new hit above stale relation")
	for invalid in [{"status":"caught"},{"grab":{"activation_id":"g","phase":"invalid","elapsed":.2,"facing":1.0}},{"caught":{"activation_id":"g"}}]:
		c = context(); c.merge(invalid,true)
		check(not policy.sample(c,0).get("ok",false),"incomplete relation fails closed")
	policy.configure(metadata("turbofit")); c = context(); c.status = "caught"; c.caught = {"activation_id":"g","elapsed":.2}
	pose = policy.sample(c,0)
	check(pose.get("clip","") == "BlockIdle" and pose.get("fallback","") != "","Turbo caught explicit accepted block fallback")
	presenter.free()
	if not failures: print("PASS: committed pose policy grab and caught")
	quit(1 if failures else 0)
