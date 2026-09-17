extends "res://tests/test_core_ledge_match.gd"
func run() -> void:
	var terrain = body(Vector3(2,-0.5,0),Vector3(4,1,4))
	var m = setup_ledge()
	await tick(m,{1:frame(false,1)})
	var up = Frame.new(); up.axis.y = -1
	await tick(m,{1:up})
	check(m.ledge_telemetry(1).anchor_id == "" and m.fighters[1].actor.position.is_equal_approx(Vector3(0.7,0.06,0)), "climb applies all elbow waypoints over real platform")
	for i in 4: await tick(m)
	check(m.fighters[1].actor.runtime.grounded, "climb hands grounded truth back to actual terrain")
	cleanup(m)
	for action in ["jump","down"]:
		m = setup_ledge(); await tick(m,{1:frame(false,1)})
		var at = m.fighters[1].actor.position
		var f = Frame.new(); f.pressed[action] = true
		await tick(m,{1:f})
		check(m.ledge_telemetry(1).anchor_id == "", "existing command releases ledge: " + action)
		check(m.fighters[1].actor.position == at, "departure does not warp")
		check(m.fighters[1].actor.velocity == (Vector3(-4,10,0) if action == "jump" else Vector3(0,-2,0)), "authored departure velocity " + action)
		check(m.fighters[1].buffer.peek(action).is_empty(), "accepted departure edge consumed")
		cleanup(m)
	# Thin wall prevents a catch; roof prevents climb even with clear destination.
	var wall = body(Vector3(-0.82,-0.3,0),Vector3(0.06,3,4))
	m = setup_ledge(); m.fighters[1].actor.position.x = -1.35
	await tick(m,{1:frame(false,1)})
	check(m.ledge_telemetry(1).anchor_id == "", "real capsule thin-wall sweep rejects catch")
	cleanup(m); wall.free()
	m = setup_ledge(); await tick(m,{1:frame(false,1)})
	var roof = body(Vector3(-0.65,1,0),Vector3(1,0.1,4))
	await tick(m,{1:up})
	check(m.ledge_telemetry(1).anchor_id == "" and m.fighters[1].actor.position.x < 0, "blocked roof climb releases without diagonal teleport")
	cleanup(m); roof.free(); terrain.free()
	if not failures: print("PASS: core ledge match motion (%d checks)" % checks)
	quit(1 if failures else 0)
