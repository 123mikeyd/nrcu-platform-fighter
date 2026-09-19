extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab._process(0)
    var text := ""
    for label in lab.find_children("*", "Label", true, false): text += label.text + "\n"
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
    for phrase in ["ELECTRIC GRAB", "exact no-axis", "source intent", "not authored final FX", "caught by", "ordinal", "immunity"]:
        check(phrase in text, "visible grab control/scope/telemetry: " + phrase)
    var data: Dictionary = lab.get_snapshot().actors[0]
    for field in ["grab_phase", "caught_by", "grab_ordinal", "grab_immunity_ticks"]:
        check(data.has(field), "detached grab telemetry " + field)
    lab.free()
    if failures == 0: print("PASS: grab lab visible exact neutral controls bounded scope telemetry")
    quit(1 if failures else 0)
