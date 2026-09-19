extends "res://tests/test_core_recovery_acceptance.gd"
func run():
	for character in ["teknium","turbofit"]:
		var m = Match.new(); var a = Actor.new(); var b = Actor.new()
		root.add_child(a); root.add_child(b); m.register_actor(1,a,-1,character); m.register_actor(2,b)
		var spawns := {1:Vector3(0,20,0),2:Vector3(1.1,20,0)}
		check(m.reset_with_collision_profiles(spawns,{1:load("res://data/collision/generated/"+character+".tres"),2:load("res://data/collision/generated/teknium.tres")}),"actual source clock profiles")
		a.runtime.grounded = true; await step(m,{1:press(Vector2.RIGHT,"attack")})
		var before: Dictionary = m.collision_telemetry(1)
		var visible = load("res://assets/"+character+"/"+character+"_animations.glb").instantiate(); root.add_child(visible)
		visible.get_node("AnimationPlayer").play("Punch" if character == "teknium" else "MeleeHorizontal")
		for i in 4: await physics_frame
		check(m.collision_telemetry(1) == before and m.fighters[2].percent == 0,"render-only frames cannot move physical attack clock")
		visible.free()
		m.fighters[1].hitstop_left = 4; m.fighters[2].hitstop_left = 4
		for i in 4:
			await step(m)
			check(m.collision_telemetry(1).pose_request == before.pose_request and m.events.is_empty(),"joint stopped startup stays harmless and exact")
		var impacts := 0
		for age in 35:
			await step(m)
			for event in m.events:
				if event.source == 1: impacts += 1
		check(impacts == 1,"resumed physical source lands once "+character)
		m.reset(spawns); a.runtime.grounded = true
		await step(m,{1:press(Vector2.RIGHT,"attack")})
		m.set_enabled(1,false)
		for i in 35: await step(m)
		check(m.fighters[2].percent == 0,"disable retires pending source contact")
		a.free(); b.free()
	if not failures: print("PASS: melee match clock and interruption (%d checks)" % checks)
	quit(1 if failures else 0)
