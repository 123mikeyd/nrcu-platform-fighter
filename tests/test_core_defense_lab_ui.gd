extends "res://tests/test_core_combat_lab_layout.gd"
func run() -> void:
    for dimensions in [Vector2i(1280,720), Vector2i(960,540)]:
        var viewport := SubViewport.new()
        viewport.size = dimensions
        root.add_child(viewport)
        var lab = load("res://scenes/combat_lab.tscn").instantiate()
        viewport.add_child(lab)
        lab.set_physics_process(false)
        check(lab.get("defense_button") != null, "finite defense checkbox is visible")
        if lab.get("defense_button") == null:
            viewport.free()
            continue
        check(lab.defense_button.focus_mode == Control.FOCUS_NONE, "mouse control cannot consume Space/Enter")
        for i in 3: await process_frame
        for down in [true, false]:
            var event := InputEventMouseButton.new()
            event.position = lab.defense_button.get_global_rect().get_center()
            event.global_position = event.position
            event.button_index = MOUSE_BUTTON_LEFT
            event.pressed = down
            viewport.push_input(event, true)
        await process_frame
        check(lab.simulation.defense_profile != null, "actual checkbox signal opts in")
        check(viewport.gui_get_focus_owner() == null, "mouse defense toggle leaves gameplay focus free")
        lab._process(0)
        var snapshot: Dictionary = lab.get_snapshot()
        check(snapshot.get("defense_enabled", false), "web snapshot declares policy")
        check(snapshot.actors[0].get("defense", {}) == lab.simulation.defense_telemetry(1).merged({"motion_velocity": [0.0, 0.0]}, true), "web defense values copied from policy with JSON vector")
        snapshot.actors[0].defense.shield_health = 0
        check(lab.simulation.defense_telemetry(1).shield_health == 100, "browser snapshot cannot mutate authoritative defense")
        check("shield 100" in lab.telemetry_label.text and "air 1" in lab.telemetry_label.text and "defCD 0" in lab.telemetry_label.text and "idle" in lab.telemetry_label.text, "compact health state charges cooldown HUD")
        var all_text := ""
        for label in lab.find_children("*", "Label", true, false): all_text += label.text
        check("E/O" in all_text and "fresh" in all_text and "fallback" in all_text, "honest physical dodge controls and fallback labels")
        lab.start_stock_match()
        lab._process(0)
        for i in 3: await process_frame
        var arena := Rect2(Vector2(0, dimensions.y * .27), Vector2(dimensions.x, dimensions.y * .52))
        var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
        for button in lab.find_children("*", "Button", true, false):
            if not button.visible: continue
            check(bounds.encloses(button.get_global_rect()) and not arena.intersects(button.get_global_rect()), "defense preserves all edge-band control geometry")
        check(not arena.intersects(lab.telemetry_label.get_global_rect()), "defense HUD never covers center")
        # Reviewed bounded-scroll contract: explanatory scrolling is allowed, controls are not.
        for control in [lab.defense_button, lab.p2_input_button, lab.ai_difficulty_button, lab.comparison_button, lab.pause_button, lab.reset_button, lab.rematch_button]:
            check(control_reachable(control, viewport), "defense critical control visible and unclipped")
        for panel in hud_panels(lab):
            for scroll in panel.get_children():
                if scroll is ScrollContainer: check(scroll.clip_contents, "defense overflow stays inside band")
        print("DEFENSE UI %s %s" % [dimensions, lab.defense_button.get_global_rect()])
        for i in 40: await tick(lab)
        key(KEY_SPACE, true); key(KEY_ENTER, true)
        for i in 8: await tick(lab)
        key(KEY_SPACE, false); key(KEY_ENTER, false)
        check(lab.actors[0].velocity.y > 0 and lab.actors[1].velocity.y > 0 and lab.defense_button.button_pressed, "both parsed jump keys work after clicking finite control without toggling it")
        viewport.free()
    if failures == 0: print("PASS: defense lab HUD JSON policy and edge-band controls")
    quit(1 if failures else 0)
