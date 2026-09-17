extends "res://tests/test_core_combat_lab.gd"
func trace(lab) -> Array:
    lab.reset_lab()
    for i in range(40): await tick(lab)
    lab.actors[0].position.x = 0
    lab.actors[1].position.x = 1.1
    key(KEY_G, true)
    var result: Array = []
    for age in range(1, 151):
        await tick(lab)
        key(KEY_G, false)
        if age == 95: key(KEY_K, true)
        if age == 112: key(KEY_K, false)
        var frame: Array = []
        for slot in range(2):
            var f: Dictionary = lab.simulation.fighters[slot+1]
            frame.append([lab.actors[slot].position, lab.actors[slot].velocity, f.percent, f.move_id, f.ready_tick, f.caught_by, f.grab_immune_until, f.grab.phase if f.grab != null else "idle", f.grab.ordinal if f.grab != null else -1, lab.actors[slot].runtime.states.status])
        result.append(frame)
    check(lab.simulation.fighters[1].percent == 0 and lab.simulation.fighters[2].percent == 10, "late caught physical K edge drains across release")
    return result
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    var visible: Array = await trace(lab)
    for visual in lab.imported_visuals: visual.visible = false
    check(await trace(lab) == visible, "hidden render same exact grab physics")
    for visual in lab.imported_visuals: visual.free()
    check(await trace(lab) == visible, "deleted render same exact grab physics")
    check(lab.grab_visuals.is_empty(), "no leaked diagnostic geometry")
    lab.free()
    if failures == 0: print("PASS: grab lab visible hidden deleted physics and caught held suppression")
    quit(1 if failures else 0)
