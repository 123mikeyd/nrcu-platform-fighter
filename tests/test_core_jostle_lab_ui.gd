extends "res://tests/test_core_collision_lab_ui.gd"
func run() -> void:
    for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
        root.content_scale_size = Vector2i.ZERO; root.size = dimensions
        var lab = load("res://scenes/combat_lab.tscn").instantiate()
        root.add_child(lab); lab.set_paused(true)
        lab.select_fighter(1,"turbofit")
        for i in 4: await process_frame
        var toggle = lab.find_child("GeneratedCollision",true,false)
        check(toggle.text == "Teknium / Turbo collision (reset) [F5]","simple complete collision label")
        await click(toggle)
        check(lab.generated_collision_enabled and lab.simulation.fighter_interaction_mode == "grounded_jostle","generated full batch defaults to grounded jostle")
        check(root.gui_get_focus_owner() != toggle,"same focus-free checkbox")
        lab.set_collision_shapes_visible(true)
        await process_frame
        var legend = lab.find_child("CollisionLegend",true,false)
        check("cyan terrain capsule" in legend.text and "grounded jostle" in legend.text,"terrain capsule and ground jostle distinguished")
        check("orange" not in legend.text and "one-way" not in legend.text,"no default head platform promise")
        check(lab.get_snapshot().get("fighter_interaction_mode","") == "grounded_jostle","public lab readback reports authoritative mode")
        for id in [1,2]:
            check(not lab.collision_debug.entries.has("top_support:%d" % id),"no orange support geometry")
            check(lab.collision_debug.entries.has(lab.actors[id-1].get_node("CoreCapsule").get_instance_id()),"cyan terrain capsule remains visible")
            check(lab.simulation.top_support_telemetry(id).relation.is_empty(),"no leftover head relation")
        var label = lab.find_child("TopSupportTelemetry",true,false)
        check("No head platform" in label.text and "rider->" not in label.text,"default diagnostic has no obsolete relation/category")
        check(legend.get_global_rect().end.y < dimensions.y*.26-8,"full legend in visible scroll band")
        check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(label.get_global_rect()),"diagnostic fits viewport")
        if DisplayServer.get_name() != "headless":
            await RenderingServer.frame_post_draw
            check(root.get_texture().get_image().save_png("res://.verification/core/jostle-lab/ui-%dx%d.png" % [dimensions.x,dimensions.y]) == OK,"native screenshot")
        await shortcut(KEY_F4)
        check(not lab.collision_debug.visible and lab.generated_collision_enabled and lab.simulation.tick == 0,"F4 remains visibility only")
        await shortcut(KEY_F5)
        check(not lab.generated_collision_enabled and lab.simulation.fighter_interaction_mode == "legacy_solid","same checkbox rollback reset")
        lab.free()
    if not failures: print("PASS: jostle lab truthful default UI telemetry native layout")
    quit(1 if failures else 0)
