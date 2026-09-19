extends "res://tests/test_core_stock_lab_invariance.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    current_scene = lab
    lab.set_physics_process(false)
    lab.start_stock_match()
    var baseline: Array = await walk_round(lab)
    lab.set_collision_shapes_visible(true)
    check(await walk_round(lab) == baseline, "ON identical real input movement/KO/stock/result trace to OFF")
    check(lab.collision_debug.entries.size() == 2, "eliminated body absent at rendered result")
    lab.collision_debug.free()
    check(await walk_round(lab) == baseline, "REMOVED identical real input movement/KO/stock/result trace to OFF")
    lab.free()
    if failures == 0: print("PASS: collision debug OFF/ON/REMOVED exact three-stock gameplay trace")
    quit(1 if failures else 0)
