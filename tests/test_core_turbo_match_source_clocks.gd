extends "res://tests/test_core_turbo_match_routes.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b,-1,"turbofit")
	for aim in [Vector2.RIGHT,Vector2.DOWN,Vector2.UP]:
		m.reset({1:Vector3(-8,20,0),2:Vector3(8,20,0)})
		await step(m,{1:press(aim)})
		var expected: float = .55 if aim == Vector2.RIGHT else (.75 if aim == Vector2.DOWN else .65)
		check(is_equal_approx(m.kit_telemetry(1).special.cooldown,expected), "acceptance retains source cooldown "+str(aim))
	m.reset({1:Vector3(-8,20,0),2:Vector3(8,20,0)})
	var input = press(Vector2.ZERO); input.held.special = true
	await step(m,{1:input})
	check(m.kit_telemetry(1).special.age == 0, "charge acceptance is entry, not a prior held interval")
	# A blocked shield command may not turn a charging actor into a shield absorber.
	m.reset({1:Vector3(0,20,0),2:Vector3(3,20,0)})
	await step(m,{1:press(Vector2.RIGHT),2:input})
	var both = Frame.new(); both.held.special = true; both.held.shield = true
	for i in 20: await step(m,{2:both})
	check(m.fighters[2].percent == 11, "kit action lock rejects legacy shield during charge")
	m.reset({1:Vector3(0,20,0),2:Vector3(8,20,0)})
	await step(m,{1:press(Vector2.RIGHT),2:input})
	var shot: Dictionary = m.projectile_telemetry()[0]
	b.position = shot.position + Vector3(.85,-1,0)
	m.fighters[2].hitstop_left = 3
	await step(m,{2:both})
	check(m.fighters[2].percent == 11, "stopped charge cannot accept a new legacy shield against world projectile")
	m.reset({1:Vector3(3,20,0),2:Vector3(0,20,0)})
	await step(m,{1:press(Vector2.RIGHT)})
	for i in 31: await step(m)
	await step(m,{2:press(Vector2.RIGHT)})
	var incoming: Dictionary = m.projectile_telemetry()[-1]
	a.position = incoming.position + Vector3(.85,-1,0)
	var block = Frame.new(); block.held.shield = true
	await step(m,{1:block})
	check(m.fighters[1].percent == 0 and m.fighters[1].shield_command, "shield eligibility and world snapshot agree at local cooldown expiry")
	m.reset({1:Vector3(0,20,0),2:Vector3(3,20,0)})
	m.set_frozen(2,true)
	await step(m,{1:press(Vector2.RIGHT),2:block})
	for i in 20: await step(m,{2:block})
	check(m.fighters[2].percent == 11, "frozen effective status rejects legacy shield intent")
	a.free(); b.free()
	if not failures: print("PASS: turbo match source clocks (%d checks)" % checks)
	quit(1 if failures else 0)
