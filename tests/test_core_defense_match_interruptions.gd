extends "res://tests/test_core_defense_match.gd"
func run() -> void:
	var floor = floor_body()
	for reason in ["freeze","disable"]:
		for action in ["attack","jump"]:
			var m = setup_match(DefenseProfile.new()); await settle(m)
			await tick(m,{2:shield(true)})
			if reason == "freeze": m.set_frozen(2,true)
			else: m.set_enabled(2,false)
			await tick(m)
			if reason == "freeze": m.set_frozen(2,false)
			else: m.set_enabled(2,true)
			var f = Frame.new(); f.pressed[action] = true; f.held[action] = true
			await tick(m,{2:f})
			check(not m.fighters[2].move_id.is_empty() if action == "attack" else m.fighters[2].actor.runtime.states.locomotion == "jump_startup", "first legal " + action + " after shield " + reason)
			check(m.fighters[2].buffer.peek(action).is_empty(), "legal command consumed without artificial lock tick")
			cleanup(m)
	floor.free()
	if not failures: print("PASS: core defense match interruption (%d checks)" % checks)
	quit(1 if failures else 0)
