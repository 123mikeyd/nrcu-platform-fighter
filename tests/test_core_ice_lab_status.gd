extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    for slot in range(2):
        lab.select_fighter(slot, "teknium")
        lab.select_fighter(1-slot, "ice_mage")
        lab.reset_lab()
        for i in range(40): await tick(lab)
        var side := KEY_D if slot == 0 else KEY_LEFT
        key(side,true)
        await tick(lab)
        key(side,false)
        for i in range(12): await tick(lab)
        lab.actors[slot].position.x = 0
        lab.actors[1-slot].position.x = 1.1 if slot == 0 else -1.1
        var special := KEY_G if slot == 0 else KEY_L
        key(special,true)
        for i in range(22): await tick(lab)
        key(special,false)
        var f: Dictionary = lab.simulation.fighters[slot+1]
        var visual = lab.imported_visuals[1-slot]
        check(f.grab != null and f.grab.phase == "hold", "real parsed grab establishes hold")
        check(visual.output.clip == "Electrocution", "Ice victim consumes committed live relation")
        if f.grab != null: check(is_equal_approx(visual.output.elapsed,f.grab.elapsed), "raw committed hold clock")
        lab.set_paused(true)
        lab.simulation.cancel_action(slot+1,"test")
        lab._sync_visuals()
        check(visual.output.clip != "Electrocution", "paused same tick relation cleanup")
        lab.simulation.set_enabled(2-slot,false)
        lab._sync_visuals()
        check(visual.output.identity == "inactive", "lifecycle effective enablement")
        lab.set_paused(false)
    lab.free()
    if not failures: print("PASS: Ice live two-ended electrocution and inactive lifecycle presentation")
    quit(1 if failures else 0)
