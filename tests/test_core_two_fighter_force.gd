extends "res://tests/test_core_recovery_acceptance.gd"
const ForceShot = preload("res://scripts/core/combat/force_projectile.gd")
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a); m.register_actor(2,b)
	for character in ["teknium","turbofit"]:
		check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(3,20,0)},{1:load("res://data/collision/generated/teknium.tres"),2:load("res://data/collision/generated/"+character+".tres")}),"actual profiles")
		await step(m)
		var capsule: Dictionary = m.collision_telemetry(2).primitives[0]
		var center: Vector3 = (capsule.a+capsule.b)*.5
		var shot := {"source":1,"activation_id":"force","facing":1.0,"position":center-Vector3(.1,0,0),"spawn_tick":-1,"ttl":96}
		var result: Dictionary = ForceShot.advance(shot,m.fighters,m.tick)
		check(result.has("contact"),"Force actual limb hit "+character)
		if result.has("contact"): check(result.contact.get("geometry_mode","") == "generated_hurtboxes","Force generated evidence "+character)
		m.fighters[2].collision_host.invalidate("test invalid snapshot")
		var body: CollisionShape3D = b.get_node("CoreCapsule")
		shot.position = body.global_position-Vector3(.1,0,0)
		result = ForceShot.advance(shot,m.fighters,m.tick)
		check(not result.get("consumed",false),"Force invalid generated snapshot cannot hit or consume on native body "+character)
	a.free(); b.free()
	if not failures: print("PASS: two fighter Force (%d checks)" % checks)
	quit(1 if failures else 0)
