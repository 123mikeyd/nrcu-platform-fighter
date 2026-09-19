extends "res://tests/test_core_top_support_lifecycle.gd"
func run():
	for lower in ["teknium","turbofit"]:
		for face in [-1,1]:
			var f = setup_pair(lower,"turbofit" if lower == "teknium" else "teknium")
			f.m.reset({1:Vector3(-face*1.6,0,0),2:Vector3.ZERO})
			for i in 8: await step(f.m)
			check(f.a.runtime.grounded,"actual terrain ground-jump prerequisite")
			var source = Source.new(); var contacted = false; var ground_takeoff = false; var air_takeoff = false
			for i in 100:
				key(KEY_SPACE,i < 18 or i in range(24,42))
				var desired = clampf(-f.a.position.x*4,-7,7)
				key(KEY_D,desired-f.a.velocity.x>0.2); key(KEY_A,desired-f.a.velocity.x< -0.2)
				await step(f.m,{1:source.sample(f.m.tick)})
				ground_takeoff = ground_takeoff or f.a.runtime.states.locomotion == "jump_startup"
				air_takeoff = air_takeoff or f.a.runtime.air_jumps_left == 0
				if not f.m.top_support_telemetry(1).relation.is_empty(): contacted = true; break
			key(KEY_SPACE,false); key(KEY_A,false); key(KEY_D,false)
			check(ground_takeoff and air_takeoff and contacted,"parsed ground jump, steering, air jump, real top contact both approaches")
			check(not f.a.runtime.grounded and f.a.runtime.air_jumps_left == 0,"head does not refund accepted air jump")
			dispose(f)
	if not failures: print("PASS: parsed approach ground/air jumps onto generated head support")
	quit(1 if failures else 0)
