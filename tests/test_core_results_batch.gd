extends "res://tests/test_core_grab_slice.gd"
func run():
	for order in [[1, 2], [2, 1]]:
		var m = Match.new(); var actors = {}
		for id in order:
			var actor = Actor.new(); root.add_child(actor); actors[id] = actor; m.register_actor(id, actor)
		var rules = load("res://scripts/core/match/match_rules.gd").new(); rules.stock_count = 1
		m.configure_rules(rules); m.rematch()
		actors[1].reset_at(Vector3(17, 3, 0)); actors[2].reset_at(Vector3(18, 3, 0))
		var right = Frame.new(); right.axis.x = 1; right.pressed.attack = true
		var left = Frame.new(); left.axis.x = -1; left.pressed.attack = true
		await step(m, {1: right, 2: left})
		check(m.events.size() == 2, "outgoing mutual contact survives blast batch")
		check(m.result.kind == "DRAW" and m.result.winner_id == 0, "same tick final-stock DRAW independent order")
		var seen = {}; var kos = 0; var results = 0
		for e in m.lifecycle_events:
			check(not seen.has(e.event_id), "unique lifecycle identity"); seen[e.event_id] = true
			if e.kind == "ko": kos += 1
			if e.kind == "result": results += 1
		check(kos == 2 and results == 1, "two KOs one result")
		m.set_enabled(1, true)
		check(not m.fighters[1].enabled, "enabled toggle cannot resurrect eliminated")
		actors[1].position.y = -100
		await step(m)
		check(m.fighters[1].stocks == 0 and m.lifecycle_events.is_empty(), "repeated outside is idempotent")
		for a in actors.values(): a.free()
	if not failures: print("PASS: result batch (%d checks)" % checks)
	quit(1 if failures else 0)
