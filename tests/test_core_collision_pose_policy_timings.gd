extends "res://tests/test_core_collision_pose_policy.gd"
func compare(id: String, c: Dictionary, next: Dictionary = {}, tick := 12) -> void:
	var policy = load(POLICY).new(); policy.configure(metadata(id))
	var presenter = load("res://scripts/core/presentation/"+id+"_presenter.gd").new()
	root.add_child(presenter)
	policy.sample(c,0); presenter.present(c,0)
	if next.is_empty(): next = c
	var pose: Dictionary = policy.sample(next,tick); presenter.present(next,tick)
	check(pose.get("ok",false),id+" accepted "+str(next))
	check(pose.get("clip","") == presenter.animation_player.assigned_animation,"oracle clip "+id)
	check(is_equal_approx(pose.get("source_seconds",-1),presenter.animation_player.current_animation_position),"oracle source time "+id+" "+str(pose))
	presenter.free()
func run() -> void:
	for id in ["teknium","turbofit"]:
		for facing in [-1.0,1.0]:
			for loco in ["idle","walk","run","initial_dash","turn","brake","jump_startup","rising","falling","fast_fall","landing"]:
				var c := context(); c.locomotion = loco; c.facing = facing; c.velocity = Vector3(4,0,0)
				compare(id,c)
			var hit := context(); hit.status = "hitstun"; hit.hit_id = "hit1"; hit.facing = facing
			compare(id,hit)
			var block := context(); block.action = "block"; compare(id,block)
	for move in ["SIDE STRIKE","AIR STRIKE","UPPERCUT","UP AIR","LOW SWEEP","DOWN STRIKE"]:
		var c := context(); c.strike_id = "strike"; c.strike_move = move; c.strike_elapsed = 0.0
		var n := c.duplicate(true); n.strike_elapsed = .2
		compare("teknium",c,n)
	var r := context(); r.recovery_id = "recovery"; r.recovery_elapsed = .24; compare("teknium",r)
	var f := context(); f.force_id = "force"; f.force_source_time = .7; compare("teknium",f)
	for clip in ["GoalkeeperKick","AirSideKick","AirDownKick","MeleeHorizontal","MeleeBackhand"]:
		var c := context(); c.presentation = {"activation_id":"basic","clip":clip,"elapsed":.2,"facing":-1.0,"duration":.8}
		compare("turbofit",c)
	for move in ["power_chord","sound_wave","sound_orb","rising_chord"]:
		for age in [0.0,.2,.3,.3333334,.34,1.6,9.1]:
			for phase in (["anticipation","release"] if move == "power_chord" else ["active","recovery"]):
				var c := context(); c.presentation = {"activation_id":"special","move":move,"phase":phase,"age":age,"facing":-1.0}
				compare("turbofit",c)
	if not failures: print("PASS: committed policy imported presenter source-time oracles")
	quit(1 if failures else 0)
