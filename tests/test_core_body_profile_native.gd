extends "res://tests/test_core_body_profile_head.gd"
func run():
	for reverse in [false,true]:
		for tall_mover in [false,true]:
			for status in ["normal","frozen","caught","disabled","stopped","launch"]:
				var floor_node = floor_body(); var m = Match.new(); var a = Actor.new(); var b = Actor.new()
				a.configure_body_profile(body_profile(0.6 if tall_mover else 0.2,2.8 if tall_mover else 0.6))
				b.configure_body_profile(body_profile(0.2 if tall_mover else 0.6,0.6 if tall_mover else 2.8))
				root.add_child(a); root.add_child(b)
				if reverse: m.register_actor(2,b); m.register_actor(1,a)
				else: m.register_actor(1,a); m.register_actor(2,b)
				m.reset({1:Vector3(0,5,0),2:Vector3.ZERO})
				a.runtime.air_jumps_left = 0; a.runtime.recovery_spent = true
				var head := false
				for i in 90:
					await step(m)
					for j in a.get_slide_collision_count():
						var c = a.get_slide_collision(j)
						for k in c.get_collision_count():
							if c.get_collider(k) == b and c.get_normal(k).y > 0.7: head = true
					if head: break
				check(head, "native head prerequisite both body sizes and registration orders")
				check(not a.runtime.grounded and a.runtime.air_jumps_left == 0 and a.runtime.recovery_spent, "no head resource refresh")
				if status == "frozen": m.set_frozen(1,true)
				if status == "disabled": m.set_enabled(1,false)
				if status == "caught": a.runtime.reconcile_status(true,false,true)
				if status == "stopped": m.fighters[1].hitstop_left = 3
				if status == "launch": a.apply_combat_launch(Vector3(-5,0,0),30)
				var at = a.position; var clock = a.runtime.tick
				if status == "caught": await physics_frame; a.simulate({})
				else: await step(m)
				if status in ["frozen","caught","disabled","stopped"]: check(absf(a.position.x-at.x) < 0.001, "unequal head escape veto: " + status)
				elif status == "normal": check(a.position.x > at.x, "normal unequal head slip")
				else: check(a.velocity.x < -1.5, "unequal body stronger launch retained")
				check(a.runtime.tick == clock + (0 if status in ["disabled","stopped"] else 1), "exact status clock")
				a.free(); b.free(); floor_node.free()
	# Legal native blocking, finite hitstop occupancy and terrain-only landing.
	for large in [false,true]:
		for direction in [-1,1]:
			var floor_node = floor_body(); var m = Match.new(); var a = Actor.new(); var b = Actor.new()
			a.configure_body_profile(body_profile(0.6 if large else 0.25,2.8 if large else 1.0))
			b.configure_body_profile(body_profile(0.25 if large else 0.6,1.0 if large else 2.8))
			root.add_child(a); root.add_child(b); m.register_actor(1,a); m.register_actor(2,b)
			m.reset({1:Vector3(-3*direction,0.1,0),2:Vector3(0,0.1,0)})
			for i in 12: await step(m)
			check(a.runtime.grounded and b.runtime.grounded, "both dimensions settle on native terrain")
			var shape = b.get_node("CoreCapsule").shape
			m.fighters[2].hitstop_left = 80
			var at = b.position; var clock = b.runtime.tick; var contacts := 0; var crossed := false
			var f = Frame.new(); f.axis.x = direction
			for i in 60:
				await step(m,{1:f})
				crossed = crossed or (a.position.x-b.position.x)*direction > 0
				for j in a.get_slide_collision_count():
					if a.get_slide_collision(j).get_collider() == b: contacts += 1
			check(contacts > 0 and not crossed, "unequal native side blocking against stopped body")
			check(b.position == at and b.runtime.tick == clock and b.get_node("CoreCapsule").shape == shape, "hitstop retains exact geometry position and clock")
			check(a.position.z == 0 and b.position.z == 0, "no depth escape")
			a.free(); b.free(); floor_node.free()
	if not failures: print("PASS body profile native (%d checks)" % checks)
	quit(1 if failures else 0)
