extends "res://tests/test_core_combat_lab.gd"
func trace(lab) -> Array:
    lab.reset_lab()
    for i in range(40): await tick(lab)
    key(KEY_D, true)
    for i in range(10): await tick(lab)
    key(KEY_D, false)
    for i in range(10): await tick(lab)
    key(KEY_W, true)
    key(KEY_G, true)
    var result: Array = []
    for i in range(50):
        await tick(lab)
        key(KEY_W, false)
        key(KEY_G, false)
        var frame: Array = []
        for slot in range(2):
            var f: Dictionary = lab.simulation.fighters[slot + 1]
            frame.append([lab.actors[slot].position, lab.actors[slot].velocity, f.percent, f.move_id, f.ready_tick, f.recovery.age if f.recovery != null else -1, lab.actors[slot].runtime.recovery_spent])
        result.append(frame)
    return result
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    var rendered: Array = await trace(lab)
    for visual in lab.imported_visuals: visual.visible = false
    check(await trace(lab) == rendered, "hidden renderers cannot change recovery physics or damage")
    for visual in lab.imported_visuals: visual.free()
    check(await trace(lab) == rendered, "deleted renderers cannot change recovery physics or damage")
    lab.free()
    lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    for i in range(40): await tick(lab)
    # Incoming real P2 strike snapshots alongside outgoing recovery.
    key(KEY_D, true)
    for i in range(10): await tick(lab)
    key(KEY_D, false)
    key(KEY_LEFT, true)
    await tick(lab)
    key(KEY_LEFT, false)
    for i in range(10): await tick(lab)
    key(KEY_W, true)
    key(KEY_G, true)
    key(KEY_K, true)
    await tick(lab)
    for code in [KEY_W, KEY_G, KEY_K]: key(code, false)
    check(lab.simulation.fighters[1].percent == 8 and lab.simulation.fighters[2].percent == 12, "real strike/recovery trade retains both snapshot contacts")
    check(lab.simulation.fighters[1].recovery == null and lab.simulation.fighters[1].activation_id == "", "real incoming strike clears recovery episode")
    check(lab.imported_visuals[0].state.output.clip == "Hit", "real incoming strike gives Hit priority over recovery")
    lab.free()
    if failures == 0: print("PASS: recovery lab hidden/deleted renderer invariance and actual incoming interruption")
    quit(1 if failures else 0)
