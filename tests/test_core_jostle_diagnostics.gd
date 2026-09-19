extends "res://tests/test_core_top_support_lifecycle.gd"
func run():
	var f = setup_pair("teknium","turbofit",true,"auto")
	check(f.m.has_method("jostle_world"),"public detached jostle world geometry exists")
	if f.m.has_method("jostle_world"):
		f.m.reset({1:Vector3(-0.1,0,0),2:Vector3(0.1,0,0)})
		for i in 8: await step(f.m)
		for id in [1,2]:
			var d: Dictionary = f.m.jostle_world(id)
			var actor = f.m.fighters[id].actor
			var shape = actor.get_node("CoreCapsule")
			check(d.entity_id == id and d.mode == "grounded_jostle","stable entity identity and selected mode")
			check(d.eligible and d.grounded,"real terrain eligible prerequisite")
			check(d.world_segment == [Vector3(shape.global_position.x-shape.shape.radius,actor.global_position.y,shape.global_position.z),Vector3(shape.global_position.x+shape.shape.radius,actor.global_position.y,shape.global_position.z)],"actual solver horizontal world range")
			check(d.profile_revision == actor.body_profile_snapshot().revision,"actual body profile revision")
			check(absf(d.last_correction) <= .25,"bounded applied correction")
			var saved = d.duplicate(true)
			d.world_segment[0] = Vector3.INF
			d.eligible = false; d.entity_id = 999; d.profile_revision = -1; d.last_correction = 999
			d.mode = "forged"; d.grounded = false; d.generation = -1; d.tick = -1
			check(f.m.jostle_world(id) == saved,"all returned fields detached and repeat reads stable")
		f.a.position.x = -0.01; f.b.position.x = 0.01
		var before_x: float = f.a.position.x
		await step(f.m)
		check(absf(f.a.position.x-before_x) > 0.001,"positive real ground correction prerequisite")
		check(is_equal_approx(f.m.jostle_world(1).last_correction,f.a.position.x-before_x),"last correction equals applied travel not proposal")
		f.m.reset({1:Vector3(0,6,0),2:Vector3.ZERO})
		check(f.m.jostle_world(1).last_correction == 0.0,"reset retires last correction")
		await step(f.m)
		check(not f.m.jostle_world(1).grounded and not f.m.jostle_world(1).eligible,"air range explicitly ineligible")
		f.m.set_enabled(2,false)
		check(not f.m.jostle_world(2).eligible,"disable immediately ineligible")
		check(f.m.jostle_world(999).is_empty(),"unknown stable ID empty")
	dispose(f)
	if not failures: print("PASS: copied authoritative jostle world diagnostics")
	quit(1 if failures else 0)
