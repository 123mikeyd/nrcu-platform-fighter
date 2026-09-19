extends "res://tests/test_core_match_strikes.gd"
const DefenseProfile = preload("res://scripts/core/combat/defense_profile.gd")
func shield(pressed := false, axis := Vector2.ZERO):
	var f = Frame.new(); f.held.shield = true; f.pressed.shield = pressed; f.axis = axis
	return f
func floor_body():
	var body = StaticBody3D.new()
	var shape = CollisionShape3D.new(); var box = BoxShape3D.new(); box.size = Vector3(40, 1, 6)
	shape.shape = box; body.add_child(shape); body.position.y = -0.5; root.add_child(body)
	return body
func setup_match(profile = null):
	var m = load("res://scripts/core/match/match_simulation.gd").new()
	var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	a.reset_at(Vector3(0, 0.01, 0)); b.reset_at(Vector3(1.5, 0.01, 0))
	m.register_actor(1, a); m.register_actor(2, b)
	if profile != null and m.has_method("configure_defense"): m.configure_defense(profile)
	return m
func settle(m):
	for i in 12: await tick(m)
func cleanup(m):
	for f in m.fighters.values(): f.actor.free()
func run() -> void:
	var floor = floor_body(); var p = DefenseProfile.new(); p.shield_drain = 0
	var m = setup_match(p)
	check(m.has_method("configure_defense"), "finite defense opt-in exists")
	if not m.has_method("configure_defense"): cleanup(m); floor.free(); quit(1); return
	await settle(m)
	await tick(m, {1: frame(true, 1), 2: shield(true)})
	check(m.fighters[2].percent == 0, "real grounded shield blocks real strike")
	check(m.defense_telemetry(2).shield_health < 100, "blocked strike spends shield")
	check(m.defense_telemetry(1).shield_health == 100, "per fighter resources isolated")
	p.shield_max = 1
	check(m.fighters[2].defense.profile.shield_max == 100, "source tuning copied")
	m.fighters[1].defense.profile.shield_max = 2
	check(m.fighters[2].defense.profile.shield_max == 100, "sibling tuning copied")
	await tick(m)
	check(m.defense_telemetry(2).state == "idle", "release drops shield without extra binding")
	cleanup(m); floor.free()
	if not failures: print("PASS: core defense match (%d checks)" % checks)
	quit(1 if failures else 0)
