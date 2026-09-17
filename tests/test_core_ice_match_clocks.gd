extends "res://tests/test_core_ice_match_shatter.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"ice_mage"); m.register_actor(2,b,-1,"ice_mage")
	m.reset({1:Vector3(-10,80,0),2:Vector3(0,80,0)})
	bolt(m,1,2,"freeze"); await step(m)
	var time: float = m.status_telemetry(2).freeze_remaining
	var actor_tick: int = b.runtime.tick
	m.fighters[2].hitstop_left = 5
	var f = Frame.new(); f.pressed.attack = true
	await step(m,{2:f})
	for i in 4: await step(m)
	check(b.runtime.tick == actor_tick and m.status_telemetry(2).freeze_remaining == time,"hitstop suspends actor and freeze clocks")
	check(not m.fighters[2].buffer.peek("attack").is_empty(),"hitstop buffers edge under finite freeze")
	await step(m)
	check(is_equal_approx(m.status_telemetry(2).freeze_remaining,time-1.0/60),"one status advance on resume")
	check(m.fighters[2].move_id == "","unexpired freeze still blocks buffered attack")
	m.reset({1:Vector3(-10,80,0),2:Vector3(0,80,0)})
	bolt(m,1,2,"world"); m.fighters[1].hitstop_left = 10
	await step(m)
	check(m.fighters[2].percent == 4 and m.fighters[2].frozen,"source hitstop does not stop detached frost")
	# Both emitted candidates survive mutual actor interruption.
	m.reset({1:Vector3(-10,80,0),2:Vector3(0,80,0)})
	bolt(m,1,2,"trade-a"); bolt(m,2,1,"trade-b"); await step(m)
	check(m.fighters[1].percent == 4 and m.fighters[2].percent == 4,"duplicate damage trade")
	check(m.fighters[1].frozen and m.fighters[2].frozen,"duplicate status trade despite source freeze")
	m.reset({1:Vector3(-10,80,0),2:Vector3(0,80,0)})
	m.configure_actor_kit(1,"turbofit")
	bolt(m,1,2,"utility-freeze"); await step(m)
	# Real Orb utility launch must not be mistaken for positive damage.
	a.reset_at(b.position+Vector3(-1.0,0,0)); a.runtime.velocity = b.runtime.velocity
	await step(m,{1:press(Vector2.DOWN)})
	check(not m.events.is_empty() and m.events[0].damage == 0,"real Orb zero damage candidate")
	check(m.fighters[2].frozen and m.status_telemetry(2).freeze_immunity == 0,"zero damage does not shatter")
	var before = m.status_telemetry(2)
	m.result = {"kind":"DRAW"}
	for i in 3: await step(m)
	check(m.status_telemetry(2) == before,"results gate status clock")
	a.free(); b.free()
	if not failures: print("PASS: ice match clocks/trades (%d checks)" % checks)
	quit(1 if failures else 0)
