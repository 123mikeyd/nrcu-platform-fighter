extends "res://tests/test_collision_authoring_layout.gd"
func run() -> void:
    var lab = load("res://scenes/collision_authoring_lab.tscn").instantiate(); root.add_child(lab)
    check(lab.discover_profiles("res://data/collision/generated").size() == 7, "seven real generated profiles")
    for resolution in [Vector2i(1280,720),Vector2i(960,540)]:
        root.size = resolution
        await process_frame; await process_frame
        var scroll: ScrollContainer = lab.panel.get_parent()
        print("LAYOUT ",resolution," root ",root.get_visible_rect()," scroll ",scroll.get_global_rect(), " minimum ",scroll.get_combined_minimum_size())
        check(scroll.get_global_rect().end.y <= resolution.y, "bounded scroll panel")
        for button in lab.panel.find_children("*","Button",true,false):
            if button.text.begins_with("Apply") or button.text.begins_with("Save") or button.text.begins_with("RESET"):
                scroll.ensure_control_visible(button)
                await process_frame; await process_frame
                check(scroll.get_global_rect().encloses(button.get_global_rect()), "critical control scroll accessible: " + button.text)
        var view: SubViewportContainer = lab.world.get_parent().get_parent()
        check(view.get_global_rect().position.x >= scroll.get_global_rect().end.x, "model pane never covered by editor")
        check(view.size.x >= resolution.x - 390, "model gets remaining width")
        if DisplayServer.get_name() != "headless":
            scroll.scroll_vertical = 0
            await process_frame; await process_frame
            await RenderingServer.frame_post_draw
            root.get_texture().get_image().save_png("res://.verification/core/collision-authoring-nav/native-%d.png" % resolution.x)
            print("ROUTE ",resolution," return ",lab.find_child("ReturnCombat",true,false).get_global_rect())
            for button in lab.panel.find_children("*","Button",true,false):
                if button.text.begins_with("Download"): print("DOWNLOAD RECT ",button.get_global_rect())
    lab.open_profile("res://data/collision/generated/ggb.tres")
    check(lab.detail.text.contains("body only"), "GGB clearly labelled static body only")
    check(not lab.slider.editable and lab.animation_selector.disabled and lab.hurt_selector.disabled, "static model cannot scrub or select invented hurtboxes")
    lab.free()
    if not failures: print("PASS collision authoring responsive")
    quit(1 if failures else 0)
