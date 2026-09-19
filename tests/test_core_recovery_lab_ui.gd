extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    var text := ""
    for label in lab.find_children("*", "Label", true, false): text += label.text
    check("W+G" in text and "Up+L" in text and "RISING STRIKE" in text, "visible recovery controls for both physical keyboards")
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
    check(not "No recovery" in text, "implemented recovery is not advertised as unsupported")
    for i in range(40): await tick(lab)
    key(KEY_W, true)
    key(KEY_G, true)
    await tick(lab)
    key(KEY_W, false)
    key(KEY_G, false)
    var data: Dictionary = lab.get_snapshot().actors[0]
    check(data.get("recovery_spent", false) and data.get("recovery_active", false), "telemetry exposes separate spent and active flags")
    check(data.get("recovery_age", -1) == 1 and not str(data.get("recovery_id", "")).is_empty(), "telemetry exposes contact age and episode identity")
    check(is_equal_approx(data.get("recovery_elapsed", -1.0), 1.0 / 60.0), "telemetry exposes committed episode clock")
    var id: String = data.get("recovery_id", "")
    for i in range(22): await tick(lab)
    data = lab.get_snapshot().actors[0]
    check(not data.get("recovery_active", true) and data.get("recovery_spent", false) and data.get("recovery_id", "") == id, "active expiry retains spent and cooldown identity")
    check(data.cooldown_ticks == 16 and data.get("recovery_age", 0) == -1, "active expiry does not truncate shared cooldown")
    lab._process(0)
    check("spent" in lab.telemetry_label.text and "active" in lab.telemetry_label.text, "visible spent and active diagnostics alongside cooldown")
    lab.reset_lab()
    data = lab.get_snapshot().actors[0]
    check(not data.get("recovery_spent", true) and not data.get("recovery_active", true) and data.get("recovery_id", "missing") == "", "reset clears recovery telemetry")
    lab.free()
    if failures == 0: print("PASS: recovery lab visible controls and detached resource/episode diagnostics")
    quit(1 if failures else 0)
