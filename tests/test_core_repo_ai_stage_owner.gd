extends "res://tests/test_core_top_support_lifecycle.gd"
const Owner = preload("res://scripts/core/input/repo_ai_match_input.gd")
func run():
	var owner = Owner.new()
	check(owner.get("stage_bounds") is Dictionary,"owner exposes optional explicit stage bounds")
	if failures: quit(1); return
	var geom = load("res://scripts/core/stage/combat_lab_stage.gd").new().geometry()[0]
	var bounds = {"left":geom.position.x-geom.size.x/2,"right":geom.position.x+geom.size.x/2,"top":geom.position.y+geom.size.y/2}
	owner.stage_bounds = bounds
	var anchors = load("res://scripts/core/stage/combat_lab_stage.gd").new().create_anchors()
	check(bounds.left == anchors[0].edge.x and bounds.right == anchors[1].edge.x,"support bounds match legal anchors")
	var f = setup_pair("turbofit","teknium",false,"grounded_jostle")
	f.floor.position = geom.position; f.floor.get_child(0).shape.size = geom.size
	f.m.reset({1:Vector3(11,0,0),2:Vector3(8.45,0,0)})
	var obs = owner._observation(f.m,2)
	check(obs.stage_bounds == bounds,"explicit bounds copied into committed public observation")
	obs.stage_bounds.left = -99
	check(owner.stage_bounds == bounds,"observation cannot mutate owner geometry")
	var frame = owner.sample_all(f.m)[2]
	check(frame.axis.x == 1,"match owner pursues beyond old edge")
	frame.axis.x = -1
	check(owner.sample_all(f.m)[2].axis.x == 1,"cached source frame copy isolation")
	var timer = owner.ai.timer; var sequence = owner.ai.sequence
	owner.sample_all(f.m)
	check(timer == owner.ai.timer and sequence == owner.ai.sequence,"same commit no cooldown decrement")
	await physics_frame
	check(not owner.advance(f.m,{},true),"pause skips simulation")
	check(timer == owner.ai.timer,"pause retains AI timer")
	check(owner.advance(f.m,{},true,true),"single step commits")
	check(not owner.advance(f.m),"native tick only once")
	owner.configure(2,true,"hard")
	check(owner.stage_bounds == bounds and owner.ai.sequence == 0,"difficulty resets decision state not stage sensing")
	owner.reset()
	check(not owner.advance(f.m),"reset retains physical guard")
	check(owner.stage_bounds == bounds,"reset retains explicit support geometry")
	# Actual recovery through input from a legal airborne reset, not raw position edits.
	for side in [-1,1]:
		f.m.reset({1:Vector3.ZERO,2:Vector3(side*12.4,-.6,0)})
		owner.reset(); var recovered := false; var jump := false
		for i in 180:
			await physics_frame
			var frames = owner.sample_all(f.m)
			jump = jump or frames[2].held.jump or (frames[2].held.special and frames[2].axis.y < 0)
			owner.advance(f.m)
			recovered = recovered or (absf(f.b.position.x) < 11.8 and f.b.runtime.grounded)
		check(jump and recovered,"offstage recovery via real input "+str(side))
	dispose(f)
	if not failures: print("PASS: repo AI stage owner clocks copies reset recovery")
	quit(1 if failures else 0)
