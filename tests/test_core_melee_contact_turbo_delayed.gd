extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b)
	for clip in ["MeleeHorizontal","MeleeBackhand","GoalkeeperKick"]:
		for face in [-1,1]:
			check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(face*1.1,20,0)},{1:load("res://data/collision/generated/turbofit.tres"),2:load("res://data/collision/generated/teknium.tres")}),"actual profiles")
			a.runtime.grounded = true
			m.fighters[1].facing = face
			await step(m,{1:press(Vector2(face,-1 if clip == "MeleeBackhand" else (1 if clip == "GoalkeeperKick" else 0)),"attack")})
			check(m.fighters[1].move_id == clip,"actual input selects physical move")
			check(m.events.is_empty(),"no acceptance contact")
			var impacts := 0
			for age in range(1,40):
				await step(m)
				for event in m.events:
					if event.source == 1:
						impacts += 1
						check(event.contact_evidence.has("attack_shape"),"source bone geometry evidence")
			check(impacts == 1,"real visible limb contact once "+clip+str(face))
	a.free(); b.free()
	if not failures: print("PASS: melee Turbo delayed (%d checks)" % checks)
	quit(1 if failures else 0)
