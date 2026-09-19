extends "res://tests/test_core_sparring_policy.gd"
func run():
	var AI = load("res://scripts/core/input/sparring_input_source.gd")
	var ai = AI.new(); var f = own(); var t = own(); t.id=1; t.position=Vector3(4,0,0)
	var specials := []
	for tick in 1200:
		var frame = ai.sample(tick,f,[t])
		if frame.pressed.get("special",false): specials.append(tick)
	check(not specials.is_empty(),"restrained but functional ranged special")
	for i in range(1,specials.size()): check(specials[i]-specials[i-1]>=360,"special separation at least six actor seconds")
	ai.reset(); f.position=Vector3(13,-1,0)
	var recovery := false
	for tick in 100:
		var frame = ai.sample(tick,f,[t]); recovery = recovery or frame.pressed.get("jump",false)
	check(recovery,"delayed bounded offstage return can jump")
	ai.reset(); f=own(); t.position=Vector3(1.6,0,0); t.attack_cooldown=0.5
	var shields := 0; var run_length := 0; var longest := 0
	for tick in 600:
		var frame = ai.sample(tick,f,[t])
		if frame.pressed.get("shield",false): shields += 1
		run_length = run_length+1 if frame.held.get("shield",false) else 0; longest=maxi(longest,run_length)
	check(shields>0 and shields<=3 and longest<=12,"occasional imperfect shield bounded to twelve ticks")
	ai.reset(); t.position=Vector3(4,0,0)
	for tick in 25: ai.sample(tick,f,[t])
	var before_age: int = ai.age
	for tick in range(25,85): ai.sample(tick,f,[t],false)
	check(ai.age==before_age,"hitstop freezes history and source clock")
	var cached = ai.sample(85,f,[t]).to_dict(); var age: int = ai.age
	check(ai.sample(85,f,[]).to_dict()==cached and ai.age==age,"same tick cached immutable frame")
	var restarted = ai.sample(0,f,[t])
	check(ai.age==1 and restarted.axis==Vector2.ZERO and restarted.pressed.is_empty(),"backward tick clears stale decisions")
	ai.reset(); var twin = AI.new()
	for tick in 180:
		var x = ai.sample(tick,f,[t]).to_dict(); var y = twin.sample(tick,f,[t]).to_dict()
		check(x==y,"deterministic observations")
		if tick==25: t.position=Vector3(-4,0,0)
		if tick>=26 and tick<49: check(x.axis[0]>=0,"changed position cannot be read before 24 advancing ticks")
	ai.reset(); f=own(); t.position=Vector3(1.6,0,0)
	for tick in 241: ai.sample(tick,f,[t])
	var stopped = ai.sample(241,f,[t],false)
	check(stopped.held.get("shield",false),"committed shield hold survives frozen source tick")
	ai.reset(); f.position=Vector3(11.5,0,0); t.position=Vector3(14,0,0)
	for tick in 80:
		var edge_frame = ai.sample(tick,f,[t])
		check(edge_frame.axis.x<=0,"do not chase toward unsafe observed platform edge")
	print("GUARDS ",JSON.stringify({"special_ticks":specials,"shield_episodes":shields,"longest_shield":longest}))
	if not failures: print("PASS: sparring specials defense recovery clocks determinism")
	quit(1 if failures else 0)
