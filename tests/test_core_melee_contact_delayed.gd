extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1,a); m.register_actor(2,b)
	for facing in [-1,1]:
		for distance in [1.1,2.4]:
			check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(facing*distance,20,0)},{1:load("res://data/collision/generated/teknium.tres"),2:load("res://data/collision/generated/turbofit.tres")}),"actual profiles")
			await step(m,{1:press(Vector2(facing,0),"attack")})
			var impacts := 0; var first := -1
			for age in range(1,20):
				await step(m)
				for event in m.events:
					if event.source == 1:
						impacts += 1
						if first < 0: first = age
			if distance < 2:
				check(impacts == 1,"real fist contact arrives once after startup facing "+str(facing))
				check(first >= 8,"impact follows actual input activation")
			else: check(impacts == 0,"old cone range remains empty space")
	a.free(); b.free()
	if not failures: print("PASS: melee delayed contact (%d checks)" % checks)
	quit(1 if failures else 0)
