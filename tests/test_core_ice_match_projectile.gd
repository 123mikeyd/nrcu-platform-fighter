extends "res://tests/test_core_ice_match_shatter.gd"
func terrain(at: Vector3, size: Vector3):
	var body = StaticBody3D.new(); var shape = CollisionShape3D.new(); var box = BoxShape3D.new()
	box.size = size; shape.shape = box; body.add_child(shape); body.position = at; root.add_child(body); return body
func emit(m, at: Vector3, id: String = "shot"):
	m._commit_kit_intents([{"kind":"spawn_projectile","projectile_kind":"frost_bolt","source":1,"activation_id":id,"position":at,"facing":1.0}])
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"ice_mage"); m.register_actor(2,b,-1,"turbofit")
	m.reset({1:Vector3(-10,20,0),2:Vector3(10,20,0)})
	emit(m,Vector3(0,21,0))
	var shot = m.projectile_host.live[0]
	shot.remaining = .1; shot.age = 1.5
	b.reset_at(Vector3(.9,20,0)); a.position.x = -30
	await step(m,{2:press(Vector2.DOWN)})
	check(m.projectile_telemetry().size() == 1,"Orb reflects before collision")
	if not m.projectile_telemetry().is_empty():
		var reflected = m.projectile_telemetry()[0]
		check(reflected.source == 2 and reflected.facing == -1,"current owner and facing transfer")
		check(is_equal_approx(reflected.remaining,.8-1.0/60) and is_equal_approx(reflected.age,1.5+1.0/60),"source frost min .8 refresh preserves age")
		check(reflected.activation_id == "shot","reflection stable identity")
		m.expire_source(1,"old owner")
		check(m.projectile_telemetry().size() == 1,"old owner cleanup preserves reflected frost")
		m.expire_source(2,"current owner")
		check(m.projectile_telemetry().is_empty() and not shot.active,"current owner cleanup cancels object")
	m.reset({1:Vector3(-10,20,0),2:Vector3(1,20,0)})
	var wall = terrain(Vector3(.5,21,0),Vector3(.1,4,4))
	await step(m)
	emit(m,Vector3(.3,21,0),"terrain"); await step(m)
	check(m.fighters[2].percent == 0 and m.projectile_telemetry().is_empty(),"real terrain ray wins over nearby fallback")
	check(m.ability_events.size() == 1 and m.ability_events[0].kind == "terrain","terrain telemetry committed")
	wall.free()
	var floor = terrain(Vector3(0,-.5,0),Vector3(100,1,10))
	m.reset({1:Vector3(-10,.01,0),2:Vector3(0,.01,0)})
	for i in 12: await step(m)
	check(b.runtime.grounded,"ray fixture settled")
	# Above .75 fallback radius but intersects rounded top of real capsule.
	emit(m,b.position+Vector3(-.25,1.78,0),"body-ray"); await step(m)
	check(m.fighters[2].percent == 4 and m.fighters[2].frozen,"actual capsule ray outside fallback")
	m.reset({1:Vector3(-10,20,0),2:Vector3(10,20,0)})
	emit(m,Vector3(0,21,0),"ttl")
	shot = m.projectile_host.live[0]; shot.remaining = 1.0/60
	await step(m)
	check(not shot.active and m.projectile_telemetry().is_empty(),"TTL decrements before final query")
	a.free(); b.free(); floor.free()
	if not failures: print("PASS: ice match projectile (%d checks)" % checks)
	quit(1 if failures else 0)
