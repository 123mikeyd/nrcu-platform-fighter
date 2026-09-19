extends "res://tests/test_core_body_profile_ledge.gd"
func run():
	for large in [false,true]:
		var height = 2.8 if large else 1.0
		var floor_node = block(Vector3(0,-0.5,0),Vector3(30,1,4))
		var platform = block(Vector3(0,1.6,0),Vector3(4,0.2,4))
		platform.add_to_group("core_pass_through"); platform.set_meta("top_y",1.7)
		var a = Actor.new(); a.configure_body_profile(body_profile(0.6 if large else 0.25,height)); root.add_child(a)
		a.reset_at(Vector3.ZERO)
		for i in 15: await physics_frame; a.simulate({})
		await physics_frame; a.simulate({"jump":true,"jump_held":true})
		var crossed := false
		for i in 100:
			await physics_frame; a.simulate({"jump_held":true})
			crossed = crossed or a.position.y > 1.75
		check(crossed and a.runtime.grounded and absf(a.position.y-1.7)<0.04, "unequal body jumps through and lands on native one-way platform")
		await physics_frame; a.simulate({"down":true})
		for i in 60: await physics_frame; a.simulate({})
		check(a.runtime.grounded and absf(a.position.y)<0.04, "unequal profile drop preserves foot-origin policy")
		a.remove_collision_exception_with(platform)
		platform.free()
		var roof = block(Vector3(0,height+2.05,0),Vector3(4,0.1,4))
		a.reset_at(Vector3(0,1,0)); a.runtime.air_jumps_left=0; a.runtime.recovery_spent=true
		a.apply_combat_launch(Vector3(0,10,0),60)
		var ceiling := false
		for i in 20:
			await physics_frame; a.simulate({})
			ceiling = ceiling or a.is_on_ceiling()
			check(a.runtime.air_jumps_left == 0 and a.runtime.recovery_spent, "ceiling never refunds resources")
		check(ceiling, "native profile-derived ceiling contact prerequisite")
		a.free(); roof.free(); floor_node.free()
	if not failures: print("PASS body profile terrain (%d checks)" % checks)
	quit(1 if failures else 0)
