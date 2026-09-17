extends "res://tests/test_core_combat_lab_layout.gd"
func run() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280,720)
    root.add_child(viewport)
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    viewport.add_child(lab)
    lab.set_physics_process(false)
    for size in [Vector2i(1280,720),Vector2i(960,540)]:
        viewport.size = size
        lab.select_fighter(0,"teknium")
        lab.select_fighter(1,"teknium")
        for slot in range(2):
            for kit in ["turbofit","ice_mage","teknium"]:
                await process_frame
                await process_frame
                var center: Vector2 = lab.fighter_buttons[slot].get_global_rect().get_center()
                print("SELECTOR ",size," P",slot+1," ",center)
                for pressed in [true,false]:
                    var event := InputEventMouseButton.new()
                    event.position = center
                    event.global_position = center
                    event.button_index = MOUSE_BUTTON_LEFT
                    event.pressed = pressed
                    viewport.push_input(event,true)
                check(lab.selected_fighters[slot] == kit, "real selector cycles three verified entries " + kit)
                check(viewport.gui_get_focus_owner() == null, "mouse leaves physical keys free")
                if kit == "ice_mage":
                    check(lab.fighter_buttons[slot].text == "P%d: Ice Mage (change)" % (slot+1), "readable Ice Mage name")
                    var help: String = lab.find_child("RosterHelp",true,false).text
                    var selected := ""
                    for line in help.split("\n"):
                        if line.begins_with("P%d Ice Mage:" % (slot+1)): selected += line
                    check("IceStrike" in selected and "ground/air" in selected and "up/down" in selected, "source grounded directional basics")
                    check("neutral/side/down FROST BOLT" in selected and "1.6s" in selected and "FROST RISE" in selected and "no bolt" in selected, "source identical down bolt separate cast budget recovery")
                    check(not "POWER CHORD" in selected and not "ELECTRIC GRAB" in selected, "no other kit instructions assigned to Ice")
                    check(not "No full freeze" in help and "Debug FX" in help, "finite freeze scope no longer denied and FX honest")
        lab.select_fighter(0,"ice_mage")
        lab.select_fighter(1,"ice_mage")
        await process_frame
        await process_frame
        for button in lab.find_children("*","Button",true,false):
            check(Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()), "controls contained at both viewport sizes")
            check(button.focus_mode == Control.FOCUS_NONE,"stable focus")
        # Reviewed bounded-scroll contract: verbose help may scroll, critical controls may not.
        for control in [lab.p2_input_button, lab.ai_difficulty_button, lab.comparison_button, lab.pause_button, lab.reset_button, lab.fighter_buttons[0], lab.fighter_buttons[1]]:
            check(control_reachable(control, viewport), "critical control visible and unclipped")
        for panel in hud_panels(lab):
            for scroll in panel.get_children():
                if scroll is ScrollContainer: check(scroll.clip_contents, "explanatory overflow remains inside edge bands")
    viewport.free()
    if not failures: print("PASS: mouse three-entry selection both slots source scoped Ice help and geometry")
    quit(1 if failures else 0)
