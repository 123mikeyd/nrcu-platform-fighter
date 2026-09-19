extends "res://tests/test_core_body_profile.gd"
func run():
	for reverse in [false,true]:
		var m = Match.new(); var a = Actor.new(); var b = Actor.new()
		a.configure_body_profile(body_profile(0.25,1.0)); b.configure_body_profile(body_profile(0.6,3.0))
		root.add_child(a); root.add_child(b)
		if reverse: m.register_actor(2,b); m.register_actor(1,a)
		else: m.register_actor(1,a); m.register_actor(2,b)
		m.reset({1:Vector3(0,2,0),2:Vector3(0.1,0,0)})
		check(m._body_overlap_directions([1,2]).size() == 2, "unequal actual spine overlap not missed by foot delta")
		m.reset({1:Vector3.ZERO,2:Vector3(0.1,1.2,0)})
		check(m._body_overlap_directions([1,2]).is_empty(), "separated actual spines not false overlap")
		a.free(); b.free()
	if not failures: print("PASS body profile overlap (%d checks)" % checks)
	quit(1 if failures else 0)
