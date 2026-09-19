extends "res://tests/test_core_ledge_match.gd"
func press_special(axis: Vector2):
	var f = Frame.new(); f.pressed.special = true; f.held.special = true; f.axis = axis; return f
func run():
	var terrain = body(Vector3(2,-.5,0),Vector3(4,1,4))
	var m = setup_ledge(); m.configure_actor_kit(1,"turbofit")
	m.fighters[1].actor.runtime.velocity.x = 3
	await tick(m,{1:press_special(Vector2.ZERO)})
	check(m.ledge_telemetry(1).anchor_id == "left", "Turbofit catches shared ledge")
	check(m.kit_telemetry(1).special.phase == "idle", "ledge catch cancels committed charge episode")
	m.configure_actor_kit(2,"turbofit")
	m.fighters[2].actor.reset_at(Vector3(-1.6,-1.5,0))
	await tick(m,{2:press_special(Vector2.DOWN)})
	check(m.fighters[1].percent == 0 and m.fighters[1].actor.runtime.hitstun_left == 0, "ledge catch protection filters zero damage Orb launch")
	check(m.ledge_telemetry(1).anchor_id == "left", "protected Orb does not detach ledge relation")
	cleanup(m); terrain.free()
	if not failures: print("PASS: turbo match ledge (%d checks)" % checks)
	quit(1 if failures else 0)
