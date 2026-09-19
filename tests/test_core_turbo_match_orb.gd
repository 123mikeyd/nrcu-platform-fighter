extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b)
	m.reset({1:Vector3(0,40,0),2:Vector3(10,40,0)})
	await step(m,{1:press(Vector2.DOWN)})
	for i in 31: await step(m)
	b.position = a.position + Vector3(1,0,0); b.runtime.velocity = a.runtime.velocity
	await step(m)
	check(m.events.size() == 1, "Orb queries final crossing interval before decrement")
	check(m.fighters[2].percent == 0 and b.runtime.hitstun_left > 0, "zero damage Orb commits real launch and interruption")
	if not m.events.is_empty(): check(m.events[0].base_knockback == 7, "Orb source knockback")
	check(m.fighters[1].force == null and m.fighters[1].grab == null, "Orb not routed to fallback")
	a.free(); b.free()
	if not failures: print("PASS: turbo match Orb (%d checks)" % checks)
	quit(1 if failures else 0)
