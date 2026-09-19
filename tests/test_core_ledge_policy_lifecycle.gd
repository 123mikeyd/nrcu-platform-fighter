extends "res://tests/test_core_ledge_policy.gd"
func run():
	var p = load("res://scripts/core/stage/ledge_policy.gd").new()
	var a = load("res://scripts/core/stage/ledge_anchor.gd").new(); a.anchor_id = "edge"
	var clear = func(_points): return true
	for side in [-1, 1]:
		a.outward = side
		for sample in [
			[Vector3(side, -1, 0), Vector3(-side, -1, 0), true],
			[Vector3(side, -1, 0), Vector3(-side, 0, 0), true],
			[Vector3(side, -1, 0), Vector3(side, -1, 0), false],
			[Vector3(side, -1, 0), Vector3(-side, 1, 0), false],
			[Vector3(-side, -1, 0), Vector3(-side, -1, 0), false],
			[Vector3(side, 0.1, 0), Vector3(-side, -1, 0), false],
			[Vector3(side, -3, 0), Vector3(-side, -1, 0), false],
			[Vector3(side, -1, 1), Vector3(-side, -1, 0), false]]:
			check(a.eligible(actor(sample[0], sample[1])) == sample[2], "side/approach/height/fall eligibility")
	a.outward = -1
	var actors = {9: actor(Vector3(-1,-1,0), Vector3(1,-1,0)), 2: actor(Vector3(-1,-1,0), Vector3(1,-1,0))}
	var r = p.advance({}, actors, [a], 0, clear)
	check(r.proposals.has(2) and not r.proposals.has(9), "contest lower stable ID wins regardless insertion")
	actors.erase(9)
	actors[2].position = a.hang()
	var held = p.advance(r.state, actors, [a], 1, clear)
	check(held.proposals.get(2, {}).get("transition") == "hang", "held ledge produces hang proposal")
	if not held.proposals.has(2): finish(); return
	check(not held.proposals[2].restore_recovery, "hang never farms resources")
	for reason in ["hit", "frozen", "ko", "reset", "caught", "disabled"]:
		var interrupted = actors.duplicate(true); interrupted[2].status = reason
		var released = p.advance(r.state, interrupted, [a], 1, clear)
		check(released.state.actors[2].anchor_id == "", "interrupt releases: " + reason)
		check(not released.proposals[2].protected and not released.proposals[2].restore_recovery, "interrupt clears benefits")
	var absent = p.advance(r.state, {}, [a], 1, clear)
	check(absent.state.actors.is_empty(), "removed actor cannot retain occupancy")
	for intent in ["drop", "jump", "climb"]:
		actors[2].intent = intent
		var exit = p.advance(r.state, actors, [a], 1, clear)
		check(exit.proposals[2].transition == intent and exit.state.actors[2].anchor_id == "", "exit " + intent)
		check(not exit.proposals[2].protected, "exit ends protection")
	actors[2].intent = "drop"
	var drop = p.advance(r.state, actors, [a], 1, clear)
	actors[2].intent = ""; actors[2].position = Vector3(-1,-1,0)
	var locked = p.advance(drop.state, actors, [a], 2, clear)
	check(not locked.proposals.has(2), "drop regrab lock")
	var again = p.advance(drop.state, actors, [a], 100, clear)
	check(again.proposals[2].transition == "catch" and not again.proposals[2].restore_recovery and not again.proposals[2].protected, "later regrab grants neither protection nor recovery")
	actors[2].position = a.hang()
	var expired = p.advance(r.state, actors, [a], 30, clear)
	check(not expired.proposals[2].protected, "protection expires on exact boundary")
	var timed_out = p.advance(r.state, actors, [a], 600, clear)
	check(timed_out.proposals[2].transition == "timeout", "finite hang")
	var blocked = p.advance({}, actors, [a], 0, func(_points): return false)
	check(blocked.proposals.is_empty(), "blocked catch rejects")
	actors[2].intent = "climb"
	blocked = p.advance(r.state, actors, [a], 1, func(_points): return false)
	check(blocked.proposals[2].transition == "blocked", "blocked climb releases rather than teleport")
	var invalid = p.advance({}, actors, [a, a], 0, clear)
	check(invalid.proposals.is_empty(), "duplicate anchor IDs fail closed")
	actors[2].intent = ""; actors[2].position = Vector3(-1,-1,0)
	var ground = actors.duplicate(true); ground[2].grounded = true
	check(p.advance({}, ground, [a], 0, clear).proposals.is_empty(), "grounded actor cannot catch")
	var disabled = actors.duplicate(true); disabled[2].enabled = false
	check(p.advance(r.state, disabled, [a], 1, clear).proposals[2].transition == "disabled", "disabled release has explicit reason")
	check(p.advance(r.state, disabled, [a], 1, clear).state.actors[2].anchor_id == "", "enabled false releases")
	check(p.advance(r.state, actors, [], 1, clear).state.actors[2].anchor_id == "", "stage anchor removal releases")
	check(p.advance(r.state, actors, [a], 0, clear).proposals.is_empty(), "same tick cannot repeat resource event")
	check(p.advance(r.state, actors, [a], -1, clear).state == r.state, "rewound tick inert")
	var touch = actors.duplicate(true); touch[2].grounded = true
	var no_refund = p.advance(drop.state, touch, [a], 100, clear)
	check(no_refund.state.actors[2].benefit_used, "grounded flag alone cannot rearm benefits")
	touch[2].terrain_landed = true
	var landed = p.advance(drop.state, touch, [a], 100, clear)
	var fresh = p.advance(landed.state, actors, [a], 101, clear)
	check(fresh.proposals[2].restore_recovery and fresh.proposals[2].protected, "trusted terrain landing rearms one catch benefit")
	check(fresh.proposals[2].cancel_recovery, "catch cancels active recovery before reset event")
	check(not drop.proposals[2].restore_recovery, "drop never restores resource")
	check(p.advance({}, actors, [a], 0, clear).proposals[2].restore_recovery, "fresh rematch state restores eligibility")
	check(r.state.actors[2].anchor_id == "edge", "prior state remains immutable after all transitions")
	finish()
