extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    check(lab.simulation.rules == null, "sandbox remains default")
    if not lab.has_method("start_stock_match"):
        check(false, "explicit stock match entry exists")
        lab.free()
        quit(1)
        return
    var source = lab.sources[0]
    var bindings: Dictionary = source.bindings.duplicate()
    lab.start_stock_match()
    var rules = lab.simulation.rules
    check(rules.stock_count == 3 and rules.respawn_hitstun_ticks == 33 and rules.respawn_protection_ticks == 0, "source stock/stun/no new defense defaults")
    check(lab.actors[0].position == Vector3(-4, 1, 0) and lab.actors[1].position == Vector3(4, 1, 0), "stage owns stock spawns")
    check(rules.stage.blast_left == -16 and rules.stage.blast_right == 16 and rules.stage.blast_bottom == -8 and rules.stage.blast_top == 15, "source blast bounds")
    # Physical-key backend -> actor movement -> match blast, not teleport or fake KO.
    key(KEY_A, true)
    for i in range(300):
        await tick(lab)
        if lab.simulation.fighters[1].stocks == 2: break
    key(KEY_A, false)
    check(lab.simulation.fighters[1].stocks == 2, "real keyboard walk-off loses one stock")
    check(lab.actors[0].position == rules.stage.spawns[1], "match respawns at authoritative spawn")
    check(lab.actors[0].runtime.hitstun_left == 33, "respawn stun is 33 ticks")
    check(lab.sources[0] == source and source.bindings == bindings and source.slot == 0, "KO preserves source and bindings")
    lab.set_paused(true)
    var t: int = lab.simulation.tick
    await tick(lab)
    check(lab.simulation.tick == t, "stock pause")
    lab.step_once()
    await tick(lab)
    check(lab.simulation.tick == t + 1, "stock single step")
    lab.enter_sandbox()
    check(lab.simulation.rules == null and lab.actors[0].position == lab.spawns[1], "explicit sandbox restores practice spawns")
    check(lab.paused and lab.pending_steps == 0, "mode change preserves pause and flushes steps")
    lab.free()
    if failures == 0: print("PASS: stock lab opt-in source rules physical walkoff respawn sandbox pause step")
    quit(1 if failures else 0)
