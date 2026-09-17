extends "res://tests/test_core_combat_lab_layout.gd"

func run() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    root.add_child(viewport)
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    viewport.add_child(lab)
    lab.set_physics_process(false)
    for slot in range(2):
        check(lab.fighter_buttons[slot].text == "P%d: Teknium (change)" % (slot + 1), "initial ASCII selector label")
    lab.select_fighter(0, "turbofit")
    check(lab.fighter_buttons[0].text == "P1: Turbofit (change)", "selected ASCII selector label")
    for button in lab.fighter_buttons:
        check(not "↔" in button.text, "unsupported selector glyph absent")
        for character in button.text: check(character.unicode_at(0) < 128, "selector entirely ASCII")
    for size in [Vector2i(1280, 720), Vector2i(960, 540)]:
        viewport.size = size
        for pair in [["teknium", "teknium"], ["turbofit", "teknium"], ["turbofit", "turbofit"], ["teknium", "turbofit"]]:
            for slot in range(2): lab.select_fighter(slot, pair[slot])
            await process_frame
            await process_frame
            var help = lab.find_child("RosterHelp", true, false)
            check(help is Label, "real selected roster help Label exists")
            if help is Label:
                for slot in range(2):
                    var prefix := "P%d %s:" % [slot + 1, str(pair[slot]).capitalize()]
                    var lines: PackedStringArray = help.text.split("\n")
                    var selected := ""
                    for line in lines:
                        if line.begins_with(prefix): selected += line
                    check(not selected.is_empty(), "instructions scoped to actual slot and selected kit")
                    check("up/down" in selected and "basic" in selected, "directional basics explicit")
                    if pair[slot] == "teknium":
                        check("neutral ELECTRIC GRAB" in selected and "side FORCE PUSH" in selected and "up RISING STRIKE recovery" in selected and "down no-op" in selected, "Teknium special routes")
                        check(not "POWER CHORD" in selected, "no Turbo instructions attributed to Teknium")
                    else:
                        check("neutral hold/release POWER CHORD" in selected and "side SOUND WAVE" in selected and "down SOUND ORB" in selected and "up RISING CHORD recovery" in selected, "Turbo special routes")
                        check(not "no-op" in selected and not "ELECTRIC GRAB" in selected, "no legacy instructions attributed to Turbo")
                if pair == ["turbofit", "turbofit"]:
                    check(not "no-op" in help.text and not "FORCE PUSH" in help.text, "duplicate Turbo removes obsolete kit advice")
                check("Debug FX" in help.text and "fallback" in help.text and "not new defense" in help.text, "honest presentation limits remain")
                check("W+G" in help.text and "Up+L" in help.text, "explicit recovery keys for both slots")
                print("HELP ", size, " ", pair, "\n", help.text)
            var bounds := Rect2(Vector2.ZERO, Vector2(size))
            for button in lab.find_children("*", "Button", true, false):
                check(bounds.encloses(button.get_global_rect()), "buttons fit viewport")
                check(button.focus_mode == Control.FOCUS_NONE, "buttons retain gameplay focus")
            check(not lab.fighter_buttons[0].get_global_rect().intersects(lab.fighter_buttons[1].get_global_rect()), "selector neighbors do not overlap")
            for scroll in lab.find_children("*", "ScrollContainer", true, false):
                check(scroll.clip_contents, "HUD overflow clips in safe band")
            # Reviewed bounded-scroll contract: retain all scoped help, mouse, focus and reset assertions.
            for control in [lab.p2_input_button, lab.ai_difficulty_button, lab.comparison_button, lab.pause_button, lab.reset_button, lab.fighter_buttons[0], lab.fighter_buttons[1]]:
                check(control_reachable(control, viewport), "roster critical control visible and unclipped")
    # Characterize real mouse selection, synchronous text, and unchanged rules/reset.
    lab.start_stock_match()
    lab.set_paused(true)
    for size in [Vector2i(1280, 720), Vector2i(960, 540)]:
        viewport.size = size
        lab.select_fighter(0, "teknium")
        lab.select_fighter(1, "teknium")
        await process_frame
        await process_frame
        for slot in range(2):
            var neighbor: String = lab.fighter_buttons[1 - slot].text
            for pressed in [true, false]:
                var event := InputEventMouseButton.new()
                event.position = lab.fighter_buttons[slot].get_global_rect().get_center()
                event.global_position = event.position
                event.button_index = MOUSE_BUTTON_LEFT
                event.pressed = pressed
                viewport.push_input(event, true)
            check(lab.selected_fighters[slot] == "turbofit", "real mouse selects each slot")
            check(lab.fighter_buttons[slot].text == "P%d: Turbofit (change)" % (slot + 1), "mouse synchronously updates ASCII label")
            check(lab.fighter_buttons[1 - slot].text == neighbor, "selection leaves neighboring label alone")
            check("P%d Turbofit:" % (slot + 1) in lab.find_child("RosterHelp", true, false).text, "mouse synchronously updates real help")
            check(viewport.gui_get_focus_owner() == null, "mouse leaves gameplay focus free")
            check(lab.paused and lab.simulation.rules != null and lab.get_snapshot().defense_enabled and lab.get_snapshot().ledges_enabled, "selection preserves pause and stock policies")
            check(lab.simulation.fighters[1].stocks == 3 and lab.simulation.fighters[2].stocks == 3, "selection retains reset stock counts")
        lab.reset_lab()
        check("P1 Turbofit:" in lab.find_child("RosterHelp", true, false).text and "P2 Turbofit:" in lab.find_child("RosterHelp", true, false).text, "reset retains selected help")
    viewport.free()
    if not failures: print("PASS: roster help selectors")
    quit(1 if failures else 0)
