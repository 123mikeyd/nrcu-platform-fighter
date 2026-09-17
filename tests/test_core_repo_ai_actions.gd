extends "res://tests/test_core_top_support_lifecycle.gd"
const Owner = preload("res://scripts/core/input/repo_ai_match_input.gd")
func run():
	var f = setup_pair("turbofit","teknium",false,"grounded_jostle")
	f.m.configure_defense(load("res://scripts/core/combat/defense_profile.gd").new())
	f.m.reset({1:Vector3(-2,3,0),2:Vector3(2,0,0)})
	var owner = Owner.new(); owner.configure(2,true,"hard")
	var jumped = false
	for i in 35:
		await physics_frame; owner.advance(f.m)
		jumped = jumped or f.b.velocity.y > 1
	check(jumped,"original elevation decision accepts real shared jump")
	# Independent real combat window for defense: each human attack is a legal frame.
	f.m.reset({1:Vector3(-1,0,0),2:Vector3(1,0,0)})
	var shielded = false; var basic = false; var edges = 0
	var previous := false
	for i in 450:
		await physics_frame
		var human = Frame.new(); human.axis.x = 1
		human.held.attack = i % 45 == 0
		if human.held.attack: human.pressed.attack = true
		var frames = owner.sample_all(f.m,{1:human})
		if frames[2].pressed.get("attack",false):
			edges += 1; check(not previous,"no repeated held attack edge")
		previous = frames[2].held.attack
		f.m.simulate(frames)
		shielded = shielded or f.m.fighters[2].shield_command
		basic = basic or f.m.fighters[2].kit.snapshot().basic.active
	# Original hard heuristic needs a nearby cooldown on its fourth decision,
	# while its own kit is unlocked. Isolate that prerequisite with legal input.
	f.m.reset({1:Vector3(14,0,0),2:Vector3.ZERO})
	for i in 20: await physics_frame; owner.advance(f.m)
	check(owner.ai.sequence == 3 and not f.m.fighters[2].kit.locked(),"shield prerequisite: third decision without a self attack")
	f.a.reset_at(f.b.position + Vector3(1.4,0,0))
	var threat = Frame.new(); threat.axis.x = 1; threat.pressed.special = true; threat.held.special = true
	await physics_frame; f.m.simulate(owner.sample_all(f.m,{1:threat}))
	check(f.m.fighters[1].force != null,"human legal special establishes long cooldown")
	for i in 8:
		await physics_frame; owner.advance(f.m)
		shielded = shielded or f.m.fighters[2].shield_command
	check(shielded,"original hard defense reaches committed shared shield")
	check(basic and edges > 1,"repeated basic attack opportunities use real kit cooldown")
	print("AI_ACTIONS jump=",jumped," shield=",shielded," basic=",basic," attack_edges=",edges)
	# Disable/enable is a reset transaction, never an unbuffered ownership swap.
	check(owner.configure(2,false,"easy"),"disable AI")
	f.m.reset({1:Vector3(-2,0,0),2:Vector3(2,0,0)})
	var human = Frame.new(); human.source_id = "human2"
	check(owner.sample_all(f.m,{2:human})[2].source_id == "human2","disabled AI delegates P2")
	check(owner.configure(2,true,"normal"),"enable AI")
	f.m.reset({1:Vector3(-2,0,0),2:Vector3(2,0,0)})
	check(owner.sample_all(f.m)[2].source_id == "repo_ai" and owner.ai.sequence == 1,"enable reset fresh sequence")
	dispose(f)
	if not failures: print("PASS: repo AI real jump basics finite shielding ownership")
	quit(1 if failures else 0)
