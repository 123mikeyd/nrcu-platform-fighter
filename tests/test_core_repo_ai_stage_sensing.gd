extends "res://tests/test_core_repo_ai.gd"
const AI = preload("res://scripts/core/input/repo_ai_input_source.gd")
func run():
	for kit in ["teknium","turbofit"]:
		for side in [-1,1]:
			var ai = AI.new()
			var actor = {"id":2,"position":Vector3(side*8.45,0,0),"velocity":Vector3.ZERO,"character_id":kit,"enabled":true,"team":-1,"attack_cooldown":0.0,"can_jump":true,"recovery_spent":false,"magic_locked":true,"magic_cooldown":0.0,"stage_bounds":{"left":-12.0,"right":12.0,"top":0.0}}
			var target = actor.duplicate(true); target.id = 1; target.position.x = side*10.02
			var attacked := false; var outward := false
			for tick in 1200:
				var frame = ai.sample(tick,actor,[target])
				attacked = attacked or frame.held.attack
				outward = outward or frame.axis.x == side
			print("BOUNDARY ",kit," side=",side," decisions=",ai.sequence," attacked=",attacked," approached=",outward)
			check(attacked and outward,"grounded boundary remains combat, not phantom offstage "+kit+str(side))
	if not failures: print("PASS: repo AI explicit stage sensing")
	quit(1 if failures else 0)
