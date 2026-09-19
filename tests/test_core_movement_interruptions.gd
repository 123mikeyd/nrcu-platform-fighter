extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _init() -> void:
	var r = load("res://scripts/core/fighter/fighter_runtime.gd").new()
	r.reset(true)
	check(not r.states.transition("locomotion", "rising", "skip startup"), "coordinator rejects ground-to-rise without startup")
	r.reset(true)
	r.step({"jump": true, "jump_held": true})
	check(not r.states.transition("locomotion", "run", "interrupt"), "coordinator rejects locomotion overriding startup")
	r.reset(true)
	r.step({"jump": true, "jump_held": true})
	r.step({"shield": true, "jump_released": true})
	for i in range(5): r.step({"jump_held": true})
	var p = load("res://scripts/core/fighter/movement_profile.gd").new()
	check(r.velocity.y <= p.short_jump_speed, "release survives movement lock during startup")
	r.reset(true)
	r.step({"jump": true, "jump_held": true})
	r.reconcile_contact(false, Vector3(1, -0.5, 0))
	for i in range(5): r.step({"jump_held": true})
	check(r.velocity.y < 0 and r.states.locomotion == "falling", "walkoff during startup cancels unlaunched ground jump")
	check(r.can_accept_jump() and r.air_jumps_left == 1, "startup walkoff retains air jump")
	r.reset(false)
	r.step({"jump": true, "jump_held": true})
	r.reconcile_contact(false, Vector3.ZERO)
	check(r.states.locomotion == "falling", "ceiling contact publishes falling on the contact tick")
	r.reset(false)
	r.reconcile_contact(true, Vector3.ZERO)
	r.reconcile_contact(false, Vector3.ZERO)
	r.step({})
	check(r.velocity.y < 0 and r.states.action == "neutral", "lost landing support cancels lock and applies gravity")
	if failures == 0: print("PASS: core movement interruptions (%d checks)" % checks)
	quit(1 if failures else 0)
