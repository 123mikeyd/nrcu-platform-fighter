extends "res://tests/test_core_combat_lab_layout.gd"
func run() -> void:
    for dimensions in [Vector2i(1280,720), Vector2i(960,540)]:
        var viewport := SubViewport.new()
        viewport.size = dimensions
        root.add_child(viewport)
        var lab = load("res://scenes/combat_lab.tscn").instantiate()
        viewport.add_child(lab)
        lab.set_physics_process(false)
        check(lab.get("ledges_button") != null, "visible explicit ledges toggle")
        if lab.get("ledges_button") == null:
            viewport.free(); continue
        for i in 3: await process_frame
        for down in [true, false]:
            var event := InputEventMouseButton.new()
            event.position = lab.ledges_button.get_global_rect().get_center()
            event.global_position = event.position
            event.button_index = MOUSE_BUTTON_LEFT
            event.pressed = down
            viewport.push_input(event, true)
        await process_frame
        lab._process(0)
        var data: Dictionary = lab.get_snapshot()
        check(data.get("ledges_enabled", false), "mouse installs policy and JSON flag")
        check(data.actors[0].get("ledge", {}) == lab.simulation.ledge_telemetry(1), "JSON detached authoritative ledge")
        check("ledge" in lab.telemetry_label.text and "regrab" in lab.telemetry_label.text and "protected" in lab.telemetry_label.text, "authoritative HUD ledge anchor protection regrab")
        var text := ""
        for label in lab.find_children("*", "Label", true, false): text += label.text
        check("Hang/climb" in text and "fallback" in text and "inward" in text, "honest fallback and actionable ledge controls")
        check(viewport.gui_get_focus_owner() == null, "toggle leaves gameplay focus free")
        lab.start_stock_match(); lab._process(0)
        for i in 3: await process_frame
        var buttons: Array = []
        var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
        var arena := Rect2(Vector2(0, dimensions.y*.27), Vector2(dimensions.x, dimensions.y*.52))
        for button in lab.find_children("*", "Button", true, false):
            if not button.visible: continue
            var rect: Rect2 = button.get_global_rect()
            check(bounds.encloses(rect) and not arena.intersects(rect), "all controls remain in edge bands")
            for previous in buttons: check(not rect.intersects(previous), "no controls occlude one another")
            buttons.append(rect)
        # Reviewed bounded-scroll contract: verbose help may scroll, critical controls may not.
        for control in [lab.p2_input_button, lab.ai_difficulty_button, lab.comparison_button, lab.pause_button, lab.reset_button, lab.fighter_buttons[0], lab.fighter_buttons[1]]:
            check(control_reachable(control, viewport), "critical control visible and unclipped")
        for panel in hud_panels(lab):
            for scroll in panel.get_children():
                if scroll is ScrollContainer: check(scroll.clip_contents, "explanatory overflow remains inside edge bands")
        print("LEDGE UI %s %s" % [dimensions, lab.ledges_button.get_global_rect()])
        var camera: Camera3D = viewport.get_camera_3d()
        print("LEDGE PROJECTION %s left=%s right=%s" % [dimensions, camera.unproject_position(Vector3(-12.65,-1.5,0)), camera.unproject_position(Vector3(12.65,-1.5,0))])
        for i in 40: await tick(lab)
        key(KEY_SPACE, true); key(KEY_ENTER, true)
        for i in 8: await tick(lab)
        key(KEY_SPACE, false); key(KEY_ENTER, false)
        check(lab.actors[0].velocity.y > 0 and lab.actors[1].velocity.y > 0, "both gameplay jumps survive mouse control")
        viewport.free()
    if failures == 0: print("PASS: ledge lab UI telemetry layout focus")
    quit(1 if failures else 0)
