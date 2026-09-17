extends "res://tests/test_core_ledge_match.gd"
func run() -> void:
	var terrain = body(Vector3(2,-0.5,0),Vector3(4,1,4))
	var m = setup_ledge()
	var defense = load("res://scripts/core/combat/defense_profile.gd").new(); defense.air_startup_ticks = 1
	m.configure_defense(defense)
	var dodge = Frame.new(); dodge.held.shield = true; dodge.pressed.shield = true; dodge.axis.x = 1
	await tick(m,{1:dodge})
	await tick(m)
	check(m.defense_telemetry(1).state == "dodge_invulnerable" and m.ledge_telemetry(1).anchor_id == "", "dodge motion owner cannot also catch ledge")
	m.reset({1:Vector3(-1,-1,0),2:Vector3(8,3,0)})
	await tick(m,{1:frame(false,1)})
	check(m.ledge_telemetry(1).anchor_id == "left", "idle finite-defense actor catches normally")
	await tick(m,{1:dodge})
	check(m.defense_telemetry(1).state == "idle" and not m.fighters[1].buffer.peek("shield").is_empty(), "attached ledge rejects defense without consuming edge")
	cleanup(m); terrain.free()
	if not failures: print("PASS: core ledge match defense (%d checks)" % checks)
	quit(1 if failures else 0)
