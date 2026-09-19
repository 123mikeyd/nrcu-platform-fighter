extends "res://tests/test_core_top_support_native.gd"
func run():
	for id in ["teknium","turbofit"]:
		var f = setup_pair(id,id)
		reset_drop(f,0,0.1); await acquire(f)
		for i in 5: await step(f.m)
		var previous = f.m.top_support_telemetry(2).geometry.height
		var standing = previous
		var jump = Frame.new(); jump.pressed.jump = true; jump.held.jump = true
		await step(f.m,{2:jump}); jump.pressed.clear()
		for i in 12:
			await step(f.m,{2:jump})
			var g = f.m.top_support_telemetry(2).geometry
			check(absf(g.height-previous) <= 0.0801,"bounded category transition, not animation bob")
			previous = g.height
		var geometry = f.m.top_support_telemetry(2).geometry
		print("POSE ",id," ",geometry," lower ",f.b.telemetry())
		check(geometry.pose_category == "airborne" and geometry.height > standing+0.1,"real lower jump selects authored airborne support envelope")
		check(absf(geometry.height-(2.13 if id == "teknium" else 2.90)) < 0.001,"source-derived sampled jumping head envelope")
		dispose(f)
	if not failures: print("PASS: bounded authored gameplay pose-category support")
	quit(1 if failures else 0)
