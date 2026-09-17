extends "res://tests/test_core_recovery_acceptance.gd"
const Special = preload("res://scripts/core/kits/turbofit_specials.gd")
const Wave = preload("res://scripts/core/kits/turbofit_wave.gd")
const ForceShot = preload("res://scripts/core/combat/force_projectile.gd")
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1,a); m.register_actor(2,b,-1,"turbofit")
	check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(4,20,0)},{1:load("res://data/collision/generated/teknium.tres"),2:load("res://data/collision/generated/turbofit.tres")}),"actual reflection profiles")
	await step(m)
	var limb: Dictionary = m.collision_telemetry(1).primitives[0]
	var center: Vector3 = (limb.a+limb.b)*.5
	var shot := {"source":1,"activation_id":"reflect-force","facing":1.0,"position":center,"spawn_tick":-1,"ttl":47}
	m.projectiles.append(shot)
	var orb = Special.new(); orb.start("orb",Vector2.DOWN,-1)
	var intents: Array = orb.collect(2,center-Vector3.UP,[],m._reflectable_projectiles())
	check(intents.size() == 1 and intents[0].kind == "reflect","actual Orb reflection intent")
	m._commit_kit_intents(intents)
	check(shot.source == 2 and shot.facing == -1 and shot.ttl == 47,"reflect swaps Force owner not lifetime")
	var outcome: Dictionary = ForceShot.advance(shot,m.fighters,m.tick)
	check(outcome.has("contact") and outcome.contact.victim == 1 and outcome.contact.geometry_mode == "generated_hurtboxes","reflected Force hits old owner limbs")
	check(orb.collect(2,center-Vector3.UP,[],m._reflectable_projectiles()).is_empty(),"one reflection per Orb projectile")
	var wave = Wave.new(); wave.start("reflect-wave",1,-1,center,1)
	wave.age = .2; wave.distance = 1.2
	check(wave.reflect(2,-1) and wave.age == .2 and wave.distance == 1.2,"Wave reflection preserves finite budgets")
	var targets := [{"id":1,"body":a,"collision_host":m.fighters[1].collision_host},{"id":2,"body":b,"collision_host":m.fighters[2].collision_host}]
	var hit: Array = wave.tick(1.0/60,{"space":a.get_world_3d().direct_space_state,"targets":targets})
	check(hit.size() == 1 and hit[0].victim == 1 and hit[0].geometry_mode == "generated_hurtboxes","reflected Wave hits old owner limbs")
	wave = Wave.new(); wave.start("paused",2,-1,center,-1)
	var before: Dictionary = wave.snapshot()
	check(wave.tick(1.0/60,{"space":a.get_world_3d().direct_space_state,"targets":targets,"paused":true}).is_empty() and wave.snapshot() == before,"paused Wave neither moves nor contacts")
	wave.age = .65-1.0/60
	check(wave.tick(1.0/60,{"space":a.get_world_3d().direct_space_state,"targets":targets}).is_empty() and wave.active,"fade boundary harmless to actual limbs")
	# Real host passes generated snapshots, not just standalone target dictionaries.
	m.projectiles.clear()
	limb = m.collision_telemetry(2).primitives[0]; center = (limb.a+limb.b)*.5
	wave = Wave.new(); wave.start("host-wave",1,-1,center,1); m.waves.append(wave)
	await step(m)
	check(m.fighters[2].percent == 11 and m.waves.is_empty(),"real match Wave generated damage and consumption")
	check(m.events.size() == 1 and m.events[0].geometry_mode == "generated_hurtboxes","real Wave committed evidence")
	a.free(); b.free()
	if not failures: print("PASS: two fighter reflection (%d checks)" % checks)
	quit(1 if failures else 0)
