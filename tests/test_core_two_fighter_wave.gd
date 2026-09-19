extends "res://tests/test_core_recovery_acceptance.gd"
const Wave = preload("res://scripts/core/kits/turbofit_wave.gd")
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b)
	for character in ["teknium","turbofit"]:
		check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(3,20,0)},{1:load("res://data/collision/generated/turbofit.tres"),2:load("res://data/collision/generated/"+character+".tres")}),"actual profiles")
		await step(m)
		var capsule: Dictionary = m.collision_telemetry(2).primitives[0]
		var center: Vector3 = (capsule.a+capsule.b)*.5
		for shielding in [false,true]:
			var wave = Wave.new(); wave.start("wave",1,-1,center,1)
			var target := {"id":2,"body":b,"team":-1,"eligible":true,"shielding":shielding,"collision_host":m.fighters[2].collision_host}
			var result: Array = wave.tick(1.0/60,{"space":b.get_world_3d().direct_space_state,"targets":[{"id":1,"body":a},target]})
			check(result.size() == 1,"Wave actual limb hit "+character)
			if not result.is_empty():
				check(result[0].get("geometry_mode","") == "generated_hurtboxes","Wave generated evidence "+character)
				check(result[0].kind == ("shield_absorb" if shielding else "hit"),"Wave committed shield result")
		m.fighters[2].collision_host.invalidate("test invalid")
		var wave = Wave.new(); wave.start("invalid",1,-1,b.get_node("CoreCapsule").global_position,1)
		var targets := [{"id":1,"body":a},{"id":2,"body":b,"collision_host":m.fighters[2].collision_host}]
		check(wave.tick(1.0/60,{"space":b.get_world_3d().direct_space_state,"targets":targets}).is_empty() and wave.active,"Wave invalid snapshot cannot consume on native body "+character)
	a.free(); b.free()
	if not failures: print("PASS: two fighter wave (%d checks)" % checks)
	quit(1 if failures else 0)
