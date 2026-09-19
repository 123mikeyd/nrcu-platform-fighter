extends "res://tests/test_core_ledge_match.gd"
func run():
	var floor_body = body(Vector3(0,-0.5,0),Vector3(40,1,4))
	var m = load("res://scripts/core/match/match_simulation.gd").new()
	for id in [1,2,3]:
		var a = Actor.new(); a.profile = load("res://data/characters/teknium_movement.tres")
		root.add_child(a); m.register_actor(id,a,1)
	m.reset({1:Vector3.ZERO,2:Vector3(0,2,0),3:Vector3(0,4,0)})
	for i in 230: await tick(m)
	for f in m.fighters.values(): check(f.actor.runtime.grounded and f.actor.position.y < 0.03,"three-body tower disperses")
	m.reset({1:Vector3(-3,0.01,0),2:Vector3.ZERO,3:Vector3(10,0,0)})
	var mixed := false
	for i in 100:
		await tick(m,{1:frame(false,1)})
		var a = m.fighters[1].actor
		for j in a.get_slide_collision_count():
			var c = a.get_slide_collision(j)
			for k in c.get_collision_count():
				if c.get_collider(k) == m.fighters[2].actor: mixed = mixed or a.runtime.grounded
	check(mixed,"real floor remains support alongside side contact")
	var wall = body(Vector3(0.95,3,0),Vector3(0.02,6,4))
	m.reset({1:Vector3(0,3.5,0),2:Vector3.ZERO,3:Vector3(10,0,0)})
	for i in 180:
		await tick(m)
		check(m.fighters[1].actor.position.x < 0.55,"thin wall never tunnels")
	check(m.fighters[1].actor.runtime.grounded and m.fighters[1].actor.position.x < -0.78,"thin wall reverses escape")
	wall.free()
	m.reset({1:Vector3(-2,0,0),2:Vector3.ZERO,3:Vector3(10,0,0)})
	for i in 15: await tick(m)
	m.fighters[2].hitstop_left = 45
	var at: Vector3 = m.fighters[2].actor.position
	var t: int = m.fighters[2].actor.runtime.tick
	for i in 45:
		await tick(m,{1:frame(false,1)})
		check(m.fighters[2].actor.position == at and m.fighters[2].actor.runtime.tick == t,"live opponent never displaces stopped actor")
	check(m.fighters[1].actor.position.x < -0.78,"stopped actor remains blocking")
	cleanup(m); floor_body.free()
	if not failures: print("PASS body guards (%d checks)" % checks)
	quit(1 if failures else 0)
