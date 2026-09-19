extends "res://tests/test_core_defense_match.gd"
func run() -> void:
	var floor = floor_body(); var m = setup_match(DefenseProfile.new()); await settle(m)
	await tick(m, {2: shield(true)})
	await tick(m, {2: frame(true, -1)})
	check(m.fighters[2].move_id == "SIDE STRIKE", "shield release opens actions on same eligible tick")
	m.reset({1:Vector3(0, 6, 0),2:Vector3(1.5,6,0)})
	m.fighters[2].defense.shield_health = 0; m.fighters[2].defense.state = "break"; m.fighters[2].defense.remaining = 50
	var rules = load("res://scripts/core/match/match_rules.gd").new(); rules.stock_count = 1
	m.configure_rules(rules)
	m.rematch()
	m.fighters[2].defense.state = "break"; m.fighters[2].defense.remaining = 50
	m.fighters[1].actor.position.x = 100
	await tick(m)
	check(not m.result.is_empty() and m.defense_telemetry(2).state == "idle", "results clean surviving defense episode including break")
	var snapshot = m.defense_telemetry(2)
	await tick(m, {2: shield(true,Vector2.LEFT)})
	check(m.defense_telemetry(2) == snapshot, "results never advance or queue defense")
	m.rematch()
	check(m.defense_telemetry(2).shield_health == 100 and m.defense_telemetry(2).air_charges == 1, "rematch fully resets per-life defense")
	cleanup(m); floor.free()
	if not failures: print("PASS: core defense match lifecycle (%d checks)" % checks)
	quit(1 if failures else 0)
