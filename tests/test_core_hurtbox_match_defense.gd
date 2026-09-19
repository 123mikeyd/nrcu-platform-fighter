extends "res://tests/test_core_defense_match.gd"
func run():
	var floor = floor_body(); var p = DefenseProfile.new(); p.shield_drain = 0; p.shield_regen = 0
	var m = setup_match(p); m.configure_actor_kit(1,"turbofit")
	check(m.reset_with_collision_profiles({1:Vector3(0,.01,0),2:Vector3(2,.01,0)},{1:load("res://data/collision/generated/turbofit.tres"),2:load("res://data/collision/generated/teknium.tres")}),"finite defense generated install")
	var blocked := false
	for xi in range(20,51):
		m.reset({1:Vector3(0,.01,0),2:Vector3(xi*.05,.01,0)})
		await settle(m)
		check(m.fighters[2].actor.runtime.grounded,"real grounded defense prerequisite")
		m.fighters[1].actor.reset_at(Vector3(0,1,0))
		await tick(m,{1:frame(true,1),2:shield(true)})
		for i in 9: await tick(m,{2:shield()})
		if m.defense_telemetry(2).shield_health < 100:
			blocked = true
			check(m.fighters[2].percent == 0 and m.defense_telemetry(2).shield_health == 84,"generated aerial contact spends exact 14+2 shield without damage")
			check(m.events.size() == 1 and m.events[0].get("geometry_mode","") == "generated_hurtboxes","shield blocks actual generated capsule contact")
			for i in 3: await tick(m,{2:shield()})
			check(m.defense_telemetry(2).shield_health == 84,"generated limb duplicates cannot spend shield twice")
			print("GENERATED SHIELD separation=",xi*.05)
			break
	check(blocked,"real generated aerial finite shield tracer exists")
	cleanup(m); floor.free()
	if not failures: print("PASS: hurtbox match defense (%d checks)" % checks)
	quit(1 if failures else 0)
