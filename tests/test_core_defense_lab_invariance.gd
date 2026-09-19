extends "res://tests/test_core_defense_lab_motion.gd"
func trace_lab(remove_presenters: bool) -> Array:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.set_defense_enabled(true)
    if remove_presenters:
        for visual in lab.imported_visuals: visual.free()
    await settle(lab)
    var trace: Array = []
    for i in 80:
        if i == 0: key(KEY_LEFT, true); key(KEY_O, true)
        if i == 1: key(KEY_LEFT, false); key(KEY_O, false)
        if i == 5: key(KEY_F, true)
        if i == 6: key(KEY_F, false)
        if i == 45: key(KEY_E, true)
        if i == 60: key(KEY_E, false)
        await tick(lab)
        var row: Array = []
        for slot in 2:
            row.append([lab.actors[slot].position, lab.actors[slot].velocity, lab.simulation.fighters[slot + 1].percent, lab.simulation.defense_telemetry(slot + 1), lab.simulation.fighters[slot + 1].buffer.debug_pending()])
        trace.append(row)
    lab.free()
    return trace
func run() -> void:
    var visible: Array = await trace_lab(false)
    var removed: Array = await trace_lab(true)
    check(visible == removed, "removing finite defense presentation leaves physical motion contacts resources queues identical")
    if failures == 0: print("PASS: defense lab presenter-independent parsed input trace")
    quit(1 if failures else 0)
