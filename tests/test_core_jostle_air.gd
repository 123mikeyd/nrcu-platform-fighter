extends "res://tests/test_core_top_support_lifecycle.gd"
func run():
	for lower in ["teknium","turbofit"]:
		for upper in ["teknium","turbofit"]:
			for reverse in [false,true]:
				for side in [-1,1]:
					var f = setup_pair(lower,upper,reverse,"auto")
					f.a.position.x = side*0.2
					f.a.runtime.air_jumps_left = 1; f.a.runtime.recovery_spent = false
					var source = Source.new()
					key(KEY_SPACE,true); await step(f.m,{1:source.sample(f.m.tick)}); key(KEY_SPACE,false)
					check(f.a.velocity.y > 0 and f.a.runtime.air_jumps_left == 0,"parsed jump actually accepted")
					var crossed = false
					for i in 85:
						await step(f.m,{1:source.sample(f.m.tick)})
						if f.a.position.y > 0.05:
							check(not f.a.runtime.grounded,"no fighter floor")
							check(absf(f.a.velocity.x)<0.00001 and absf(f.a.position.x-side*0.2)<0.0001,"no aerial sideways injection")
						if f.a.position.y < 0.8 and f.a.position.y > 0.05: crossed = true
					check(crossed,"actual descent through rounded core")
					check(f.m.top_support_telemetry(1).geometry.is_empty() and f.m.top_support_telemetry(1).relation.is_empty(),"no default head relation or orange geometry")
					dispose(f)
	if not failures: print("PASS: generated grounded-jostle aerial parsed input matrix")
	quit(1 if failures else 0)
