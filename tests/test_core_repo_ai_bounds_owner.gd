extends "res://tests/test_core_top_support_lifecycle.gd"
const Owner = preload("res://scripts/core/input/repo_ai_match_input.gd")

func run():
	for kit in ["teknium","turbofit"]:
		var f = setup_pair("teknium",kit,false,"grounded_jostle")
		for side in [-1,1]:
			for bounds in [{"left":NAN,"right":NAN,"top":NAN},{"left":-INF,"right":INF,"top":0.0},{"left":12.0,"right":-12.0,"top":0.0},{"left":9.0,"right":9.0,"top":0.0},{"left":false,"right":"27","top":4},{"left":3,"right":27},{"top":4}]:
				f.m.reset({1:Vector3.ZERO,2:Vector3(side*9,0,0)})
				f.m.fighters[1].enabled = false
				var owner = Owner.new(); owner.stage_bounds = bounds.duplicate(true)
				var original = var_to_bytes(owner.stage_bounds)
				var obs = owner._observation(f.m,2)
				obs.stage_bounds.left = 500
				check(var_to_bytes(owner.stage_bounds) == original,"invalid observation still detached")
				var frame = owner.sample_all(f.m)[2]
				check(frame.axis.x == -side and frame.held.jump and frame.pressed.jump,"owner invalid bounds emit fallback recovery "+kit+str(side))
				var timer = owner.ai.timer; var sequence = owner.ai.sequence
				frame.axis.x = 0; frame.held.jump = false
				check(owner.sample_all(f.m)[2].held.jump,"owner invalid cached frame is detached")
				check(owner.ai.timer == timer and owner.ai.sequence == sequence,"owner duplicate does not advance state")
				check(var_to_bytes(owner.stage_bounds) == original,"owner supplied invalid data preserved")
		dispose(f)
	if not failures: print("PASS: repo AI owner invalid bounds recover both kits both edges without state or copy regressions")
	quit(1 if failures else 0)
