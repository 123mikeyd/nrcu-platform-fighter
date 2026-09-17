extends "res://tests/test_core_turbo_match_routes.gd"
func shield():
	var f = Frame.new(); f.held.shield = true; return f
func run():
	var floor = floor_body(); var m = Match.new()
	var a = Actor.new(); var b = Actor.new(); var c = Actor.new()
	root.add_child(a); root.add_child(b); root.add_child(c)
	m.register_actor(1,a); m.register_actor(2,b,-1,"turbofit"); m.register_actor(3,c)
	var p = load("res://scripts/core/combat/defense_profile.gd").new(); p.shield_max = 10; p.shield_drain = 0; p.shield_regen = 0
	m.configure_defense(p)
	m.reset({1:Vector3(-10,.01,0),2:Vector3(-4,.01,0),3:Vector3(10,.01,0)})
	for i in 12: await step(m)
	await step(m,{2:press(Vector2.RIGHT),3:shield()})
	var shot: Dictionary = m.projectile_telemetry()[0]
	c.position.x = shot.position.x + .85; a.position.x = c.position.x + 1.3
	await step(m,{1:press(Vector2.LEFT,"attack"),3:shield()})
	check(m.defense_telemetry(3).state == "break", "finite shield breaks on snapshotted contacts")
	check(m.fighters[3].percent == 0, "wave utility cannot break shield before earlier ordered direct contact")
	check(m.projectile_telemetry().is_empty(), "captured shield absorption remains consumed even after ordered break")
	a.free(); b.free(); c.free(); floor.free()
	if not failures: print("PASS: turbo match snapshot defense (%d checks)" % checks)
	quit(1 if failures else 0)
