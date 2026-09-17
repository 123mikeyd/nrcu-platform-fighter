extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    var text := ""
    for label in lab.find_children("*", "Label", true, false): text += label.text
    for move in ["UPPERCUT", "UP AIR", "LOW SWEEP", "DOWN STRIKE"]:
        check(move in text, "visible implemented move " + move)
    check("W/S+F" in text and "Up/Down+K" in text, "both physical directional controls visible")
    var help: Label = lab.find_child("RosterHelp", true, false)
    for slot in range(2):
        check(lab.selected_fighters[slot] == "teknium", "default selected Teknium kit")
        check(lab.fighter_buttons[slot].text == "P%d: Teknium (change)" % (slot + 1), "exact selected kit label")
        var selected := ""
        for line in help.text.split("\n"):
            if line.begins_with("P%d Teknium:" % (slot + 1)): selected += line + "\n"
        var special := "G" if slot == 0 else "L"
        var recovery := "W+G" if slot == 0 else "Up+L"
        check(special + ": neutral ELECTRIC GRAB (exact no-axis)" in selected, "selected slot exact neutral grab binding")
        check("side FORCE PUSH" in selected and "down no-op (source intent)" in selected, "selected Teknium supported side and unsupported down specials")
        check("up RISING STRIKE recovery (" + recovery + ")" in selected, "selected slot up recovery binding")
        var directional := "W/S+F up/down" if slot == 0 else "Up/Down+K up/down"
        check(directional in selected, "selected slot directional basic binding")
        for route in ["SIDE / AIR STRIKE", "UPPERCUT / UP AIR", "LOW SWEEP / DOWN STRIKE"]:
            check(route in selected, "selected Teknium directional move pair " + route)
    check("W+G" in text and "Up+L" in text, "preserves recovery controls")
    lab.free()
    if failures == 0: print("PASS: directional lab bounded visible controls and scope")
    quit(1 if failures else 0)
