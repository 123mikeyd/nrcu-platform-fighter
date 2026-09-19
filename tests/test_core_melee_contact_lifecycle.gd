extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b)
	check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(1.1,20,0)},{1:load("res://data/collision/generated/turbofit.tres"),2:load("res://data/collision/generated/teknium.tres")}),"actual profiles")
	a.runtime.grounded = true; await step(m,{1:press(Vector2.RIGHT,"attack")})
	var reached := false
	for age in 35:
		await step(m)
		if m.events.is_empty(): continue
		reached = true
		var targets: Array = m._kit_targets(1)
		var basic = m.fighters[1].kit.basic
		var late: Array = targets.duplicate(true)
		for target in late:
			if target.id == 2: target.id = 3
		basic.tick(.2)
		check(basic.contacts(1,a.global_position,late).is_empty(),"advanced source clock cannot reuse previous active geometry on a late victim")
		basic.cancel(); check(basic.start("next",Vector2.RIGHT,false,1),"new episode accepted")
		check(basic.contacts(1,a.global_position,targets).is_empty(),"new source startup cannot reuse old episode attack geometry")
		break
	check(reached,"real previous active contact prerequisite")
	a.free(); b.free()
	if not failures: print("PASS: melee lifecycle geometry retirement (%d checks)" % checks)
	quit(1 if failures else 0)
