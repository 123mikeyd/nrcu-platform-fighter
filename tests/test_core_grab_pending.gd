extends "res://tests/test_core_grab_slice.gd"
func run():
	var runtime = preload("res://scripts/core/fighter/fighter_runtime.gd").new()
	check(runtime.has_method("cancel_for_grab"), "caught cancellation clears private pending move state")
	if not runtime.has_method("cancel_for_grab"): quit(1); return
	runtime.reset(true); runtime.step({"jump": true, "jump_held": true})
	runtime.recovery_spent = true; runtime.air_jumps_left = 0
	runtime.cancel_for_grab()
	check(runtime.states.status == "caught" and runtime.hitstun_left == 0, "capture status")
	runtime.states.transition("status", "normal", "release")
	for i in 10: runtime.step({"jump_held": true})
	check(runtime.velocity.y <= 0, "no delayed pre-capture jump")
	check(runtime.states.locomotion == "idle", "released grounded victim returns to ground locomotion")
	check(runtime.recovery_spent and runtime.air_jumps_left == 0, "cancel does not refund air resources")
	var actor = Actor.new(); root.add_child(actor)
	check(actor.has_method("cancel_for_grab"), "actor clears pending platform drop on capture")
	if not actor.has_method("cancel_for_grab"): actor.free(); quit(1); return
	var platform := StaticBody3D.new(); root.add_child(platform)
	actor._dropping = platform
	actor.cancel_for_grab()
	check(actor._dropping == null and actor.runtime.states.status == "caught", "capture cancels platform drop")
	actor.free(); platform.free()
	if not failures: print("PASS: grab pending move cancellation (%d checks)" % checks)
	quit(1 if failures else 0)
