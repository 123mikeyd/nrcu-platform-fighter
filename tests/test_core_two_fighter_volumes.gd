extends "res://tests/test_core_recovery_acceptance.gd"
const Special = preload("res://scripts/core/kits/turbofit_specials.gd")
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a); m.register_actor(2,b)
	for character in ["teknium","turbofit"]:
		check(m.reset_with_collision_profiles({1:Vector3(0,20,0),2:Vector3(1,20,0)},{1:load("res://data/collision/generated/teknium.tres"),2:load("res://data/collision/generated/"+character+".tres")}),"actual profiles")
		for source_kit in ["teknium","turbofit"]:
			m.configure_actor_kit(1,source_kit)
			m.reset({1:Vector3(0,20,0),2:Vector3(1,20,0)})
			await step(m,{1:press()})
			check(m.fighters[2].percent == 12,"recovery actual limb hit "+source_kit+character)
			check(not m.events.is_empty(),"recovery event exists")
			if not m.events.is_empty(): check(m.events[0].get("geometry_mode","") == "generated_hurtboxes","recovery generated evidence "+source_kit+character)
			m.reset({1:Vector3(0,20,0),2:Vector3(1,20,0)})
			var recovery = preload("res://scripts/core/combat/recovery_ability.gd").new(1,"last-window")
			recovery.age = 22; m.fighters[1].recovery = recovery
			await step(m)
			check(m.fighters[2].percent == 12 and m.fighters[1].recovery == null,"actual recovery final crossing interval retained "+source_kit+character)
			m.fighters[2].percent = 0
			await step(m)
			check(m.fighters[2].percent == 0,"expired generated recovery cannot hit")
		m.reset({1:Vector3(0,20,0),2:Vector3(.6,20,0)})
		await step(m)
		var target: Dictionary = m._kit_targets(1)[1]
		target.hurtbox_snapshot = {"ok":false,"primitives":[]}
		target.position = a.global_position+Vector3(.3,0,0)
		var special = Special.new(); special.start("orb-invalid",Vector2.DOWN,1)
		check(special.collect(1,a.global_position,[target]).is_empty(),"Orb invalid snapshot fail closed "+character)
		target = m._kit_targets(1)[1]
		var center: Vector3 = target.hurtbox_snapshot.primitives[0].a
		target.position = center+Vector3(100,100,100)
		special = Special.new(); special.start("orb-hit",Vector2.DOWN,1)
		var hits: Array = special.collect(1,center,[target])
		check(hits.size() == 1,"Orb actual limb hit independent of origin "+character)
		if not hits.is_empty(): check(hits[0].get("geometry_mode","") == "generated_hurtboxes","Orb evidence")
		check(special.collect(1,center,[target]).is_empty(),"Orb once/victim")
	a.free(); b.free()
	if not failures: print("PASS: two fighter volumes (%d checks)" % checks)
	quit(1 if failures else 0)
