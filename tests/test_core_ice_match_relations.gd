extends "res://tests/test_core_ice_match_shatter.gd"
func floor_body():
	var body = StaticBody3D.new(); var shape = CollisionShape3D.new(); var box = BoxShape3D.new()
	box.size = Vector3(100,1,10); shape.shape = box; body.add_child(shape); body.position.y = -.5; root.add_child(body); return body
func run():
	var floor = floor_body()
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); var c = Actor.new()
	root.add_child(a); root.add_child(b); root.add_child(c)
	m.register_actor(1,a); m.register_actor(2,b,-1,"ice_mage"); m.register_actor(3,c,-1,"ice_mage")
	for victim in [1,2]:
		m.reset({1:Vector3(0,.01,0),2:Vector3(1,.01,0),3:Vector3(10,.01,0)})
		for i in 12: await step(m)
		await step(m,{1:press(Vector2.ZERO)})
		for i in 11: await step(m)
		check(m.fighters[2].caught_by == 1,"real grab fixture")
		check(not a.get_collision_exceptions().is_empty(),"grab relation owns collision exceptions")
		bolt(m,3,victim,"interrupt-grab"); await step(m)
		check(m.fighters[victim].frozen,"freeze caster or captive commits")
		check(m.fighters[2].caught_by == 0 and m.fighters[1].grab == null,"freeze releases grab both directions")
		check(a.get_collision_exceptions().is_empty() and b.get_collision_exceptions().is_empty(),"freeze clears relation collision exclusions")
	# Dedupe belongs to accepted resolver output, never raw candidate status list.
	m.reset({1:Vector3(-10,50,0),2:Vector3(0,50,0),3:Vector3(10,50,0)})
	bolt(m,1,2,"duplicate"); bolt(m,1,2,"duplicate"); await step(m)
	check(m.fighters[2].percent == 4 and m.fighters[2].frozen,"duplicate identity hits/status only once")
	check(m.status_telemetry(2).freeze_immunity == 0,"duplicate rejected damage cannot shatter")
	bolt(m,1,2,"duplicate"); await step(m)
	check(m.fighters[2].percent == 4 and m.fighters[2].frozen,"later duplicate cannot shatter")
	m.fighters[1].team = 1; m.fighters[2].team = 1
	bolt(m,1,2,"team"); await step(m)
	check(m.fighters[2].percent == 4,"allied body excluded from real ray and fallback")
	m.expire_source(1,"source cleanup")
	check(m.fighters[2].frozen,"source cleanup does not erase independently owned victim status")
	a.free(); b.free(); c.free(); floor.free()
	if not failures: print("PASS: ice match relations/dedupe (%d checks)" % checks)
	quit(1 if failures else 0)
