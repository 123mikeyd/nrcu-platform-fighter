extends "res://tests/test_core_combat_lab.gd"
# Outer canvas panels own layout. OptionButton's hidden popup panels/scrolls
# are separate windows, not arena HUD; never enumerate those as live HUD.
func run():
	for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
		var viewport = SubViewport.new(); viewport.size = dimensions; root.add_child(viewport)
		var lab = load("res://scenes/combat_lab.tscn").instantiate(); viewport.add_child(lab); lab.set_physics_process(false)
		var panels: Array = []
		for child in lab.get_children():
			if child is CanvasLayer:
				for panel in child.get_children():
					if panel is PanelContainer: panels.append(panel)
		check(panels.size() == 2,"exactly two outer HUD bands")
		for i in 40: await tick(lab)
		key(KEY_W,true); key(KEY_G,true); await tick(lab); key(KEY_W,false); key(KEY_G,false)
		check(lab.get_snapshot().actors[0].recovery_active,"real physical recovery prerequisite")
		for i in 28:
			await tick(lab); await process_frame
			var camera = viewport.get_camera_3d()
			var feet = camera.unproject_position(lab.actors[0].global_position)
			var head = camera.unproject_position(lab.actors[0].global_position+Vector3(0,2.9,0))
			var region = Rect2(Vector2(head.x-24,head.y),Vector2(48,feet.y-head.y+8))
			for panel in panels: check(not panel.get_global_rect().intersects(region),"outer HUD clears recovery "+str(dimensions))
		for panel in panels:
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(panel.get_global_rect()),"outer HUD fits viewport")
			var scroll = panel.get_child(0)
			check(scroll.clip_contents and scroll.focus_mode == Control.FOCUS_NONE,"help overflow clips inside edge band without focus")
		for control in [lab.p2_input_button,lab.ai_difficulty_button,lab.comparison_button,lab.pause_button,lab.reset_button]:
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(control.get_global_rect()),"primary controls in viewport")
			check(control.get_global_rect().end.y <= dimensions.y*.26,"primary controls visible in top band")
		lab.free(); viewport.free()
	if not failures: print("PASS: AI lab outer HUD recovery and primary controls at both resolutions")
	quit(1 if failures else 0)
