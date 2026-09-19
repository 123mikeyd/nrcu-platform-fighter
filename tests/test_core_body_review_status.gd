extends "res://tests/test_core_ledge_match.gd"
func run():
	for reverse in [false,true]:
		for facing in [-1,1]:
			for continuation in [false,true]:
				for status in ["frozen","caught","disabled","stopped","normal","launch"]:
					var terrain = body(Vector3(0,-0.5,0),Vector3(40,1,4))
					var m = load("res://scripts/core/match/match_simulation.gd").new()
					for id in ([2,1] if reverse else [1,2]):
						var actor = Actor.new(); actor.profile = load("res://data/characters/teknium_movement.tres")
						root.add_child(actor); m.register_actor(id,actor)
					m.reset({1:Vector3(0,3.5,0),2:Vector3.ZERO}); m.fighters[1].facing = facing
					var a = m.fighters[1].actor; var b = m.fighters[2].actor
					var head = false
					for i in 90:
						await tick(m)
						for j in a.get_slide_collision_count():
							var c = a.get_slide_collision(j)
							for k in c.get_collision_count():
								if c.get_collider(k) == b and c.get_normal(k).y > 0.7: head = true
						if head: break
					check(head,"real head contact prerequisite")
					if continuation: await tick(m)
					if status == "frozen": m.set_frozen(1,true)
					if status == "disabled": m.set_enabled(1,false)
					if status == "stopped": m.fighters[1].hitstop_left = 10
					if status == "launch": a.apply_combat_launch(Vector3(-5,0,0),30)
					# Direct actor seam isolates caught priority without forging a grab relation.
					if status == "caught": a.runtime.reconcile_status(true,false,true)
					var at: Vector3 = a.position; var clock = a.runtime.tick
					if status == "caught":
						await physics_frame; a.simulate({})
					else: await tick(m)
					if status in ["frozen","caught","disabled","stopped"]:
						check(absf(a.position.x-at.x) < 0.001,"%s head priority reverse=%s facing=%s continuation=%s" % [status,reverse,facing,continuation])
						if status == "frozen": check(absf(a.velocity.x) < 0.001,"freeze has no injected horizontal speed")
					elif status == "normal": check(a.position.x > at.x,"normal centered head still slips world +X")
					else: check(a.velocity.x < -1.5,"strong external launch retains direction and speed")
					check(a.runtime.tick == clock + (0 if status in ["stopped","disabled"] else 1),"exact actor clock policy")
					cleanup(m); terrain.free()
	if not failures: print("PASS body review status (%d checks)" % checks)
	quit(1 if failures else 0)
