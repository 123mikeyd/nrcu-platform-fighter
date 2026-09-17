extends "res://tests/test_core_recovery_acceptance.gd"
func floor_body():
	var body = StaticBody3D.new(); var shape = CollisionShape3D.new(); var box = BoxShape3D.new()
	box.size = Vector3(40,1,6); shape.shape = box; body.add_child(shape); body.position.y = -.5; root.add_child(body); return body
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b,-1,"turbofit")
	var floor = floor_body()
	for aim in [Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN,Vector2.UP]:
		m.reset({1:Vector3(0,.01,0),2:Vector3(1.5,.01,0)})
		for i in 12: await step(m)
		var clip: String = "MeleeBackhand" if aim == Vector2.UP else ("GoalkeeperKick" if aim == Vector2.DOWN else "MeleeHorizontal")
		await step(m,{1:press(aim,"attack")})
		check(m.kit_telemetry(1).basic.clip == clip, "ground route "+clip)
		for i in (26 if aim == Vector2.DOWN else 16):
			if aim == Vector2.UP: b.position = a.position + Vector3(0,1.5,0); b.runtime.velocity = Vector3.ZERO
			await step(m)
		check(m.fighters[2].percent == 14, "ground timed contact "+clip)
	m.reset({1:Vector3(0,.01,0),2:Vector3(10,.01,0)})
	for i in 12: await step(m)
	await step(m,{1:press(Vector2.RIGHT,"attack")})
	check(a.velocity.x > 0, "basic action cooldown does not immobilize shared movement")
	var before: float = m.kit_telemetry(1).basic.remaining
	m.cancel_action(1,"hit")
	await step(m,{1:press(Vector2.RIGHT,"attack")})
	check(not m.kit_telemetry(1).basic.active and m.kit_telemetry(1).action_locked, "interrupted basic retains cooldown without restarting buffered attack")
	check(before > .5, "test interrupted during windup")
	floor.free()
	for aim in [Vector2.ZERO,Vector2.LEFT,Vector2.DOWN,Vector2.UP]:
		m.reset({1:Vector3(0,30,0),2:Vector3(10,30,0)})
		await step(m,{1:press(aim,"attack")})
		var clip: String = "MeleeBackhand" if aim == Vector2.UP else ("AirDownKick" if aim == Vector2.DOWN else "AirSideKick")
		check(m.kit_telemetry(1).basic.clip == clip, "air route "+clip)
		var first: int = 17 if aim == Vector2.UP else (24 if aim == Vector2.DOWN else 10)
		for i in first - 2: await step(m)
		var facing: float = m.kit_telemetry(1).basic.facing
		var offset := Vector3(0,1.5,0)
		if aim != Vector2.UP:
			offset = load("res://scripts/core/kits/turbofit_contact_pose.gd").new().center(clip,float(first)/60.0,facing) - Vector3(0,.9,0)
		b.position = a.position + offset; b.runtime.velocity = a.runtime.velocity
		await step(m)
		check(m.fighters[2].percent == 14, "air capsule contact "+clip)
		if not m.events.is_empty(): check(m.events[0].base_knockback == 5.5, "all basics source knockback")
	a.free(); b.free()
	if not failures: print("PASS: turbo match routes (%d checks)" % checks)
	quit(1 if failures else 0)
