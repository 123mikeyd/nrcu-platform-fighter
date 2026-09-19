extends "res://tests/test_core_top_support_lifecycle.gd"
func obstacle(at: Vector3, size: Vector3):
	var b = StaticBody3D.new(); var c = CollisionShape3D.new(); var s = BoxShape3D.new()
	s.size = size; c.shape = s; b.add_child(c); b.position = at; root.add_child(b); return b
func run():
	for reverse in [false,true]:
		for side in [-1,1]:
			var f = setup_pair("teknium","turbofit",reverse,"auto")
			f.m.reset({1:Vector3(side*0.2,0,0),2:Vector3(-side*0.2,0,0)})
			for i in 4: await step(f.m)
			var radius = f.a.get_node("CoreCapsule").shape.radius
			var edge = side*(0.2+radius+0.02)
			var wall = obstacle(Vector3(edge+side*0.01,1.5,0),Vector3(0.02,3,4))
			var roof = obstacle(Vector3(0,3.2,0),Vector3(4,0.03,4))
			await physics_frame
			f.a.position.x = side*0.2; f.b.position.x = -side*0.2
			var y = f.a.position.y
			for i in 20:
				await step(f.m)
				check(side*f.a.get_node("CoreCapsule").global_position.x+radius <= side*edge+0.002,"thin wall sweep never crosses")
				check(absf(f.a.position.y-y)<0.003 and absf(f.a.velocity.x)<0.00001,"no wall climb or lateral launch")
			var source = Source.new(); key(KEY_SPACE,true)
			for i in 8: await step(f.m,{1:source.sample(f.m.tick)})
			key(KEY_SPACE,false)
			check(f.a.velocity.y > 0,"enemy by wall cannot lock real jump")
			for i in 12: await step(f.m,{1:source.sample(f.m.tick)})
			check(f.a.position.y+f.a.get_node("CoreCapsule").shape.height < 3.2,"actual thin roof retained")
			wall.free(); roof.free(); dispose(f)
	# Ordinary departure from a small terrain platform: no ground tether.
	var f = setup_pair("teknium","teknium",false,"auto")
	f.floor.get_child(0).shape.size.x = 1.5
	f.m.reset({1:Vector3(0.3,0,0),2:Vector3(0,0,0)})
	for i in 5: await step(f.m)
	var source = Source.new(); key(KEY_D,true)
	var left_floor = false
	for i in 35:
		await step(f.m,{1:source.sample(f.m.tick)})
		if not f.a.runtime.grounded and f.a.position.y < -0.1: left_floor = true
	key(KEY_D,false)
	check(left_floor,"actual ledge departure and fall, no magical ground tether")
	dispose(f)
	if not failures: print("PASS: jostle native thin terrain wall roof and ledge escape")
	quit(1 if failures else 0)
