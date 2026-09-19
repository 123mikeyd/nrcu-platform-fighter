extends "res://tests/test_core_combat_lab.gd"
func walk_round(lab) -> Array:
    lab.rematch_lab()
    var trace: Array = []
    key(KEY_A, true)
    for i in range(1000):
        await tick(lab)
        var frame: Array = []
        for slot in range(2):
            var f: Dictionary = lab.simulation.fighters[slot + 1]
            frame.append([lab.actors[slot].position, lab.actors[slot].velocity, f.stocks, f.eliminated, f.percent, f.move_id, f.caught_by])
        trace.append(frame)
        if not lab.simulation.result.is_empty(): break
    key(KEY_A, false)
    check(lab.simulation.fighters[1].stocks == 0 and lab.simulation.result.get("winner_id") == 2, "three real walkoffs reach P2 winner without teleport")
    trace.append([lab.simulation.result.get("kind"), lab.simulation.result.get("winner_id"), lab.simulation.result.get("tick")])
    return trace
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    current_scene = lab
    lab.set_physics_process(false)
    lab.start_stock_match()
    var visible: Array = await walk_round(lab)
    for visual in lab.imported_visuals: visual.hide()
    check(await walk_round(lab) == visible, "hidden presentation exact stock trajectory and outcome")
    for visual in lab.imported_visuals: visual.free()
    check(await walk_round(lab) == visible, "deleted presentation exact stock trajectory and outcome")
    # Results -> actual viewport F3 (explicit rematch), then held keys across
    # Esc navigation. Sources and actor signal owners must be torn down cleanly.
    for code in [KEY_F, KEY_G, KEY_K, KEY_L]: key(code, true)
    Input.flush_buffered_events()
    var shortcut := InputEventKey.new()
    shortcut.physical_keycode = KEY_F3
    shortcut.pressed = true
    root.push_input(shortcut)
    check(lab.simulation.result.is_empty() and lab.simulation.fighters[1].stocks == 3, "physical F3 rematches stock result")
    for i in range(45): await tick(lab)
    check(lab.simulation.fighters[1].activation_id.is_empty() and lab.simulation.fighters[2].activation_id.is_empty(), "F3 suppresses held F/G/K/L")
    var old_source = lab.sources[0]
    var old_match = lab.simulation
    shortcut = InputEventKey.new()
    shortcut.physical_keycode = KEY_ESCAPE
    shortcut.pressed = true
    root.push_input(shortcut)
    await process_frame
    await process_frame
    check(current_scene.scene_file_path == "res://scenes/training_lab.tscn", "Esc exits stock mode")
    check(old_match.fighters.is_empty() and not Input.joy_connection_changed.is_connected(old_source._on_joy_connection_changed), "stock navigation releases match and source owners")
    for code in [KEY_F, KEY_G, KEY_K, KEY_L]: key(code, false)
    current_scene.free()
    if failures == 0: print("PASS: stock lab three physical walkoffs WIN render invariance F3 rematch Esc teardown")
    quit(1 if failures else 0)
