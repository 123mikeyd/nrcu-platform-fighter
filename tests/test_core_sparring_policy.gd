extends "res://tests/test_core_ai_comparison_lab_ticks.gd"
func own() -> Dictionary:
	return {"id":2,"position":Vector3.ZERO,"velocity":Vector3.ZERO,"team":-1,"enabled":true,"character_id":"turbofit","can_jump":true,"recovery_spent":false,"magic_locked":false,"magic_cooldown":0.0,"attack_cooldown":0.0,"facing":1.0,"stage_bounds":{"left":-12.0,"right":12.0,"top":0.0}}
func run():
	var path := "res://scripts/core/input/sparring_input_source.gd"
	check(FileAccess.file_exists(path),"separate explicitly attributed sparring policy exists")
	if failures: quit(1); return
	var ai = load(path).new()
	var f = own(); var target = own(); target.id = 1; target.position = Vector3(1.6,0,0)
	var edges := []; var neutral := 0; var last_decision := -1; var seq := 0
	for tick in 1200:
		var frame = ai.sample(tick,f,[target])
		if ai.sequence != seq:
			if last_decision >= 0: check(tick-last_decision>=36,"decision cadence slower than repo Easy 26-tick cadence")
			last_decision=tick; seq=ai.sequence
		check(frame.source_id == "sparring_easy","distinct source attribution")
		if tick < 24: check(frame.axis == Vector2.ZERO and frame.pressed.is_empty(),"24 committed tick initial reaction delay")
		if frame.pressed.get("attack",false): edges.append(tick)
		if frame.axis == Vector2.ZERO and not frame.held.values().has(true): neutral += 1
	check(not edges.is_empty(),"not a training dummy: attempts basics")
	for i in range(1,edges.size()): check(edges[i]-edges[i-1]>=120,"no attack retry or sequence bypass within 120 committed ticks")
	check(neutral>=600,"intentional input-neutral breathing at least half close fixture")
	print("POLICY ",JSON.stringify({"basic_ticks":edges,"neutral_ticks":neutral}))
	if not failures: print("PASS: separate sparring delayed bounded pressure")
	quit(1 if failures else 0)
