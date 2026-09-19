extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280,720)
    root.add_child(viewport)
    viewport.add_child(lab)
    lab.set_physics_process(false)
    check(lab.get("fighter_buttons") != null, "visible independent fighter controls")
    check(lab.get_snapshot().actors[0].has("kit"), "detached kit telemetry in browser snapshot")
    if lab.get("fighter_buttons") != null:
        for size in [Vector2i(1280,720),Vector2i(960,540)]:
            viewport.size = size
            await process_frame
            await process_frame
            for slot in range(2):
                var button: Button = lab.fighter_buttons[slot]
                var box := button.get_global_rect()
                check(box.position.x >= 20 and box.end.x < size.x-20 and box.end.y < size.y*.26, "selection visible in top band " + str(size))
                check(button.focus_mode == Control.FOCUS_NONE, "selection cannot steal keyboard")
                print("SELECTOR ", size, " P",slot+1," ",box)
            for pressed in [true,false]:
                var event := InputEventMouseButton.new()
                event.position = lab.fighter_buttons[0].get_global_rect().get_center()
                event.global_position = event.position
                event.button_index = MOUSE_BUTTON_LEFT
                event.pressed = pressed
                viewport.push_input(event,true)
            await process_frame
            check(viewport.gui_get_focus_owner() == null, "actual selector click leaves focus free")
            check(lab.selected_fighters[0] == "turbofit", "mouse control selects real kit")
            check("Turbofit" in lab.fighter_buttons[0].text, "selection visible label updated synchronously")
            for i in range(40): await tick(lab)
            key(KEY_SPACE,true)
            key(KEY_ENTER,true)
            for i in range(8): await tick(lab)
            check(lab.actors[0].position.y > .2 and lab.actors[1].position.y > .2, "both jump keys survive selector")
            key(KEY_SPACE,false)
            key(KEY_ENTER,false)
            lab.select_fighter(0,"teknium")
    var help: Label = lab.find_child("RosterHelp", true, false)
    # Advice follows each real selection, not the unselected roster catalog.
    var teknium_help: String = help.text
    for slot in range(2):
        check(lab.select_fighter(slot, "turbofit"), "explicitly select Turbo before checking advice")
        check(lab.fighter_buttons[slot].text == "P%d: Turbofit (change)" % (slot + 1), "exact Turbo selector label")
        var selected := ""
        for line in help.text.split("\n"):
            if line.begins_with("P%d Turbofit:" % (slot + 1)): selected += line + "\n"
        var special := "G" if slot == 0 else "L"
        var recovery := "W+G" if slot == 0 else "Up+L"
        var directional := "W/S+F up/down" if slot == 0 else "Up/Down+K up/down"
        check(directional in selected, "selected Turbo directional basic keys")
        check(special + ": neutral hold/release POWER CHORD" in selected, "selected Turbo exact neutral charge binding")
        check("side SOUND WAVE" in selected and "down SOUND ORB" in selected, "selected Turbo side and down specials")
        check("up RISING CHORD recovery (" + recovery + ")" in selected, "selected Turbo up recovery binding")
        check(not "no-op" in selected and not "ELECTRIC GRAB" in selected, "Turbo advice excludes Teknium-only routes")
        check(lab.select_fighter(slot, "teknium"), "switch back to Teknium")
        check(lab.fighter_buttons[slot].text == "P%d: Teknium (change)" % (slot + 1), "exact restored Teknium selector label")
        check(help.text == teknium_help, "switch back synchronously restores original Teknium help")
        selected = ""
        for line in help.text.split("\n"):
            if line.begins_with("P%d Teknium:" % (slot + 1)): selected += line + "\n"
        check(special + ": neutral ELECTRIC GRAB (exact no-axis)" in selected and "side FORCE PUSH" in selected and "down no-op (source intent)" in selected, "restored Teknium special routes")
        check("up RISING STRIKE recovery (" + recovery + ")" in selected, "restored Teknium up recovery")
        for move in ["POWER CHORD", "SOUND WAVE", "SOUND ORB", "RISING CHORD"]:
            check(not move in help.text, "no unselected Turbo move advice " + move)
    viewport.free()
    if not failures: print("PASS: independent selector layout controls focus and kit telemetry")
    quit(1 if failures else 0)
