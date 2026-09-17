extends "res://tests/test_full_game_flow.gd"
func run():
	var failures := 0
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		var view := SubViewport.new()
		view.size = size
		view.own_world_3d = true
		root.add_child(view)
		app = load("res://scenes/experimental_full_game.tscn").instantiate()
		view.add_child(app)
		app.show_select()
		await frames(4)
		var help_text := ""
		for item in app.find_children("*","Label",true,false): help_text += item.text
		for required in ["LB shield","neutral special","Down drops","shield + move"]:
			if not help_text.contains(required):
				printerr("FAIL: missing playable controls ",required)
				failures += 1
		for id in ["Fighter1","Fighter2","OpponentOwner","StartMatch","BackMenu"]:
			var rect: Rect2 = app.find_child(id,true,false).get_global_rect()
			if not Rect2(Vector2.ZERO,Vector2(size)).encloses(rect):
				printerr("FAIL: ",size," selection control clipped ",id," ",rect)
				failures += 1
		app.start_match()
		await frames(4)
		for label_node in app.page.get_children():
			if label_node is Label and not Rect2(Vector2.ZERO,Vector2(size)).encloses(label_node.get_global_rect()):
				printerr("FAIL: ",size," match HUD clipped ",label_node.get_global_rect())
				failures += 1
		app.free(); view.free()
	await frames(2)
	if failures == 0: print("PASS: full game compact selection and match HUD at 1280 and 960")
	quit(1 if failures else 0)
