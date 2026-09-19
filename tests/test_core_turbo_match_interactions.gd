extends "res://tests/test_core_turbo_match_routes.gd"
func held(axis := Vector2.ZERO):
	var f = Frame.new(); f.axis = axis; f.held.special = true; return f
func shield_edge(axis := Vector2.ZERO):
	var f = Frame.new(); f.axis = axis; f.pressed.shield = true; f.held.shield = true; return f
func run():
	var floor = floor_body(); var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b)
	m.reset({1:Vector3(0,.01,0),2:Vector3(1.5,.01,0)})
	for i in 12: await step(m)
	var defense = load("res://scripts/core/combat/defense_profile.gd").new()
	defense.ground_dodge_speed = 0; defense.shield_drain = 0
	m.configure_defense(defense)
	await step(m,{1:press(Vector2.RIGHT,"attack")})
	for i in 12: await step(m)
	await step(m,{2:shield_edge(Vector2.RIGHT)})
	for i in 3: await step(m)
	check(m.defense_telemetry(2).state == "dodge_invulnerable", "real finite dodge active on timed contact")
	check(m.events.size() == 1 and m.fighters[2].percent == 0, "dodge consumes delayed Turbofit basic")
	for i in 15: await step(m)
	check(m.fighters[2].percent == 0, "consumed contact cannot hit after dodge expires")
	# Actual support cancels aerial foot episodes before post-move collection.
	for aim in [Vector2.ZERO,Vector2.DOWN]:
		m.reset({1:Vector3(0,.6,0),2:Vector3(1,.01,0)})
		a.runtime.velocity.y = -20
		await step(m,{1:press(aim,"attack")})
		for i in 5: await step(m)
		check(a.runtime.grounded and not m.kit_telemetry(1).basic.active, "landing cancels air kick and lock")
		check(m.fighters[2].percent == 0, "landing does not emit stale foot contact")
	# Detached waves advance while their source's local clock is stopped.
	m.reset({1:Vector3(-8,.01,0),2:Vector3(8,.01,0)})
	for i in 12: await step(m)
	await step(m,{1:press(Vector2.RIGHT)})
	var shot: Dictionary = m.projectile_telemetry()[0]
	m.fighters[1].hitstop_left = 5
	var clock: int = a.runtime.tick
	for i in 5: await step(m)
	check(a.runtime.tick == clock and m.projectile_telemetry()[0].age > shot.age, "wave world clock independent of actor hitstop")
	for i in 55: await step(m)
	check(m.projectile_telemetry().is_empty(), "world wave expires without presenter")
	# Buffered edge survives hitstop; acceptance uses remaining local cooldown.
	m.reset({1:Vector3(-8,.01,0),2:Vector3(8,.01,0)})
	for i in 12: await step(m)
	await step(m,{1:press(Vector2.RIGHT)})
	for i in 30: await step(m)
	m.fighters[1].hitstop_left = 4
	await step(m,{1:press(Vector2.UP,"attack")})
	for i in 3: await step(m)
	check(not m.fighters[1].buffer.peek("attack").is_empty(), "action edge retained during hitstop")
	for i in 3: await step(m)
	check(m.kit_telemetry(1).basic.clip == "MeleeBackhand", "buffer accepts only when local special cooldown ends")
	# Runtime kit change does not inherit a different factory's cooldown.
	m.configure_actor_kit(1,"teknium"); m.reset({1:Vector3(-8,.01,0),2:Vector3(8,.01,0)})
	for i in 12: await step(m)
	await step(m,{1:press(Vector2.RIGHT)})
	m.configure_actor_kit(1,"turbofit"); m.configure_actor_kit(1,"teknium")
	await step(m,{1:press(Vector2.RIGHT,"attack")})
	check(m.fighters[1].move_id == "SIDE STRIKE", "new factory selection clears stale outgoing attack cooldown")
	a.free(); b.free(); floor.free()
	if not failures: print("PASS: turbo match interactions (%d checks)" % checks)
	quit(1 if failures else 0)
