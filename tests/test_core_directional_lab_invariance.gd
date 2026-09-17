extends "res://tests/test_core_combat_lab.gd"
func trace(lab) -> Array:
    var result: Array = []
    for airborne in [false, true]:
        for down in [false, true]:
            lab.reset_lab()
            for i in range(40): await tick(lab)
            if airborne:
                lab.actors[0].position = Vector3(0, 8, 0)
                lab.actors[0].runtime.grounded = false
            lab.actors[1].position = lab.actors[0].position + (Vector3(0, -2 if down else 2, 0) if airborne else (Vector3(2, 0, 0) if down else Vector3(0, 2, 0)))
            lab.actors[1].runtime.grounded = false
            var vertical := KEY_S if down else KEY_W
            key(vertical, true)
            key(KEY_F, true)
            for i in range(25):
                await tick(lab)
                key(vertical, false)
                key(KEY_F, false)
                var frame: Array = []
                for slot in range(2):
                    var f: Dictionary = lab.simulation.fighters[slot + 1]
                    frame.append([lab.actors[slot].position, lab.actors[slot].velocity, f.percent, f.move_id, f.ready_tick, lab.actors[slot].runtime.states.status, lab.actors[slot].runtime.recovery_spent])
                result.append(frame)
            check(lab.simulation.fighters[2].percent == 8, "invariance includes actual directional contact")
    return result
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    var visible: Array = await trace(lab)
    for visual in lab.imported_visuals: visual.visible = false
    check(await trace(lab) == visible, "hidden directional presenters cannot alter contacts or movement")
    for visual in lab.imported_visuals: visual.free()
    check(await trace(lab) == visible, "deleted directional presenters cannot alter contacts or movement")
    lab.free()
    if failures == 0: print("PASS: directional visible hidden deleted exact match traces")
    quit(1 if failures else 0)
