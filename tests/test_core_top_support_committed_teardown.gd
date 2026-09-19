extends "res://tests/test_core_top_support_lifecycle.gd"
func run():
	var f = setup_pair("teknium","turbofit")
	await acquire(f)
	f.b.free()
	var t = f.m.top_support_telemetry(2)
	check(t.body.is_empty() and t.relation.is_empty(),"retired actor telemetry has no live body/relation")
	check(f.m.top_support_telemetry(1).relation.is_empty(),"carrier tree exit releases rider relation")
	f.a.free(); f.floor.free()
	if not failures: print("PASS: supported geometry readback after actor retirement")
	quit(1 if failures else 0)
