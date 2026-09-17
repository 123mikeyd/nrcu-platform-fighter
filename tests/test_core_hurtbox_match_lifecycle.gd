extends "res://tests/test_core_recovery_acceptance.gd"
func active_hit(m):
	var before: float = m.fighters[2].percent
	await step(m,{1:press(Vector2.RIGHT,"attack")})
	check(not m.fighters[1].activation_id.is_empty(),"real input activation prerequisite")
	check(m.fighters[2].percent == before,"no startup damage")
	var impact_age := -1
	for age in range(1,12): # Imported Punch source window .6..8 seconds.
		await step(m)
		if m.fighters[2].percent > before:
			impact_age = age
			break
	check(impact_age >= 9 and impact_age <= 11,"actual hand window reached for fresh damage")
	check(not m.events.is_empty() and m.events[0].contact_evidence.has("attack_shape"),"independent source shape hit prerequisite")
func run():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a); m.register_actor(2,b,-1,"turbofit")
	var profiles := {1:load("res://data/collision/generated/teknium.tres"),2:load("res://data/collision/generated/turbofit.tres")}
	var spawns := {1:Vector3(0,30,0),2:Vector3(1.1,30,0)}
	check(m.reset_with_collision_profiles(spawns,profiles),"lifecycle install")
	await active_hit(m)
	check(m.fighters[2].percent > 0,"real first active-hand hit on generated actor")
	check(m.collision_telemetry(2).get("pose_request",{}).get("clip","") == "HitReactRight","same-tick canonical post-contact pose")
	check(m.collision_telemetry(2).get("contact_snapshot",{}).get("pose_request",{}).get("clip","") != "HitReactRight","pre-contact evidence retained separately")
	await step(m)
	var first: Dictionary = m.collision_telemetry(2)
	check(first.get("ok",false),"first committed hit pose")
	for i in 40: await step(m)
	# Safe separated placement for a second real attack, same life and source.
	a.global_position = Vector3(0,30,0); b.global_position = Vector3(1.1,30,0)
	a.runtime.velocity = Vector3.ZERO; b.runtime.velocity = Vector3.ZERO
	await active_hit(m)
	await step(m)
	var second: Dictionary = m.collision_telemetry(2)
	check(second.get("ok",false),"second committed hit pose")
	check(first.get("pose_request",{}).get("episode_id",[]) != second.get("pose_request",{}).get("episode_id",[]),"new same-life actual hit has distinct episode")
	check(str(first.get("pose_request",{}).get("episode_id",[])).contains("hit:"),"hit identity is match event not fallback initial")
	var generation: int = m.generation
	var invalid: Resource = profiles[2].duplicate(true); invalid.source_sha256 = "bad"
	check(not m.reset_with_collision_profiles(spawns,{2:invalid}),"invalid profile rejected")
	check(m.generation == generation and m.collision_telemetry(2) == second,"failed install is atomic")
	var missing: Resource = profiles[2].duplicate(true); missing.hurtboxes[0].bone_name = "MissingImportedBone"
	check(not m.reset_with_collision_profiles(spawns,{2:missing}),"missing imported bone rejected before full reset")
	check(m.generation == generation,"missing pose rejection leaves generation intact")
	m.reset_with_collision_profiles(spawns,profiles)
	await step(m,{1:press(Vector2.RIGHT,"special")})
	for i in 6: await step(m)
	check(m.fighters[1].force != null,"real Force accepted")
	if m.fighters[1].force != null:
		var force = m.fighters[1].force
		check(is_equal_approx(m.collision_telemetry(1).pose_request.source_seconds,force.source_time(force.age/60.0)),"host uses real Force source-time mapping")
	m.reset(spawns)
	check(not m.collision_telemetry(2).get("ok",true),"ordinary reset invalidates pose")
	await step(m)
	var moving: Dictionary = m.collision_telemetry(2)
	for i in 4: await step(m)
	var later: Dictionary = m.collision_telemetry(2)
	check(moving.primitives != later.primitives,"actual imported falling limbs move under committed clock")
	var paused: Dictionary = m.collision_telemetry(2)
	var visible: Node3D = load("res://assets/turbofit/turbofit_animations.glb").instantiate()
	root.add_child(visible)
	visible.get_node("AnimationPlayer").play("AirDownKick")
	for i in 3: await physics_frame
	check(paused == m.collision_telemetry(2),"visible autonomous source cannot advance host")
	visible.hide()
	for i in 3: await physics_frame
	check(paused == m.collision_telemetry(2),"hidden renderer cannot advance host")
	visible.free()
	for i in 3: await physics_frame
	check(paused == m.collision_telemetry(2),"host pause never reads render clock")
	await step(m)
	check(paused != m.collision_telemetry(2),"explicit one-frame advance changes pose")
	m.fighters[2].hitstop_left = 3
	var before_stop: Dictionary = m.collision_telemetry(2)
	for i in 3: await step(m)
	check(before_stop.primitives == m.collision_telemetry(2).primitives and before_stop.pose_request == m.collision_telemetry(2).pose_request,"hitstop freezes complete moving limb pose")
	var detached: Dictionary = m.collision_telemetry(2); detached.primitives.clear()
	check(not m.collision_telemetry(2).primitives.is_empty(),"read-only telemetry copy")
	m.set_enabled(2,false); check(not m.collision_telemetry(2).ok,"disable immediate invalidation")
	m.set_enabled(2,true); await step(m)
	check(m.collision_telemetry(2).ok,"reenable creates fresh valid pose")
	m._clean_life(2,spawns[2]); check(not m.collision_telemetry(2).ok,"stock life invalidates synchronously")
	a.free(); b.free()
	if not failures: print("PASS: hurtbox match lifecycle (%d checks)" % checks)
	quit(1 if failures else 0)
