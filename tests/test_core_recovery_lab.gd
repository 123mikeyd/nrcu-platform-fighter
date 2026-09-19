extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    for slot in range(2):
        lab.reset_lab()
        for i in range(40): await tick(lab)
        var up := KEY_W if slot == 0 else KEY_UP
        var special := KEY_G if slot == 0 else KEY_L
        var direction := KEY_D if slot == 0 else KEY_LEFT
        key(up, true)
        key(direction, true)
        key(special, true)
        var start_y: float = lab.actors[slot].position.y
        await tick(lab)
        var f: Dictionary = lab.simulation.fighters[slot + 1]
        var visual = lab.imported_visuals[slot]
        check(f.move_id == "RISING STRIKE", "physical W+G / Up+L accepts recovery")
        check(not lab.actors[slot].runtime.grounded and lab.actors[slot].position.y > start_y and is_equal_approx(lab.actors[slot].velocity.y, 13.5), "physical recovery takes off terrain with one impulse")
        check(visual.state.output.clip == "RaiseWall", "committed recovery selects authored RaiseWall not Jump")
        check(is_equal_approx(visual.state.output.fraction, 1.0 / 39.0), "first committed tick maps RaiseWall to legacy .65 second duration")
        for code in [up, direction, special]: key(code, false)
        var transition: int = visual.state.transition
        for age in range(2, 40):
            await tick(lab)
            check(visual.state.output.clip == "RaiseWall" and visual.state.transition == transition, "single recovery episode survives active expiry without restarting")
            check(is_equal_approx(visual.state.output.fraction, age / 39.0), "source progress follows committed cooldown clock")
        check(f.recovery == null and not f.activation_id.is_empty(), "contact expires before presentation identity")
        await tick(lab)
        check(visual.state.output.clip != "RaiseWall", "cooldown retirement ends episode")
    lab.free()
    if failures == 0: print("PASS: recovery lab physical takeoff and continuous legacy RaiseWall clock")
    quit(1 if failures else 0)
