extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failures += 1; printerr("FAIL: "+message)
func run():
	var path := "res://scripts/core/kits/ggb_air.gd"
	check(ResourceLoader.exists(path),"GGB independent air policy exists")
	if failures: quit(1); return
	var a = load(path).new()
	for i in 5:
		var request = a.commit_jump(1,{})
		check(not request.is_empty() and is_equal_approx(request.vertical_speed,10.5*pow(.84,i)),"five diminishing jumps")
	check(a.commit_jump(1,{}).is_empty(),"sixth rejected")
	var before = a.snapshot()
	check(a.float_request(1,.1,{"jump_held":true,"velocity":Vector3(0,-5,0),"stopped":true}).is_empty() and a.snapshot()==before,"hitstop no float budget")
	var request = a.float_request(1,.1,{"jump_held":true,"velocity":Vector3(0,-5,0)})
	check(request.vertical_speed==-1.5 and is_equal_approx(a.float_remaining,1.1),"held descent clamps and spends")
	for blocked in ["drop_committed","recovery_spent","frozen","caught","disabled"]:
		var context := {"jump_held":true,"velocity":Vector3(0,-5,0),blocked:true}
		before = a.snapshot()
		check(a.float_request(1,.1,context).is_empty() and a.snapshot()==before,"excluded float "+blocked)
	for i in 12: a.float_request(1,.1,{"jump_held":true,"velocity":Vector3(0,-5,0)})
	check(a.float_remaining==0 and a.float_request(1,.1,{"jump_held":true,"velocity":Vector3(0,-5,0)}).is_empty(),"exhausted float")
	a.reset()
	a.commit_recovery()
	check(a.recovery_spent and a.jumps_used==2 and a.commit_jump(1,{}).is_empty(),"recovery spends source jumps=2 but prohibits all five")
	a.landed(false)
	check(a.recovery_spent,"head or air no refund")
	a.landed(true)
	check(not a.recovery_spent and a.jumps_used==0 and a.float_remaining==1.2,"terrain resets")
	# Actual native capsule support, without legacy actor or presenter.
	var floor_body := StaticBody3D.new()
	var box := BoxShape3D.new(); box.size=Vector3(20,1,5)
	var shape := CollisionShape3D.new(); shape.shape=box; floor_body.add_child(shape)
	root.add_child(floor_body); floor_body.position.y=-.5
	var body := CharacterBody3D.new()
	var capsule := CapsuleShape3D.new(); capsule.radius=.4; capsule.height=2
	shape=CollisionShape3D.new();shape.shape=capsule;shape.position.y=1;body.add_child(shape)
	root.add_child(body);body.position=Vector3(0,.03,0)
	await physics_frame; await process_frame
	for i in 10:
		await physics_frame; await process_frame
		body.velocity=Vector3(0,-4,0);body.move_and_slide()
	check(body.is_on_floor() and a.terrain_grounded(body,[]),"real terrain floor")
	var head := StaticBody3D.new()
	shape=CollisionShape3D.new();shape.shape=capsule;shape.position.y=1;head.add_child(shape)
	root.add_child(head);head.position=Vector3(4,0,0)
	body.position=Vector3(4,2.03,0)
	await physics_frame;await process_frame
	for i in 10:
		await physics_frame; await process_frame
		body.velocity=Vector3(0,-4,0);body.move_and_slide()
	check(body.is_on_floor() and not a.terrain_grounded(body,[head]),"real native head floor not terrain")
	body.free();head.free();floor_body.free()
	if failures==0: print("PASS: GGB diminishing jumps, float budget/exclusions and native terrain vs head")
	quit(1 if failures else 0)
