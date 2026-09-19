extends "res://tests/test_core_repo_ai_bounds_validation.gd"

func run():
	for kit in ["teknium","turbofit"]:
		for bounds in [{},{"left":-8.0,"right":8.0,"top":0.0}]:
			for position in [Vector3(-9,0,0),Vector3(9,0,0),Vector3(0,-0.6,0)]:
				var obs = observation(kit,position); obs.stage_bounds = bounds
				check(AI.new().sample(0,obs,[]).to_dict() == AI.new().sample(0,observation(kit,position),[]).to_dict(),"empty/original positive control")
		for bounds in [{"left":3,"right":27,"top":4},{"left":3.0,"right":27.0,"top":4.0},{"left":3,"right":27.0,"top":4,"metadata":"ignored"}]:
			for position in [Vector3(2,4,0),Vector3(28,4,0),Vector3(15,3.49,0),Vector3(3,4,0),Vector3(27,4,0),Vector3(15,3.5,0),Vector3(15,4,0)]:
				var obs = observation(kit,position); obs.stage_bounds = bounds
				var before = var_to_bytes(obs)
				var ai = AI.new(); var frame = ai.sample(0,obs,[])
				var offstage = position.x < 3 or position.x > 27 or position.y < 3.5
				check(frame.axis.x == signf(15-position.x),"translated center 15 "+kit+str(position))
				check(frame.held.jump == offstage,"translated strict edges/top4 "+kit+str(position))
				var cached = frame.to_dict(); var timer = ai.timer; var sequence = ai.sequence
				obs.stage_bounds = {"left":NAN,"right":INF,"top":false}
				check(ai.sample(0,obs,[]).to_dict() == cached,"same tick changed geometry cannot replace cached frame")
				ai.sample(1,obs,[],false)
				check(ai.timer == timer and ai.sequence == sequence,"invalid observation cannot advance frozen clock")
				obs.stage_bounds = bounds
				check(var_to_bytes(obs) == before,"valid coordinates/metadata never rewritten")
	if not failures: print("PASS: repo AI original and translated bounds positive controls cached and frozen state")
	quit(1 if failures else 0)
