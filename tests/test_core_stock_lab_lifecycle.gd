extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.start_stock_match()
    for i in range(40): await tick(lab)
    key(KEY_F, true)
    key(KEY_K, true)
    await tick(lab)
    var survivor_history: Dictionary = lab.sources[1]._previous.duplicate()
    var survivor_activation: String = lab.simulation.fighters[2].activation_id
    # Boundary fixture isolates lifecycle while the other fighter is attacking.
    lab.actors[0].position.x = -17
    lab.paused = true
    lab.pending_steps = 3
    await tick(lab)
    check(lab.pending_steps == 0, "KO flushes queued host steps")
    check(lab.sources[0]._previous.is_empty() and lab.sources[0]._suppress_next, "KO resets affected external history before next sample")
    check(lab.sources[1]._previous == survivor_history, "KO preserves survivor held attack history")
    check(lab.simulation.fighters[2].activation_id == survivor_activation, "KO preserves survivor committed attack")
    lab.set_paused(false)
    for i in range(40): await tick(lab)
    check(lab.simulation.fighters[1].activation_id.is_empty(), "held F cannot retrigger after respawn")
    key(KEY_F, false)
    key(KEY_K, false)
    # Terminal fixtures exercise batch outcomes, not production fake KO controls.
    for draw in [false, true]:
        lab.rematch_lab()
        for i in range(2): await tick(lab)
        lab.simulation.fighters[1].stocks = 1
        lab.actors[0].position.x = -17
        if draw:
            lab.simulation.fighters[2].stocks = 1
            lab.actors[1].position.x = 17
        await tick(lab)
        check(lab.simulation.result.get("kind") == ("DRAW" if draw else "WIN"), "committed terminal kind")
        check(lab.simulation.result.get("winner_id") == (0 if draw else 2), "committed winner identity")
        check(not lab.actors[0].visible, "eliminated actor and label hidden")
        var t: int = lab.simulation.tick
        var result: Dictionary = lab.simulation.result.duplicate(true)
        for code in [KEY_F, KEY_G, KEY_K, KEY_L]: key(code, true)
        lab.set_paused(true)
        lab.step_once()
        await tick(lab)
        check(lab.simulation.tick == t and lab.simulation.result == result and lab.pending_steps == 0, "results step is frozen and discarded")
        lab.set_paused(false)
        for i in range(3): await tick(lab)
        check(lab.simulation.result == result, "results persist; never auto rematch")
        var generation: int = lab.simulation.generation
        lab.rematch_lab()
        check(lab.simulation.generation == generation + 1 and lab.simulation.result.is_empty(), "explicit fresh generation rematch")
        for actor in lab.actors: check(actor.visible, "rematch restores actor and label")
        for i in range(45): await tick(lab)
        for id in [1, 2]:
            var f: Dictionary = lab.simulation.fighters[id]
            check(f.stocks == 3 and f.percent == 0 and f.activation_id.is_empty() and f.buffer.debug_pending().is_empty(), "held F/G/K/L suppressed through rematch")
        for code in [KEY_F, KEY_G, KEY_K, KEY_L]: key(code, false)
        await tick(lab)
        key(KEY_F, true)
        key(KEY_L, true)
        await tick(lab)
        check(lab.simulation.fighters[1].move_id == "SIDE STRIKE" and lab.simulation.fighters[2].grab != null, "fresh edges work after release")
        key(KEY_F, false)
        key(KEY_L, false)
    lab.enter_sandbox()
    check(lab.simulation.result.is_empty() and lab.sources[0].slot == 0 and lab.sources[1].slot == 1, "sandbox clears results without changing slot ownership")
    lab.free()
    if failures == 0: print("PASS: stock lab lifecycle histories terminal WIN DRAW explicit rematch held suppression")
    quit(1 if failures else 0)
