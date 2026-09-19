extends "res://tests/test_core_recovery_acceptance.gd"
const Recipient = preload("res://scripts/core/collision/recipient_queries.gd")
const ForceShot = preload("res://scripts/core/combat/force_projectile.gd")
const Wave = preload("res://scripts/core/kits/turbofit_wave.gd")
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1,a); m.register_actor(2,b)
	for character in ["teknium","turbofit"]:
		check(m.reset_with_collision_profiles({1:Vector3(-10,20,0),2:Vector3(3,20,0)},{1:load("res://data/collision/generated/teknium.tres"),2:load("res://data/collision/generated/"+character+".tres")}),"actual world profiles")
		await step(m)
		var c: Dictionary = m.collision_telemetry(2).primitives[0]
		var center: Vector3 = (c.a+c.b)*.5
		# Locate the first real limb crossing independently of the native body.
		var long_start := center-Vector3(5,0,0)
		var crossing: Dictionary = Recipient.sphere(m.fighters[2],long_start,center,0)
		check(not crossing.is_empty(),"actual ray crossing fixture")
		var boundary: Vector3 = long_start.lerp(center,crossing.t)
		var start := boundary-Vector3(.15,0,0)
		var unobstructed: Dictionary = Recipient.sphere(m.fighters[2],start,start+Vector3(.25,0,0),0)
		check(not unobstructed.is_empty() and unobstructed.t > 0,"limb would hit after wall without terrain")
		var wall := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
		box.size = Vector3(.02,10,10); shape.shape = box; wall.add_child(shape); wall.position = boundary-Vector3(.08,0,0); root.add_child(wall)
		await physics_frame
		var shot := {"source":1,"activation_id":"wall-force","facing":1.0,"position":start,"spawn_tick":-1,"ttl":96}
		var outcome: Dictionary = ForceShot.advance(shot,m.fighters,m.tick)
		check(outcome.get("consumed",false) and not outcome.has("contact"),"Force wall blocks before actual limbs "+character)
		# Initial wall overlap wins over overlapping generated fighter geometry.
		var wave = Wave.new(); wave.start("wall-wave",1,-1,center,1)
		wall.position = center
		await physics_frame
		var hit: Array = wave.tick(1.0/60,{"space":a.get_world_3d().direct_space_state,"targets":[{"id":1,"body":a},{"id":2,"body":b,"collision_host":m.fighters[2].collision_host}]})
		check(hit.size() == 1 and hit[0].kind == "terrain","Wave initial terrain/limb tie blocks "+character)
		wall.free()
	a.free(); b.free()
	if not failures: print("PASS: two fighter world (%d checks)" % checks)
	quit(1 if failures else 0)
