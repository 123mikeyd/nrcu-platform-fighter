extends "res://tests/test_core_turbo_match_routes.gd"
func run():
	var floor = floor_body()
	floor.add_to_group("core_pass_through"); floor.set_meta("top_y",0.0)
	for aim in [Vector2.ZERO,Vector2.DOWN]:
		var m = Match.new(); var a = Actor.new(); var b = Actor.new()
		root.add_child(a); root.add_child(b); m.register_actor(1,a,1,"turbofit"); m.register_actor(2,b,1,"ice_mage")
		m.configure_defense(load("res://scripts/core/combat/defense_profile.gd").new())
		m.reset({1:Vector3(0,3.5,0),2:Vector3.ZERO})
		a.runtime.air_jumps_left = 0; a.runtime.recovery_spent = true
		m.fighters[1].defense.air_charges = 0
		var head := false; var landed := false; var checks_on_head := 0
		for i in 150:
			await step(m)
			for j in a.get_slide_collision_count():
				var c = a.get_slide_collision(j)
				for k in c.get_collision_count():
					if c.get_collider(k) == b and c.get_normal(k).y > 0.7: head = true
			if head and checks_on_head == 0:
				await step(m,{1:press(aim,"attack")})
				check(m.kit_telemetry(1).basic.clip == ("AirDownKick" if aim == Vector2.DOWN else "AirSideKick"),"physical head selects aerial episode")
				checks_on_head += 1
			elif head and checks_on_head < 4 and not a.runtime.grounded:
				check(m.kit_telemetry(1).basic.active,"body head never cancels aerial episode")
				check(a.runtime.air_jumps_left == 0 and a.runtime.recovery_spent and m.fighters[1].defense.air_charges == 0,"head never refunds jump/recovery/dodge")
				check(a.runtime._landing_left == 0,"head has no terrain landing recovery")
				checks_on_head += 1
			if head and a.runtime.grounded:
				landed = true
				check(a.runtime.air_jumps_left > 0 and not a.runtime.recovery_spent and m.fighters[1].defense.air_charges > 0,"real pass-through terrain refreshes resources")
				check(not m.kit_telemetry(1).basic.active,"real landing cancels aerial episode before contacts")
				break
		check(head and landed and checks_on_head == 4,"nonvacuous head to real terrain transition")
		a.free(); b.free()
	floor.free()
	if not failures: print("PASS body landing (%d checks)" % checks)
	quit(1 if failures else 0)
