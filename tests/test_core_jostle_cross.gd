extends "res://tests/test_core_top_support_lifecycle.gd"
func run():
	for lower in ["teknium","turbofit"]:
		for upper in ["teknium","turbofit"]:
			for reverse in [false,true]:
				for side in [-1,1]:
					var f = setup_pair(lower,upper,reverse,"auto")
					var control = []
					var intersected = false
					for nearby in [false,true]:
						f.m.reset({1:Vector3(side*0.7,1.6,0),2:Vector3(0 if nearby else 10,0,0)})
						var source = Source.new(); var code = KEY_D if side < 0 else KEY_A
						key(code,true)
						for i in 17:
							await step(f.m,{1:source.sample(f.m.tick)})
							check(not f.a.runtime.grounded,"crossing remains aerial")
							if nearby:
								check(f.a.position.distance_to(control[i][0])<0.00001 and f.a.velocity.distance_to(control[i][1])<0.00001,"opponent does not deflect aerial trajectory")
								if absf(f.a.position.x) < 0.3 and f.a.position.y < 1.7: intersected = true
							else: control.append([f.a.position,f.a.velocity])
						key(code,false)
					check(intersected and side*f.a.position.x < 0,"actual parsed horizontal passage through core prerequisite")
					dispose(f)
	if not failures: print("PASS: aerial parsed cross identical to opponent-absent trajectory")
	quit(1 if failures else 0)
