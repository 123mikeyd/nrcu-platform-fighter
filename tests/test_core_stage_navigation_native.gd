extends "res://tests/test_core_top_support.gd"
func geometry(stage) -> Array:
	var result := []
	for body in stage.get_children():
		if not body is StaticBody3D: continue
		var shape = body.get_child(0)
		var half: Vector3 = shape.shape.size*0.5
		var low: Vector3 = shape.global_transform * -half
		var high: Vector3 = shape.global_transform * half
		result.append({"id":str(body.name),"rect":Rect2(Vector2(low.x,low.y),Vector2(high.x-low.x,high.y-low.y)),"one_way":body.is_in_group("core_pass_through")})
	return result
func run():
	var owner = load("res://scripts/core/input/repo_ai_match_input.gd").new()
	check(owner.has_method("configure_navigation"),"wrapper opt-in navigation seam exists")
	if failures: quit(1); return
	var stage = load("res://scripts/experimental/full_game_stage.gd").new()
	# v0.2 Toy Shelf is flat; retain multi-support policy coverage on the
	# unchanged authored debug layout, not invisible Toy Shelf geometry.
	stage.layout_id = "debug"
	root.add_child(stage)
	var m = Match.new(); var a = Actor.new(); var b = Actor.new()
	root.add_child(a); root.add_child(b)
	m.register_actor(1,a,-1,"teknium"); m.register_actor(2,b,-1,"turbofit")
	check(m.reset_with_collision_profiles({1:Vector3(-7,3.3,0),2:Vector3(-4,-0.01,0)},{1:fitted("teknium"),2:fitted("turbofit")},"grounded_jostle"),"real native generated pair")
	owner.configure(2,true,"easy"); owner.stage_bounds=stage.ai_bounds()
	check(owner.configure_navigation(geometry(stage)),"actual four authored supports copied")
	var landed := false; var jumps := 0
	for i in 450:
		await physics_frame
		var frames = owner.sample_all(m)
		if frames[2].pressed.get("jump",false): jumps += 1
		m.simulate(frames)
		if b.runtime.grounded and absf(b.position.y-3.225)<0.05: landed=true; break
	print("NATIVE main->left landed=",landed," jumps=",jumps," foot=",b.position)
	check(landed,"AI reaches actual upper support using only Match input")
	check(jumps == 2,"one ground and one air jump, held not spammed")
	a.free(); b.free(); stage.free()
	if not failures: print("PASS: native Toy Shelf AI main to upper")
	quit(1 if failures else 0)
