extends "res://tests/test_core_sparring_policy.gd"
func run():
	var AI = load("res://scripts/core/input/sparring_input_source.gd")
	var delays := []; var intervals := []
	for offset in 36:
		var ai = AI.new(); var f = own(); var t = own(); t.id=1; t.position=Vector3(6,0,0)
		var changed_at: int = 72+offset; var first := -1
		# Include the deliberate 132..179 phase pause, not just next decision.
		for tick in 300:
			if tick == changed_at: t.position.x=-6
			var frame = ai.sample(tick,f,[t])
			if tick >= changed_at and frame.axis.x<0 and first<0: first=tick
		check(first>=changed_at+24,"all decision phases obey minimum perception delay")
		delays.append(first-changed_at)
	var ai = AI.new(); var f = own(); var t = own(); t.id=1
	var last := -1000
	for tick in 2400:
		t.position=Vector3(1.6 if tick%180<90 else 4.0,0,0)
		var frame = ai.sample(tick,f,[t])
		var shot: bool = frame.pressed.get("attack",false) or frame.pressed.get("special",false)
		if shot:
			check(tick-last>=120,"alternating distance cannot bypass shared offense interval")
			if last>=0: intervals.append(tick-last)
			last=tick
		check(not(frame.pressed.get("attack",false) and frame.pressed.get("special",false)),"no dual attack/basic sequence spam")
	for bad in [null,{},[],{"left":true,"right":12,"top":0},{"left":0,"right":0,"top":0},{"left":-12,"right":INF,"top":0},{"left":-12,"right":12,"top":NAN}]:
		check(ai._bounds(bad)=={"left":-8.0,"right":8.0,"top":0.0},"whole bounds fallback")
	var valid = {"left":10,"right":34,"top":5}
	check(ai._bounds(valid)==valid,"translated finite geometry supported")
	ai.reset(); t.position=Vector3(4,0,0)
	var frame = ai.sample(0,f,[t]); frame.pressed.attack=true
	check(not ai.sample(0,f,[t]).pressed.get("attack",false),"caller cannot mutate cached frame")
	check(not ai.configure("normal") and ai.difficulty=="easy","no hidden original difficulty tuning")
	var row = {"reaction_delays_ticks":delays,"offense_intervals_ticks":intervals}
	var file = FileAccess.open("res://.verification/core/sparring-ai/measured-contract.json",FileAccess.WRITE); file.store_string(JSON.stringify(row,"\t")); file.close()
	print("MEASURED ",JSON.stringify(row))
	if not failures: print("PASS: sparring reaction sweep shared offense budget and value safety")
	quit(1 if failures else 0)
