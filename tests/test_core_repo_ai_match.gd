extends "res://tests/test_core_top_support_lifecycle.gd"
func run():
	var path = "res://scripts/core/input/repo_ai_match_input.gd"
	check(ResourceLoader.exists(path),"single match input owner exists")
	if failures: quit(1); return
	var f = setup_pair("turbofit","teknium",false,"grounded_jostle")
	f.m.reset({1:Vector3(-2,0,0),2:Vector3(2,0,0)})
	var owner = load(path).new()
	var frames = owner.sample_all(f.m,{1:Frame.new()})
	check(frames[1].source_id != "repo_ai" and frames[2].source_id == "repo_ai","default only P2 AI")
	check(not owner.configure(1,true,"hard"),"P1 remains human")
	check(not owner.configure(2,true,"legendary"),"no fabricated difficulties")
	var sequence = owner.ai.sequence
	owner.sample_all(f.m)
	check(owner.ai.sequence == sequence,"same commit sampled once")
	owner.reset()
	var moved = false; var attacked = false; var damage = false
	for i in 400:
		await physics_frame
		var before = f.m.tick
		check(owner.advance(f.m),"one authoritative commit")
		check(not owner.advance(f.m),"duplicate physics callback rejected")
		check(f.m.tick == before+1,"exactly one simulation tick")
		moved = moved or f.b.position.x < 1.5
		attacked = attacked or f.m.fighters[2].move_id != ""
		damage = damage or f.m.fighters[1].percent > 0
	check(moved and attacked and damage,"AI actually approaches, accepts kit attack, damages human through real physics")
	var t = f.m.tick; sequence = owner.ai.sequence
	await physics_frame
	check(not owner.advance(f.m,{},true),"pause skips all clocks")
	check(f.m.tick == t and owner.ai.sequence == sequence,"paused AI clock unchanged")
	check(owner.advance(f.m,{},true,true),"F2 commits one tick")
	dispose(f)
	if not failures: print("PASS: repo AI authoritative real match")
	quit(1 if failures else 0)
