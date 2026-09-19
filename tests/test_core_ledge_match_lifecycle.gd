extends "res://tests/test_core_ledge_match.gd"
func run() -> void:
	var terrain = body(Vector3(2,-0.5,0),Vector3(4,1,4))
	var m = setup_ledge()
	var rules = load("res://scripts/core/match/match_rules.gd").new(); rules.respawn_hitstun_ticks = 0
	m.configure_rules(rules); m.rematch()
	m.fighters[1].actor.position = Vector3(-1,-1,0)
	await tick(m,{1:frame(false,1)})
	check(m.ledge_telemetry(1).get("benefit_used",false), "first life used benefit")
	# Force a blast without treating it as a voluntary ledge drop.
	m.fighters[1].actor.position.x = 100
	m.set_frozen(1,true)
	await tick(m)
	check(m.fighters[1].stocks == 2 and m.ledge_telemetry(1).anchor_id == "" and not m.ledge_telemetry(1).get("benefit_used",false), "KO erases excursion state and releases occupancy")
	m.fighters[1].actor.position = Vector3(-1,-1,0); m.fighters[1].actor.runtime.velocity = Vector3(1,-1,0)
	await tick(m,{1:frame(false,1)})
	check(m.ledge_telemetry(1).protected, "new life can earn benefit without old regrab cooldown")
	m.rematch()
	check(m.ledge_state.is_empty(), "rematch clears all occupancy and local clocks")
	cleanup(m)
	m = setup_ledge(); rules.stock_count = 1; m.configure_rules(rules); m.rematch()
	m.fighters[1].actor.position = Vector3(-1,-1,0)
	await tick(m,{1:frame(false,1)})
	m.fighters[2].actor.position.x = 100
	await tick(m)
	check(not m.result.is_empty() and m.ledge_state.is_empty() and m.ledge_events.is_empty(), "results clear ledge state and stale proposals")
	await tick(m,{1:frame(false,1)})
	check(m.ledge_state.is_empty() and m.ledge_events.is_empty(), "result frames do not replay ledge proposals")
	cleanup(m); terrain.free()
	# The real authored stage resource (not blast edges) integrates both sides.
	var stage = load("res://scripts/core/stage/combat_lab_stage.gd").new()
	var g = stage.geometry()[0]; terrain = body(g.position,g.size)
	for side in [-1,1]:
		m = setup_ledge(); var anchors = stage.create_anchors(); var p = LedgePolicy.new()
		m.configure_ledges(anchors,p)
		anchors[0].edge.x = 100; p.max_hang_ticks = 1
		m.fighters[1].actor.position = Vector3(side*13,-1,0)
		await tick(m,{1:frame(false,-side)})
		check(m.ledge_telemetry(1).anchor_id == ("combat_lab.main.left" if side == -1 else "combat_lab.main.right"), "actual stage anchor catches on mirrored side")
		await tick(m)
		check(m.ledge_telemetry(1).anchor_id != "", "installed anchors and tuning are deep copied")
		var up = Frame.new(); up.axis.y = -1
		await tick(m,{1:up})
		check(m.fighters[1].actor.position.is_equal_approx(Vector3(side*11.3,0.06,0)), "actual main collider supports full elbow climb")
		cleanup(m)
	terrain.free()
	if not failures: print("PASS: core ledge match lifecycle (%d checks)" % checks)
	quit(1 if failures else 0)
