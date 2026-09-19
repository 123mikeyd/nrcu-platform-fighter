extends "res://tests/test_core_match_strikes.gd"
const Match = preload("res://scripts/core/match/match_simulation.gd")
const Policy = preload("res://scripts/core/combat/hitstop_profile.gd")
func run() -> void:
	await trades()
	await phases()
	await electric()
	await presentation_invariance()
	if not failures: print("PASS: core hitstop integration (%d checks)" % checks)
	quit(1 if failures else 0)
func trades() -> void:
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); var c = Actor.new()
	for actor in [a,b,c]: root.add_child(actor)
	m.register_actor(1,a); m.register_actor(2,b); m.register_actor(3,c)
	var spawns = {1:Vector3(0,20,0),2:Vector3(1,20,0),3:Vector3(-1,20,0)}
	m.reset(spawns)
	await tick(m,{1:frame(true,1),2:frame(true,-1),3:frame(true,1)})
	check(m.fighters[1].hitstop_left == 0 and m.fighters[2].hitstop_left == 0, "sandbox remains opt-out")
	m.reset(spawns)
	var policy = Policy.new(); policy.direct_hit_ticks = 7; m.configure_hitstop(policy); policy.direct_hit_ticks = 1
	await tick(m,{1:frame(true,1),2:frame(true,-1),3:frame(true,1)})
	check(m.fighters[1].percent > 0 and m.fighters[2].percent > 8, "shared snapshot trades and multiple hits survive source cancellation")
	for id in [1,2,3]: check(m.fighters[id].hitstop_left == 7, "all contributing attackers freeze using max not sum and copied tuning")
	var damage = m.fighters[2].percent
	for i in 7: await tick(m)
	check(m.fighters[2].percent == damage, "stop never repeats contact damage")
	for actor in [a,b,c]: actor.free()
func phases() -> void:
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1,a); m.register_actor(2,b)
	m.configure_hitstop(Policy.new()); m.reset({1:Vector3(0,20,0),2:Vector3(1,20,0)})
	var special = Frame.new(); special.pressed.special = true; special.axis.y = -1
	await tick(m,{1:special})
	var recovery = m.fighters[1].recovery; var ready = m.fighters[1].ready_tick - m.tick
	check(recovery != null and recovery.age == 1 and m.fighters[1].hitstop_left == 4, "real recovery hit commits without same-tick pause")
	for i in 4: await tick(m)
	check(recovery.age == 1 and m.fighters[1].ready_tick - m.tick == ready, "active recovery and cooldown pause together")
	await tick(m)
	check(recovery.age == 2 and m.fighters[1].hitstop_left == 0, "recovery resumes without repeat victim hitstop")
	m.reset({1:Vector3(0,20,0),2:Vector3(100,20,0)})
	special.axis = Vector2.RIGHT
	await tick(m,{1:special})
	var force = m.fighters[1].force; var age = force.age
	m.fighters[1].hitstop_left = 4
	m.projectiles.append({"source":1,"activation_id":"independent","facing":1.0,"position":Vector3(20,20,0),"spawn_tick":-1,"ttl":96})
	for i in 4: await tick(m)
	check(force.age == age and m.ability_events.is_empty(), "force phase and source event cannot advance while stopped")
	check(m.projectiles[0].position == Vector3(21,20,0) and m.projectiles[0].ttl == 92, "projectiles retain independent world motion and TTL")
	await tick(m)
	check(force.age == age + 1, "force phase resumes once")
	# Existing freeze remains intent-only after hitstop expires; no status overwrite.
	m.set_frozen(1,true); a.apply_combat_launch(Vector3(3,5,0),8); m.fighters[1].hitstop_left = 2
	var v = a.velocity; var at = a.position
	for i in 2: await tick(m)
	check(a.velocity == v and a.position == at and a.runtime.hitstun_left == 8 and a.runtime.states.status == "frozen", "hitstop gates physics above freeze and hitstun without erasing constraints")
	await tick(m)
	check(a.runtime.hitstun_left == 7 and a.runtime.states.status == "frozen", "lower status clock resumes after pause")
	a.free(); b.free()
func electric() -> void:
	var floor_body = StaticBody3D.new(); var shape = CollisionShape3D.new(); var box = BoxShape3D.new(); box.size = Vector3(30,1,10)
	shape.shape = box; floor_body.add_child(shape); floor_body.position.y = -0.5; root.add_child(floor_body)
	var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
	m.register_actor(1,a); m.register_actor(2,b); m.configure_hitstop(Policy.new()); m.reset({1:Vector3.ZERO,2:Vector3(1,0,0)})
	for i in 10: await tick(m)
	var special = Frame.new(); special.pressed.special = true
	await tick(m,{1:special})
	for i in 96:
		await tick(m)
		check(m.fighters[1].hitstop_left == 0 and m.fighters[2].hitstop_left == 0, "electric percent ordinals never request hitstop")
	check(m.fighters[2].percent == 10, "all five real electric ordinals still fire")
	a.free(); b.free(); floor_body.free()
func presentation_invariance() -> void:
	var snapshots: Array = []
	for visible in [false,true]:
		var m = Match.new(); var a = Actor.new(); var b = Actor.new(); root.add_child(a); root.add_child(b)
		m.register_actor(1,a); m.register_actor(2,b); m.configure_hitstop(Policy.new()); m.reset({1:Vector3(0,20,0),2:Vector3(1,20,0)})
		var presenter = null
		if visible:
			presenter = load("res://scripts/core/presentation/teknium_presenter.gd").new(); root.add_child(presenter)
		var replay: Array = []
		for i in 12:
			await tick(m,{1:frame(i==0,1)})
			var telemetry = m.hitstop_telemetry(1)
			if visible: presenter.present(a.telemetry(),telemetry.simulation_tick)
			replay.append([a.position,b.position,a.velocity,b.velocity,m.fighters[2].percent,telemetry.simulation_tick,telemetry.remaining_ticks])
		snapshots.append(replay)
		if visible: presenter.free()
		a.free(); b.free()
	check(snapshots[0] == snapshots[1], "real presenter present/absent produces identical simulation replay")
