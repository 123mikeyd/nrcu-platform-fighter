extends "res://tests/test_core_collision_lab_ui.gd"
func run() -> void:
    for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
        root.content_scale_size = Vector2i.ZERO; root.size = dimensions
        var lab = load("res://scenes/combat_lab.tscn").instantiate()
        root.add_child(lab); lab.set_paused(true)
        lab.select_fighter(1,"turbofit"); lab.set_generated_collision_enabled(true)
        # This fixture characterizes retained legacy head support, not the generated default.
        check(lab.simulation.reset_with_collision_profiles(lab.spawns, {1:lab.simulation.fighters[1].collision_host.builder._profile,2:lab.simulation.fighters[2].collision_host.builder._profile}, "legacy_solid"),"explicit legacy support fixture")
        lab._reset_round_input_and_visuals()
        await shortcut(KEY_F4)
        var label = lab.find_child("TopSupportTelemetry",true,false)
        check(label is Label,"read-only top-support telemetry label")
        var legend = lab.find_child("CollisionLegend",true,false)
        check("orange" in legend.text and "one-way" in legend.text and "cyan" in legend.text and "magenta" in legend.text and "yellow" in legend.text,"explicit physical support/body/hurtbox legend")
        check(lab.generated_collision_enabled and lab.simulation.tick == 0,"F4 visibility only no collision-mode reset")
        check(lab.collision_debug.entries.has("top_support:1"),"F4 shows support alongside native body")
        check(legend.get_global_rect().end.y < dimensions.y*.26-8,"entire support legend visible above scroll bar")
        if label is Label:
            check("rider->" in label.text and "→" not in label.text,"support relation uses readable ASCII arrow")
            check("ephemeral" in label.text and "upright" in label.text and "none" in label.text,"stable category vs ephemeral relation")
            check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(label.get_global_rect()),"support telemetry readable at "+str(dimensions))
            check(label.get_global_rect().position.y >= dimensions.y*.8,"telemetry stays outside model band")
            if DisplayServer.get_name() != "headless":
                await RenderingServer.frame_post_draw
                root.get_texture().get_image().save_png("res://.verification/core/top-support-lab/ui-%dx%d.png" % [dimensions.x,dimensions.y])
        await shortcut(KEY_F4)
        check(not lab.collision_debug.visible and lab.generated_collision_enabled,"F4 hides both layers without opting out")
        if label is Label: check(not label.visible,"hidden diagnostics hidden label")
        lab.free()
    if not failures: print("PASS: top-support UI F4 visibility only legend category and two-size layout")
    quit(1 if failures else 0)
