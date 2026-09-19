extends "res://tests/test_core_recovery_acceptance.gd"
func held_special():
	var f = Frame.new(); f.held.special = true; return f
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b,-1,"turbofit")
	m.reset({1:Vector3(0,30,0),2:Vector3(2,30,0)})
	var edge = press(Vector2.ZERO); edge.held.special = true
	await step(m,{1:edge,2:edge})
	check(m.kit_telemetry(1).get("special",{}).get("phase","") == "anticipation", "neutral special starts held charge, not grab")
	if not m.kit_telemetry(1).has("special"):
		a.free(); b.free(); quit(1); return
	for i in 45: await step(m,{1:held_special(),2:held_special()})
	check(is_equal_approx(m.kit_telemetry(1).special.power,.5), "45 committed held ticks half power")
	var clock: float = m.kit_telemetry(1).special.age
	m.fighters[1].hitstop_left = 3
	for i in 3: await step(m,{1:held_special(),2:held_special()})
	check(m.kit_telemetry(1).special.age == clock, "local charge clock pauses in hitstop")
	b.position = a.position + Vector3(2,0,0); b.runtime.velocity = a.runtime.velocity
	await step(m,{2:held_special()})
	check(is_equal_approx(m.fighters[2].percent,18), "half charge release resolves 18 damage")
	check(m.kit_telemetry(2).special.phase == "idle", "incoming hit cancels other charge")
	check(is_equal_approx(m.kit_telemetry(1).special.cooldown,.7), "release step does not decrement new cooldown")
	check(m.fighters[1].grab == null and m.fighters[1].force == null, "charge has no Teknium fallback")
	a.free(); b.free()
	if not failures: print("PASS: turbo match charge (%d checks)" % checks)
	quit(1 if failures else 0)
