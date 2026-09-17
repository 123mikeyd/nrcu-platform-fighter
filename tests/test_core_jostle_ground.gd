extends "res://tests/test_core_top_support_lifecycle.gd"
func run():
	var baselines = {}
	for lower in ["teknium","turbofit"]:
		for upper in ["teknium","turbofit"]:
			for reverse in [false,true]:
				for side in [-1,1]:
					var f = setup_pair(lower,upper,reverse,"auto")
					f.m.reset({1:Vector3(side*2,0,0),2:Vector3.ZERO})
					for i in 8: await step(f.m)
					check(f.a.runtime.grounded and f.b.runtime.grounded,"both actual terrain floors")
					var source = Source.new(); var code = KEY_D if side < 0 else KEY_A
					key(code,true)
					for i in 35: await step(f.m,{1:source.sample(f.m.tick)})
					key(code,false)
					for i in 20: await step(f.m,{1:source.sample(f.m.tick)})
					var ca = f.a.get_node("CoreCapsule"); var cb = f.b.get_node("CoreCapsule")
					check(side*(ca.global_position.x-cb.global_position.x) >= ca.shape.radius+cb.shape.radius-0.003,"ground approach retains order and separates cores")
					var positions = [f.a.position,f.b.position]
					for i in 10: await step(f.m)
					check(f.a.position.distance_to(positions[0])<0.0001 and f.b.position.distance_to(positions[1])<0.0001,"steady no jitter or injected movement")
					var identity = lower+upper+str(side)
					if baselines.has(identity):
						check(f.a.position.distance_to(baselines[identity][0])<0.00001 and f.b.position.distance_to(baselines[identity][1])<0.00001,"registration order identical final positions")
					else: baselines[identity] = [f.a.position,f.b.position]
					dispose(f)
	if not failures: print("PASS: grounded native parsed approach all pairs orders and facings")
	quit(1 if failures else 0)
