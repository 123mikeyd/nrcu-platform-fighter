extends "res://tests/test_core_recovery_acceptance.gd"
const DefenseProfile = preload("res://scripts/core/combat/defense_profile.gd")
func run():
	await exact_frozen_wave()
	for mode in ["null", "legacy", "finite"]:
		for victim_kit in ["teknium", "turbofit"]:
			await frozen_wave(mode, victim_kit)
			await stopped_shield(mode, victim_kit, false)
			await stopped_shield(mode, victim_kit, true)
			await caught_gate(mode, victim_kit)
		for source_kit in ["teknium", "turbofit"]:
			for victim_kit in ["teknium", "turbofit"]:
				for status in ["frozen", "hitstun", "disabled"]:
					await status_gate(mode, source_kit, victim_kit, status)
	if not failures: print("PASS: turbo match frozen legacy (%d checks)" % checks)
	quit(1 if failures else 0)
func exact_frozen_wave():
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"turbofit"); m.register_actor(2,b,-1,"teknium")
	m.reset({1:Vector3(0,20,0),2:Vector3(3,20,0)})
	m.set_frozen(2,true)
	var block = Frame.new(); block.held.shield = true
	await step(m,{1:press(Vector2.RIGHT),2:block})
	var absorbed := false
	for i in 20:
		await step(m,{2:block})
		for event in m.ability_events:
			if event.kind == "shield_absorb": absorbed = true
	check(m.fighters[2].percent == 11, "frozen Teknium takes exactly 11 Wave damage")
	check(not m.fighters[2].shield_command, "frozen Teknium cannot commit new shield")
	check(not absorbed, "frozen Teknium never emits shield_absorb")
	a.free(); b.free()
func setup(mode: String, source_kit: String, victim_kit: String):
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,source_kit); m.register_actor(2,b,-1,victim_kit)
	if mode != "null":
		var p = DefenseProfile.new(); p.policy_id = mode; p.shield_drain = 0; p.shield_regen = 0
		m.configure_defense(p)
	m.reset({1:Vector3(0,20,0),2:Vector3(3,20,0)})
	return m
func cleanup(m):
	for f in m.fighters.values(): f.actor.free()
func block():
	var f = Frame.new(); f.held.shield = true; return f
func frozen_wave(mode: String, victim_kit: String):
	var m = setup(mode, "turbofit", victim_kit)
	m.set_frozen(2,true)
	await step(m,{1:press(Vector2.RIGHT),2:block()})
	var absorbed := false
	for i in 20:
		await step(m,{2:block()})
		for event in m.ability_events:
			if event.kind == "shield_absorb": absorbed = true
	var label = mode+"/"+victim_kit
	check(m.fighters[2].percent == 11 and not absorbed, label+": frozen Wave deals 11, no absorption")
	check(not m.fighters[2].shield_command, label+": frozen held shield is not committed")
	check(m.fighters[2].actor.runtime.states.status == "frozen", label+": damage preserves freeze")
	cleanup(m)
func status_gate(mode: String, source_kit: String, victim_kit: String, status: String):
	var m = setup(mode, source_kit, victim_kit)
	var b = m.fighters[2].actor
	if status == "frozen": m.set_frozen(2,true)
	elif status == "hitstun": b.apply_combat_launch(Vector3.ZERO,10)
	else: m.set_enabled(2,false)
	await step(m,{2:block()})
	var label = "%s/%s/%s/%s" % [mode,source_kit,victim_kit,status]
	check(not m.fighters[2].shield_command, label+": status rejects fresh shield")
	check(b.runtime.states.status == status, label+": authoritative status retained")
	if mode == "finite": check(m.fighters[2].defense.state != "shield", label+": no finite shield")
	cleanup(m)
func caught_gate(mode: String, victim_kit: String):
	var m = setup(mode,"teknium",victim_kit)
	m.reset({1:Vector3(0,100,0),2:Vector3(1,100,0)})
	await step(m,{1:press(Vector2.ZERO)})
	for i in 11: await step(m)
	check(m.fighters[2].caught_by == 1, mode+"/"+victim_kit+": actual grab establishes caught")
	await step(m,{2:block()})
	check(not m.fighters[2].shield_command, mode+"/"+victim_kit+": caught cannot shield")
	if mode == "finite": check(m.fighters[2].defense.state != "shield", "caught finite shield remains off")
	cleanup(m)
func stopped_shield(mode: String, victim_kit: String, committed: bool):
	var floor_body = StaticBody3D.new(); var shape = CollisionShape3D.new(); var box = BoxShape3D.new()
	box.size = Vector3(40,1,6); shape.shape = box; floor_body.add_child(shape); floor_body.position.y = -0.5; root.add_child(floor_body)
	var m = setup(mode,"turbofit",victim_kit)
	m.reset({1:Vector3(0,.01,0),2:Vector3(8,.01,0)})
	for i in 12: await step(m)
	await step(m,{2:block()} if committed else {})
	check(m.fighters[2].shield_command == committed, "shield commitment fixture")
	await step(m,{1:press(Vector2.RIGHT),2:block()} if committed else {1:press(Vector2.RIGHT)})
	var shot: Dictionary = m.projectile_telemetry()[0]
	var b = m.fighters[2].actor
	b.position = shot.position + Vector3(.85,-1,0)
	m.fighters[2].hitstop_left = 3
	var local_tick: int = b.runtime.tick
	var world_tick: int = m.tick
	# Release cannot erase a committed shield during stop; fresh hold cannot create one.
	await step(m,{} if committed else {2:block()})
	var absorbed := false
	for event in m.ability_events:
		if event.kind == "shield_absorb": absorbed = true
	var label = "%s/%s/committed=%s" % [mode,victim_kit,committed]
	check(m.fighters[2].percent == (0 if committed else 11), label+": Wave damage respects pre-stop shield")
	check(absorbed == committed, label+": absorption respects pre-stop shield")
	check(m.fighters[2].shield_command == committed, label+": held input cannot rewrite stopped command")
	check(b.runtime.tick == local_tick and m.tick == world_tick+1, label+": local clock paused, world clock advances")
	if committed and mode == "finite": check(m.fighters[2].defense.snapshot().shield_health == 87, "stopped finite shield spends Wave 11+2 once")
	cleanup(m); floor_body.free()
