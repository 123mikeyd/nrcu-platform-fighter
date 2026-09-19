extends "res://tests/test_core_recovery_acceptance.gd"
const Special = preload("res://scripts/core/kits/turbofit_specials.gd")
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b)
	for character in ["teknium","turbofit"]:
		check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(2,20,0)},{1:load("res://data/collision/generated/turbofit.tres"),2:load("res://data/collision/generated/"+character+".tres")}),"actual profiles")
		await step(m)
		var target: Dictionary = m._kit_targets(1)[1]
		# A generated snapshot is authoritative, even when the old origin hits.
		target.hurtbox_snapshot = {"ok":false,"primitives":[]}
		var special = Special.new()
		special.start("invalid",Vector2.ZERO,1)
		special.tick(.1,{"held":false})
		check(special.collect(1,a.global_position,[target]).is_empty(),"Chord invalid generated snapshot cannot fall back to origin "+character)
		# Valid limb geometry can hit independently of the legacy origin field.
		target = m._kit_targets(1)[1]
		target.position = Vector3(100,100,100)
		special = Special.new(); special.start("limb",Vector2.ZERO,1); special.tick(.1,{"held":false})
		var hits: Array = special.collect(1,a.global_position,[target])
		check(hits.size() == 1,"Chord actual limb hit ignores legacy origin "+character)
		if not hits.is_empty(): check(hits[0].get("geometry_mode","") == "generated_hurtboxes","Chord evidence mode")
		for clip in ["MeleeHorizontal","MeleeBackhand","GoalkeeperKick"]:
			m.configure_actor_kit(1,"turbofit")
			check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(10,20,0)},{1:load("res://data/collision/generated/turbofit.tres"),2:load("res://data/collision/generated/"+character+".tres")}),"isolated real physical source")
			a.runtime.grounded = true; m.fighters[1].facing = 1
			await step(m,{1:press(Vector2.UP if clip == "MeleeBackhand" else (Vector2.DOWN if clip == "GoalkeeperKick" else Vector2.RIGHT),"attack")})
			var basic = m.fighters[1].kit.basic
			check(basic.clip == clip and not basic.activation_id.is_empty(),"invalid test actual activation "+clip)
			check(basic.source_shapes.is_empty(),"invalid test real startup "+clip)
			var first: int = {"MeleeHorizontal":17,"MeleeBackhand":10,"GoalkeeperKick":23}[clip]
			for age in range(1,first+1): await step(m)
			check(not basic.source_shapes.is_empty(),"invalid test active hand/foot prerequisite "+clip)
			if basic.source_shapes.is_empty(): continue
			target = m._kit_targets(1)[1]
			target.hurtbox_snapshot = target.hurtbox_snapshot.contact_snapshot.duplicate(true)
			var delta: Vector3 = basic.source_shapes[0].a-target.hurtbox_snapshot.primitives[0].a
			for capsule in target.hurtbox_snapshot.primitives: capsule.a += delta; capsule.b += delta
			target.position = a.global_position+Vector3(0,1,0) if clip == "MeleeBackhand" else a.global_position+Vector3(1,0,0)
			var positive := target.duplicate(true)
			target.hurtbox_snapshot = {"ok":false,"primitives":[]}
			check(basic.contacts(1,a.global_position,[target]).is_empty(),clip+" invalid snapshot fails closed "+character)
			var physical_hits: Array = basic.contacts(1,a.global_position,[positive])
			check(physical_hits.size() == 1,"independent active-source positive control "+clip+character)
		for move in ["side_strike","air_strike","uppercut","up_air","low_sweep","down_strike"]:
			var definition = load("res://data/moves/"+move+".tres")
			var direction: Vector3 = definition.query_direction(1)
			m.configure_actor_kit(1,"teknium")
			check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(1.1,20,0)},{1:load("res://data/collision/generated/teknium.tres"),2:load("res://data/collision/generated/"+character+".tres")}),"physical source matches actual Teknium kit")
			# Punch/Kick assets extend forward, including directional-labelled routes.
			m.fighters[1].facing = 1
			# Selection is isolated from terrain; the input still runs the real match.
			a.runtime.grounded = move in ["side_strike","uppercut","low_sweep"]
			var aim := Vector2(direction.x,-direction.y)
			await step(m,{1:press(aim,"attack")})
			check(m.fighters[1].move_id == definition.move_id,"real selection "+move)
			check(not m.fighters[1].activation_id.is_empty(),"buffered attack activation prerequisite "+move)
			check(m.events.is_empty(),"source startup inactive "+move)
			var first_age := 8 if move in ["low_sweep","down_strike"] else 9
			var last_age := 10 if first_age == 8 else 11
			var impacts := 0
			for age in range(1,last_age+1):
				await step(m)
				for event in m.events:
					if event.source == 1:
						impacts += 1
						check(age >= first_age,"source window prerequisite "+move)
						check(event.get("geometry_mode","") == "generated_hurtboxes","Teknium generated limb evidence "+move+character)
						check(event.contact_evidence.has("attack_shape"),"actual hand/foot source evidence "+move)
			check(impacts == 1,"real generated physical positive once "+move+character)
	a.free(); b.free()
	if not failures: print("PASS: two fighter cones (%d checks)" % checks)
	quit(1 if failures else 0)
