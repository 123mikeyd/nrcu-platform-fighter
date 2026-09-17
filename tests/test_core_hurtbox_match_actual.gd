extends "res://tests/test_core_recovery_acceptance.gd"
const Queries = preload("res://scripts/core/collision/hurtbox_queries.gd")
const Pose = preload("res://scripts/core/kits/turbofit_contact_pose.gd")
func translated_capsules(primitives: Array, offset: Vector3) -> Array:
	var result := primitives.duplicate(true)
	for c in result: c.a += offset; c.b += offset
	return result
func fixture(m, source: int, victim: int, clip: String, facing: float, want_hit: bool) -> Dictionary:
	var t: Dictionary = m.collision_telemetry(victim)
	if not t.get("ok",false): return {}
	var origin: Vector3 = m.fighters[victim].actor.global_position
	var primitives := translated_capsules(t.primitives,-origin)
	var shape: CollisionShape3D = m.fighters[victim].actor.get_node("CoreCapsule")
	var local_body: Transform3D = shape.global_transform; local_body.origin -= origin
	var k = m.fighters[source].kit.basic
	var sphere: Vector3 = Pose.new().center(clip,k.elapsed,facing)
	var source_shape: CollisionShape3D = m.fighters[source].actor.get_node("CoreCapsule")
	var source_body: Dictionary = Queries.capsule_from_transform("source",source_shape.transform,source_shape.shape.height,source_shape.shape.radius)
	for xi in range(-80,81):
		for yi in range(-80,81):
			var offset := Vector3(xi*.05*facing,yi*.05,0)
			if clip == "AirSideKick" and offset.x*facing <= 0: continue
			if clip == "AirDownKick" and offset.y >= 0: continue
			var moved := local_body; moved.origin += offset
			var body: Dictionary = Queries.capsule_from_transform("body",moved,shape.shape.height,shape.shape.radius)
			var body_hit := Queries.sphere_overlap(sphere,.22,body)
			if clip == "AirSideKick" and body_hit == want_hit: continue
			if absf(offset.x+local_body.origin.x-source_shape.position.x) < source_body.radius+body.radius+.05: continue
			# Legal separated movement bodies: no reciprocal fixture exceptions.
			var nearest := Geometry3D.get_closest_points_between_segments(source_body.a,source_body.b,body.a,body.b)
			if nearest[0].distance_to(nearest[1]) < source_body.radius+body.radius+.02: continue
			var evidence: Dictionary = Queries.earliest_contact(sphere,sphere,.20 if want_hit else .24,translated_capsules(primitives,offset))
			if (not evidence.is_empty()) == want_hit: return {"offset":offset,"body_hit":body_hit,"evidence":evidence}
	return {}
func run():
	var cases := 0
	for target_character in ["teknium","turbofit"]:
		for source in [1,2]:
			var victim: int = 3-source
			for facing in [-1.0,1.0]:
				for reverse in [false,true]:
					for clip in ["AirSideKick","AirDownKick"]:
						var m = Match.new(); var a = Actor.new(); var b = Actor.new()
						root.add_child(a); root.add_child(b)
						var actors := {1:a,2:b}
						for id in ([2,1] if reverse else [1,2]): m.register_actor(id,actors[id],-1,"turbofit" if id == source else "teknium")
						var profiles := {source:load("res://data/collision/generated/turbofit.tres"),victim:load("res://data/collision/generated/"+target_character+".tres")}
						check(m.reset_with_collision_profiles({source:Vector3(0,30,0),victim:Vector3(10,30,0)},profiles),"matrix generated install")
						m.fighters[victim].facing = facing
						var aim := Vector2(facing,1 if clip == "AirDownKick" else 0)
						var ticks := 24 if clip == "AirDownKick" else 10
						await step(m,{source:press(aim,"attack")})
						for i in ticks-1: await step(m)
						var selected_fixtures := [fixture(m,source,victim,clip,facing,true),fixture(m,source,victim,clip,facing,false)]
						var drift: Vector3 = actors[source].global_position-actors[victim].global_position+Vector3(10,0,0)
						for want_hit in [true,false]:
							var selected: Dictionary = selected_fixtures[0 if want_hit else 1]
							check(not selected.is_empty(),"real geometry disagreement exists "+str([target_character,clip,facing,want_hit]))
							if selected.is_empty(): continue
							m.reset({source:Vector3(0,30,0),victim:Vector3(0,30,0)+selected.offset+drift})
							m.fighters[victim].facing = facing
							await step(m,{source:press(aim,"attack")})
							for i in ticks-1: await step(m)
							check(m.fighters[victim].percent == (14 if want_hit else 0),"real generated damage disagreement "+str([target_character,source,facing,reverse,clip,want_hit,selected.offset,m.fighters[victim].percent]))
							var t: Dictionary = m.collision_telemetry(victim)
							check(t.get("ok",false),"committed actual complete target")
							var contact_pose: Dictionary = t.contact_snapshot
							var age := .4 if clip == "AirDownKick" else 5.0/30
							var sphere: Vector3 = actors[source].global_position+Pose.new().center(clip,age,facing)
							check((not Queries.earliest_contact(sphere,sphere,.22,contact_pose.primitives).is_empty()) == want_hit,"actual committed narrowphase agrees with damage")
							if clip == "AirSideKick":
								var shape: CollisionShape3D = actors[victim].get_node("CoreCapsule")
								var body := Queries.capsule_from_transform("body",shape.global_transform,shape.shape.height,shape.shape.radius)
								check(Queries.sphere_overlap(sphere,.22,body) != want_hit,"live body and animated limbs disagree")
							if want_hit:
								check(m.events.size() == 1 and m.events[0].get("geometry_mode","") == "generated_hurtboxes","one authoritative generated event")
								if not m.events.is_empty(): check(m.events[0].get("contact_evidence",{}).get("pose_revision",{}) == contact_pose.pose_revision,"damage evidence retains exact pre-contact pose identity")
								for i in 3: await step(m)
								check(m.fighters[victim].percent == 14,"multi-limb once victim")
							cases += 1
						a.free(); b.free()
	print("ACTUAL CASES ",cases)
	if not failures: print("PASS: hurtbox match actual (%d checks)" % checks)
	quit(1 if failures else 0)
