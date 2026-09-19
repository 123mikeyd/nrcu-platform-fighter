extends "res://tests/test_core_top_support_lifecycle.gd"
func run():
	for reverse in [false,true]:
		var f = setup_pair("teknium","turbofit",reverse,"auto")
		var spawns = {1:Vector3(-0.12,0,0),2:Vector3(0.12,0,0)}
		for state in ["frozen","disabled","hitstop","exception","caught","grab"]:
			f.m.reset(spawns)
			for i in 5: await step(f.m)
			# Legal terrain contact first, then a bounded synthetic overlap to isolate exclusion.
			f.a.position.x = -0.12; f.b.position.x = 0.12
			if state == "frozen": f.m.set_frozen(1,true)
			if state == "disabled": f.m.set_enabled(1,false)
			if state == "hitstop": f.m.fighters[1].hitstop_left = 4
			if state == "exception": f.a.add_collision_exception_with(f.b)
			if state == "caught": f.m.fighters[1].caught_by = 2
			if state == "grab":
				# Real grab object exclusion without advancing an invalid fabricated episode.
				f.m.fighters[1].grab = preload("res://scripts/core/combat/grab_ability.gd").new(1.0,"guard")
			var before = [f.a.position,f.b.position]
			if state in ["caught","grab"]:
				f.m._reconcile_status(1); f.m._advance_ground_jostle([1,2])
			else: await step(f.m)
			check(absf(f.a.position.x-before[0].x)<0.00001 and absf(f.b.position.x-before[1].x)<0.00001,"both endpoints excluded: "+state)
			f.m.fighters[1].caught_by = 0; f.m.fighters[1].grab = null
			f.a.remove_collision_exception_with(f.b)
		check(f.m.fighter_interaction_mode == "grounded_jostle" and f.a.collision_mask == 1 and f.b.collision_mask == 1,"reset retains terrain-only interaction")
		var generation = f.m.generation
		check(not f.m.reset_with_collision_profiles(spawns,{1:fitted("teknium")},"grounded_jostle") and f.m.generation == generation,"partial explicit optin rejected atomically")
		check(not f.m.reset_with_collision_profiles(spawns,{1:fitted("teknium")}) and f.b.collision_mask == 1,"partial auto cannot change untouched active endpoint")
		check(not f.m.reset_with_body_profiles(spawns,{1:null}) and f.b.collision_mask == 1,"partial body reset cannot change untouched active endpoint")
		check(f.m.reset_with_collision_profiles(spawns,{1:fitted("teknium"),2:fitted("turbofit")},"legacy_solid"),"full explicit legacy boundary")
		check(f.m.reset_with_collision_profiles(spawns,{1:fitted("teknium")}),"partial auto compatibility")
		check(f.m.fighter_interaction_mode == "legacy_solid" and f.a.collision_mask == 3 and f.b.collision_mask == 3,"mixed mode symmetric compatibility")
		check(f.m.reset_with_collision_profiles(spawns,{1:fitted("teknium"),2:fitted("turbofit")},"legacy_solid"),"explicit rollback")
		check(not f.m.top_support_telemetry(1).geometry.is_empty(),"legacy head geometry retained")
		f.m.reset({1:Vector3(0,3.0,0),2:Vector3.ZERO})
		await acquire(f)
		check(not f.m.top_support_telemetry(1).relation.is_empty(),"genuine old relation before retirement")
		check(f.m.reset_with_collision_profiles(spawns,{1:fitted("teknium"),2:fitted("turbofit")}),"new mode reentry")
		await step(f.m)
		check(f.m.collision_telemetry(1).pose_request.state != "supported","canonical non-supported pose after migration")
		check(f.m.top_support_telemetry(1).geometry.is_empty() and f.m.top_support.envelopes.is_empty() and f.m.top_support.relations.is_empty(),"retired support caches empty")
		var rules = preload("res://scripts/core/match/match_rules.gd").new()
		rules.stage.spawns = {1:Vector3(-2,0,0),2:Vector3(2,0,0)}
		f.m.configure_rules(rules); f.m.rematch()
		var stocks: int = f.m.fighters[1].stocks
		f.a.position.y = -9; await step(f.m)
		check(f.m.fighters[1].stocks == stocks-1,"actual stock loss in generated jostle mode")
		check(f.a.collision_mask == 1 and f.b.collision_mask == 1,"fresh stock preserves terrain-only movement")
		f.m.rematch(); await step(f.m)
		check(f.m.fighters[1].stocks == stocks and f.m.top_support.relations.is_empty() and f.a.get_collision_exceptions().is_empty(),"rematch clears life/relation state")
		dispose(f)
	if not failures: print("PASS: jostle lifecycle status exclusions and explicit migration")
	quit(1 if failures else 0)
