extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    check(lab.has_method("select_fighter"), "lab offers independent verified fighter selection")
    if not lab.has_method("select_fighter"):
        lab.free()
        quit(1)
        return
    check(lab.selected_fighters == ["teknium", "teknium"], "fresh default preserved")
    var source = lab.sources[0]
    var actor = lab.actors[0]
    var sim = lab.simulation
    check(not lab.select_fighter(0, "unknown") and not lab.select_fighter(2, "ice_mage"), "invalid selection rejected")
    lab.start_stock_match()
    lab.set_paused(true)
    key(KEY_F, true)
    lab.pending_steps = 2
    var accepted: bool = lab.select_fighter(0, "ice_mage")
    check(accepted, "P1 selects Ice Mage")
    if not accepted:
        key(KEY_F, false)
        lab.free()
        quit(1)
        return
    check(lab.simulation == sim and lab.sources[0] == source and lab.actors[0] == actor, "ownership objects retained")
    check(lab.selected_fighters == ["ice_mage", "teknium"], "P2 independent")
    check(lab.simulation.kit_telemetry(1).kit_id == "ice_mage", "real registered kit replaced")
    check(lab.imported_visuals[0].get_script() == load("res://scripts/core/presentation/ice_mage_presenter.gd"), "correct actual presenter")
    check(lab.paused and lab.pending_steps == 0 and lab.simulation.rules != null, "round reset retains pause and rules")
    check(lab.simulation.fighters[1].stocks == 3 and source.slot == 0 and source.bindings.attack == KEY_F, "fresh stocks stable bindings slots")
    lab.step_once()
    await tick(lab)
    check(lab.simulation.kit_telemetry(1).basic.is_empty() or lab.simulation.kit_telemetry(1).basic.get("activation_id", "").is_empty(), "held attack suppressed after selection")
    key(KEY_F, false)
    check(lab.select_fighter(1, "ice_mage"), "duplicate kit selectable")
    check(lab.imported_visuals[0] != lab.imported_visuals[1], "independent presenters")
    check(lab.select_fighter(0, "teknium"), "switch back supported")
    check(lab.imported_visuals[0].get_script() == load("res://scripts/core/presentation/teknium_presenter.gd"), "Teknium presenter restored")
    lab.free()
    if not failures: print("PASS: independent fighter selection full round reset stable source ownership")
    quit(1 if failures else 0)
