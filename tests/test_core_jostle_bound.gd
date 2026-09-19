extends "res://tests/test_core_top_support_lifecycle.gd"
func run():
	var f = setup_pair("teknium","teknium",false,"legacy_solid")
	var c = Actor.new(); root.add_child(c); f.m.register_actor(3,c)
	check(f.m.reset_with_collision_profiles({1:Vector3(-2,0,0),2:Vector3(0,0,0),3:Vector3(2,0,0)},{1:fitted("teknium"),2:fitted("teknium"),3:fitted("teknium")}),"three optins")
	for i in 5: await step(f.m)
	f.a.position.x = 0; f.b.position.x = 0.001; c.position.x = 0.002
	var starts = [f.a.position.x,f.b.position.x,c.position.x]
	f.m._advance_ground_jostle([1,2,3])
	for i in 3:
		check(absf(f.m.fighters[i+1].actor.position.x-starts[i]) <= 0.250001,"per-actor correction bound across all pairs")
	var d = Actor.new(); root.add_child(d)
	f.m.register_actor(4,d)
	check(not f.m.fighters.has(4),"late opted-out endpoint cannot asymmetrically join active jostle roster")
	d.free()
	c.free(); dispose(f)
	if not failures: print("PASS: bounded multi-fighter jostle")
	quit(1 if failures else 0)
