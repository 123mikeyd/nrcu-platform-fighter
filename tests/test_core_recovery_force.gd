extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var actors := []
	for id in [1, 2, 3]:
		var actor = Actor.new(); root.add_child(actor); actors.append(actor); m.register_actor(id, actor)
	m.reset({1: Vector3(20, 40, 0), 2: Vector3(0, 40, 0), 3: Vector3(40, 40, 0)})
	await step(m, {2: press(Vector2.RIGHT)})
	for i in 18: await step(m)
	check(m.projectiles.size() == 1, "real force shot emitted and in flight")
	if m.projectiles.size() == 1:
		var shot: Dictionary = m.projectiles[0]
		actors[0].position = Vector3(shot.position.x + 0.15, shot.position.y - 0.7, 0)
		actors[2].position = actors[0].position + Vector3(0.5, 1, 0)
		await step(m, {1: press()})
		check(m.fighters[1].percent == 8 and m.fighters[1].recovery == null, "actual swept force shot interrupts recovery")
		check(m.fighters[3].percent == 12, "recovery contact survives same-tick incoming projectile")
		check(m.events.size() == 2 and m.projectiles.is_empty(), "both contact types resolve once; force consumes on impact")
		check(actors[0].runtime.recovery_spent and not actors[0].runtime.recovery_motion, "force hit ends recovery motion without refund")
	# Recovery can interrupt force anticipation without altering its shared cooldown.
	m.reset({1: Vector3(20, 40, 0), 2: Vector3(0, 40, 0), 3: Vector3(40, 40, 0)})
	await step(m, {2: press(Vector2.RIGHT)})
	actors[0].position = actors[1].position + Vector3(0.5, 0, 0)
	await step(m, {1: press()})
	check(m.fighters[2].percent == 12 and m.fighters[2].force == null, "recovery interrupts force anticipation")
	check(m.fighters[2].ready_tick == 75, "force cooldown preserved by recovery hit")
	for i in 15: await step(m)
	check(m.projectiles.is_empty(), "interrupted force cannot emit")
	# An emitted shot remains alive when recovery hits the caster.
	m.reset({1: Vector3(20, 40, 0), 2: Vector3(0, 40, 0), 3: Vector3(40, 40, 0)})
	await step(m, {2: press(Vector2.RIGHT)})
	for i in 14: await step(m)
	actors[0].position = actors[1].position + Vector3(-0.5, 0, 0)
	await step(m, {1: press()})
	check(m.fighters[2].percent == 12 and m.fighters[2].force == null, "recovery interrupts post-emission force phase")
	check(m.projectiles.size() == 1, "caster interruption retains already emitted projectile")
	for actor in actors: actor.free()
	if not failures: print("PASS: recovery force interplay (%d checks)" % checks)
	quit(1 if failures else 0)
