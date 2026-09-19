extends "res://tests/test_core_repo_ai.gd"
const AI = preload("res://scripts/core/input/repo_ai_input_source.gd")

func observation(kit: String, position: Vector3) -> Dictionary:
	return {"id":2,"position":position,"velocity":Vector3.ZERO,"character_id":kit,"enabled":true,"team":-1,"attack_cooldown":0.0,"can_jump":true,"recovery_spent":false,"magic_locked":false,"magic_cooldown":0.0}

func invalid_cases() -> Array:
	# Exact AI-STAGE-001 review inputs plus individual malformed coordinates.
	var cases: Array = [
		{"name":"nan","bounds":{"left":NAN,"right":NAN,"top":NAN}},
		{"name":"infinite","bounds":{"left":-INF,"right":INF,"top":0.0}},
		{"name":"reversed","bounds":{"left":12.0,"right":-12.0,"top":0.0}},
		{"name":"zero_width","bounds":{"left":9.0,"right":9.0,"top":0.0}},
		{"name":"all_wrong_types","bounds":{"left":false,"right":"27","top":[]}},
		{"name":"unexpected_only","bounds":{"center":15}},
	]
	for value in [null, false, true, "3", [], Vector3.ZERO, INF, -INF, NAN]:
		cases.append({"name":"container_"+str(value),"bounds":value})
	for key in ["left","right","top"]:
		for value in [null, false, true, "3", [], {}, Vector3.ZERO, INF, -INF, NAN]:
			var bounds = {"left":3.0,"right":27.0,"top":4.0}
			bounds[key] = value
			cases.append({"name":key+"_"+str(value),"bounds":bounds})
		var partial = {"left":3.0,"right":27.0,"top":4.0}
		partial.erase(key)
		cases.append({"name":"missing_"+key,"bounds":partial})
		cases.append({"name":"only_"+key,"bounds":{key:partial.values()[0]}})
	return cases

func run():
	var cases = invalid_cases()
	for kit in ["teknium","turbofit"]:
		# x=9,y=0 is the exact review probe; opposite edge and interior
		# distinguish reversed/partial intervals that accidentally match it.
		for position in [Vector3(9,0,0),Vector3(-9,0,0),Vector3(4,0,0),Vector3(0,-0.6,0)]:
			for row in cases:
				var obs = observation(kit,position)
				var baseline = AI.new()
				var actual = AI.new()
				obs.stage_bounds = row.bounds
				var before = var_to_bytes(obs)
				for tick in 30:
					var expected = baseline.sample(tick,observation(kit,position),[]).to_dict()
					var frame = actual.sample(tick,obs,[])
					check(frame.to_dict() == expected,"atomic fallback frame/edges "+kit+str(position)+row.name+" tick="+str(tick))
					check(actual.timer == baseline.timer and actual.sequence == baseline.sequence and actual.intent == baseline.intent,"fallback preserves timer/sequence/intent "+row.name)
					frame.axis = Vector2(99,99); frame.held.jump = false
					check(actual.sample(tick,obs,[]).to_dict() == expected,"duplicate cached copy "+row.name)
				check(var_to_bytes(obs) == before,"fallback never mutates supplied data "+row.name)
	print("BOUNDS_INVALID_CASES ",cases.size())
	if not failures: print("PASS: repo AI malformed bounds atomically preserve default frames clocks edges and copies")
	quit(1 if failures else 0)
