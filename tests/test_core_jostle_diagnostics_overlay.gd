extends "res://tests/test_core_collision_lab_ui.gd"
func run():
	for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
		root.content_scale_size = Vector2i.ZERO; root.size = dimensions
		var lab = load("res://scenes/combat_lab.tscn").instantiate()
		root.add_child(lab); lab.set_paused(true)
		lab.select_fighter(1,"turbofit")
		for i in 4: await process_frame
		await click(lab.find_child("GeneratedCollision",true,false))
		for i in 12:
			lab.step_once(); await physics_frame; await process_frame
		lab.set_collision_shapes_visible(true)
		lab.collision_debug.refresh()
		var legend = lab.find_child("CollisionLegend",true,false)
		check("white grounded jostle range" in legend.text,"range has distinct named diagnostic color")
		check("Range geometry not published" not in lab.find_child("TopSupportTelemetry",true,false).text,"released geometry replaces missing seam notice")
		for id in [1,2]:
			var d: Dictionary = lab.simulation.jostle_world(id)
			check(d.eligible,"settled marker prerequisite")
			var entry: Dictionary = lab.collision_debug.entries.get("jostle:%d" % id,{})
			check(not entry.is_empty(),"published eligible range drawn")
			if not entry.is_empty():
				check(entry.points == PackedVector3Array(d.world_segment),"exact authoritative endpoints consumed")
				check(entry.color == Color.WHITE,"range distinct from terrain and hurtboxes")
				entry.geometry.world_segment[0] = Vector3.INF
				check(lab.simulation.jostle_world(id) == d,"consumer geometry cannot mutate authority")
		check(legend.get_global_rect().end.y < dimensions.y*.26-8,"full marker legend fits visible band")
		lab.collision_debug.refresh()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://.verification/core/jostle-diagnostics-final/on-%dx%d.png" % [dimensions.x,dimensions.y]) == OK,"native on capture")
		await shortcut(KEY_F4)
		check(not lab.collision_debug.visible,"F4 hides range")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://.verification/core/jostle-diagnostics-final/off-%dx%d.png" % [dimensions.x,dimensions.y]) == OK,"native off capture")
		lab.simulation.reset({1:Vector3(0,6,0),2:Vector3.ZERO})
		lab.step_once(); await physics_frame; await process_frame
		lab.set_collision_shapes_visible(true); lab.collision_debug.refresh()
		check(not lab.simulation.jostle_world(1).eligible,"airborne no marker prerequisite")
		check(not lab.collision_debug.entries.has("jostle:1"),"ineligible air shows no horizontal marker")
		lab.free()
	if not failures: print("PASS: jostle authoritative marker native sizes and visibility")
	quit(1 if failures else 0)
