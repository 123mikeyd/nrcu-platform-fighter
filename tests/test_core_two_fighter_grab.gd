extends "res://tests/test_core_recovery_acceptance.gd"
const Grab = preload("res://scripts/core/combat/grab_ability.gd")
const Queries = preload("res://scripts/core/collision/hurtbox_queries.gd")
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a); m.register_actor(2,b)
	for character in ["teknium","turbofit"]:
		check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(1.3,20,0)},{1:load("res://data/collision/generated/teknium.tres"),2:load("res://data/collision/generated/"+character+".tres")}),"actual profiles")
		await step(m)
		var positive := Vector3.INF; var disagreement := 0
		var g = Grab.new(1,"grab")
		var point: Vector3 = a.global_position+Grab.sample("GrabStart",13.0/24,1)
		for xi in range(9,18,2):
			for yi in range(-5,6,2):
				b.global_position = a.global_position+Vector3(xi*.1,yi*.1,0)
				m._commit_collision_poses([1,2])
				var record: Dictionary = m.collision_telemetry(2).contact_snapshot
				var expected := not Queries.earliest_contact(point,point,.18,record.primitives).is_empty()
				var actual: int = g.closest(1,m.fighters,m.tick)
				if (actual == 2) != expected: disagreement += 1
				if expected and positive == Vector3.INF: positive = b.global_position
		check(disagreement == 0,"Grab compares actual committed limbs not native capsule "+character+" mismatches="+str(disagreement))
		check(positive != Vector3.INF,"actual generated capture fixture exists "+character)
		if positive == Vector3.INF: continue
		b.global_position = positive; m._commit_collision_poses([1,2])
		m.fighters[1].grab = Grab.new(1,"lifecycle")
		m.fighters[1].grab.age = 11
		m._advance_grab(1)
		check(m.fighters[2].caught_by == 1,"real capture relation "+character)
		if m.fighters[2].caught_by == 1:
			var captures: Array = m.ability_events.filter(func(e): return e.kind == "grab_capture")
			check(captures.size() == 1 and captures[0].get("geometry_mode","") == "generated_hurtboxes","capture evidence "+character)
			var held = m.fighters[1].grab
			var held_time: float = held.elapsed
			m.fighters[1].hitstop_left = 2
			await step(m)
			check(held.elapsed == held_time and m.fighters[2].caught_by == 1,"joint hitstop preserves generated capture clock")
			held.phase = "hold"; held.elapsed = 0.0
			for i in 15: m._advance_grab(1)
			check(m.fighters[2].percent == 2,"captured generated victim receives periodic relation damage without re-query")
			m.set_enabled(1,false)
			check(m.fighters[2].caught_by == 0 and b.get_collision_exceptions().is_empty(),"disable releases actual generated capture")
	a.free(); b.free()
	if not failures: print("PASS: two fighter grab (%d checks)" % checks)
	quit(1 if failures else 0)
