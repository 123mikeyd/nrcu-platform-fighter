extends "res://tests/test_core_ledge_match.gd"
func run():
	for side in [-1,1]:
		for stopped in [false,true]:
			var terrain = body(Vector3(-2*side,-0.5,0),Vector3(4,1,4))
			var m = setup_ledge()
			var anchor = Anchor.new(); anchor.anchor_id = "edge"; anchor.outward = side
			m.configure_ledges([anchor],LedgePolicy.new())
			m.reset({1:Vector3(side,-1,0),2:Vector3(-8*side,0.1,0)})
			await tick(m,{1:frame(false,-side)})
			check(m.ledge_telemetry(1).anchor_id == "edge","actual both-sided catch prerequisite")
			var a = m.fighters[1].actor; var b = m.fighters[2].actor
			b.reset_at(anchor.climb())
			if stopped: m.fighters[2].hitstop_left = 10
			var before: Vector3 = a.position
			var up = Frame.new(); up.axis.y = -1
			await tick(m,{1:up})
			check(m.ledge_events[1].transition == "blocked" and m.ledge_telemetry(1).anchor_id == "","occupied climb releases without phantom commit")
			check(a.position == before,"blocked climb performs no partial translation")
			check(b.position.x == anchor.climb().x,"blocked route never pushes occupant")
			cleanup(m); terrain.free()
	if not failures: print("PASS body ledge (%d checks)" % checks)
	quit(1 if failures else 0)
