extends "res://tests/test_core_top_support_native.gd"
func run():
	for reverse in [false,true]:
		var f = setup_pair("teknium","teknium",reverse)
		reset_drop(f,0.51,0.1,-120)
		f.a.runtime._tuning.fall_speed = 200
		f.a.runtime.velocity.x = 12; f.a.velocity = f.a.runtime.velocity
		await step(f.m)
		print("GLANCE ",f.a.position," lower ",f.b.position)
		check(f.a.position.y > 1.0,"fast glancing exit cannot bypass unchanged rounded native core")
		check(f.a.get_collision_exceptions().is_empty() and f.b.get_collision_exceptions().is_empty(),"movement exceptions are batch-owned only")
		dispose(f)
	if not failures: print("PASS: high-speed glancing native-core continuity")
	quit(1 if failures else 0)
