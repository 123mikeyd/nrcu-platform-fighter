extends "res://tests/test_core_combat_lab.gd"
func capture(lab) -> void:
    lab.set_paused(false)
    lab.reset_lab()
    for i in range(40): await tick(lab)
    lab.actors[0].position.x = 0
    lab.actors[1].position.x = 1.1
    key(KEY_G, true)
    for i in range(30): await tick(lab)
    key(KEY_G, false)
    check(lab.simulation.fighters[2].caught_by == 1, "fixture real hold")
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    for reason in ["cancel", "disable", "freeze", "reset"]:
        await capture(lab)
        check(lab.get("grab_visuals") != null and not lab.get("grab_visuals").is_empty(), "hold has diagnostic arcs")
        lab.set_paused(true)
        var t: int = lab.simulation.tick
        var p: float = lab.simulation.fighters[2].percent
        var time: float = lab.imported_visuals[1].animation_player.current_animation_position
        for i in range(3): await tick(lab)
        check(lab.simulation.tick == t and lab.simulation.fighters[2].percent == p, "pause freezes simulation")
        check(is_equal_approx(time, lab.imported_visuals[1].animation_player.current_animation_position), "pause freezes victim source clock")
        lab.step_once()
        await tick(lab)
        check(lab.simulation.tick == t+1, "one step one match tick")
        match reason:
            "cancel": lab.simulation.cancel_action(2, "lab-test")
            "disable": lab.simulation.set_enabled(1, false)
            "freeze": lab.simulation.set_frozen(2, true)
            "reset": lab.reset_lab()
        # No simulate: the next render must reconcile current relations.
        lab._process(0)
        check(lab.imported_visuals[1].animation_player.assigned_animation != "Electrocution", "paused " + reason + " clears victim before render")
        check(lab.imported_visuals[0].animation_player.assigned_animation not in ["GrabStart", "GrabLoop", "GrabEnd"], "paused " + reason + " clears caster")
        check(lab.imported_visuals[1].position.x == 0 and lab.imported_visuals[1].position.z == 0, "no residual jitter")
        check(lab.get("grab_visuals") != null and lab.get("grab_visuals").is_empty(), "paused " + reason + " frees arcs")
    lab.free()
    if failures == 0: print("PASS: grab lab paused step cancel disable frozen reset relation cleanup")
    quit(1 if failures else 0)
