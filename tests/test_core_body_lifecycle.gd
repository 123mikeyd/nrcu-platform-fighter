extends "res://tests/test_core_grab_slice.gd"
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b); m.register_actor(1,a); m.register_actor(2,b)
	m.reset({1:Vector3(-2,5,0),2:Vector3(0,5,0)})
	m.set_enabled(2,false)
	check(b.collision_layer == 0, "disabled fighter removes body occupancy immediately")
	m.set_enabled(2,true)
	check(b.collision_layer == 2 and b.collision_mask == 3, "reenable restores native body filtering")
	m.set_enabled(2,false); m.reset({1:Vector3(-2,5,0),2:Vector3(0,5,0)})
	check(b.collision_layer == 2, "reset restores participation")
	for reason in ["release","freeze","disabled","remove","reset"]:
		m.reset({1:Vector3.ZERO,2:Vector3.RIGHT})
		a._head_slip_direction = 1; a._contacts_valid = true
		b._head_slip_direction = -1; b._contacts_valid = true
		var f = Frame.new(); f.pressed.special = true
		await step(m,{1:f})
		for i in 11: await step(m)
		check(m.fighters[2].caught_by == 1,"real capture " + reason)
		check(b in a.get_collision_exceptions() and a in b.get_collision_exceptions(),"reciprocal capture " + reason)
		check(not a._contacts_valid and not b._contacts_valid and a._head_slip_direction == 0 and b._head_slip_direction == 0,"capture invalidates both body episodes")
		a._head_slip_direction = 1; a._contacts_valid = true
		b._head_slip_direction = -1; b._contacts_valid = true
		b.runtime.air_jumps_left = 0; b.runtime.recovery_spent = true
		if reason == "release": m.cancel_action(1,"test release")
		elif reason == "freeze": m.set_frozen(1,true)
		elif reason == "disabled": m.set_enabled(1,false)
		elif reason == "reset": m.reset({1:Vector3.ZERO,2:Vector3.RIGHT})
		else: root.remove_child(b)
		check(not a._contacts_valid and not b._contacts_valid and a._head_slip_direction == 0 and b._head_slip_direction == 0,"release invalidates both contact episodes " + reason)
		check(not b in a.get_collision_exceptions() and not a in b.get_collision_exceptions(),"reciprocal cleanup " + reason)
		if reason != "reset": check(b.runtime.air_jumps_left == 0 and b.runtime.recovery_spent,"release does not refund " + reason)
		if reason == "remove": root.add_child(b)
	a.free(); b.free()
	if not failures: print("PASS body lifecycle (%d checks)" % checks)
	quit(1 if failures else 0)
