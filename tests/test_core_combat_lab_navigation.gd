extends "res://tests/test_core_combat_lab.gd"
func button_named(node: Node, prefix: String):
    for child in node.find_children("*", "Button", true, false):
        if child.text.begins_with(prefix): return child
    return null
func run() -> void:
    var movement = load("res://scenes/training_lab.tscn").instantiate()
    root.add_child(movement)
    current_scene = movement
    movement.set_physics_process(false)
    var navigation = button_named(movement, "Combat lab")
    if navigation == null:
        check(false, "movement overlay offers explicitly labeled combat navigation")
        movement.free()
        quit(1)
        return
    navigation.pressed.emit()
    await process_frame
    await process_frame
    var lab = current_scene
    check(lab.scene_file_path == "res://scenes/combat_lab.tscn", "native navigation opens combat scene")
    lab.set_physics_process(false)
    for name in ["Pause", "Step", "Reset", "Movement lab"]:
        var button = button_named(lab, name)
        check(button != null and button.focus_mode == Control.FOCUS_NONE, "non-stealing UI control: " + name)
    button_named(lab, "Pause").pressed.emit()
    var before: int = lab.simulation.tick
    button_named(lab, "Step").pressed.emit()
    await tick(lab)
    await tick(lab)
    check(lab.simulation.tick == before + 1, "UI pause/step advances once")
    button_named(lab, "Reset").pressed.emit()
    check(lab.get_snapshot().tick == 0, "UI reset refreshes telemetry")
    lab._process(0.0)
    check(lab.telemetry_label.text.contains("P1: 0.0%"), "visible damage telemetry is formatted")
    check(lab.get_snapshot().actors[0].has("cooldown_ticks"), "damage/status/cooldown snapshot available")
    var source = lab.sources[0]
    var simulation = lab.simulation
    button_named(lab, "Movement lab").pressed.emit()
    await process_frame
    await process_frame
    check(current_scene.scene_file_path == "res://scenes/training_lab.tscn", "back returns to movement lab")
    check(simulation.fighters.is_empty(), "navigation discards match actor references")
    check(not Input.joy_connection_changed.is_connected(source._on_joy_connection_changed), "navigation disconnects input source signal")
    current_scene.set_physics_process(false)
    button_named(current_scene, "Combat lab").pressed.emit()
    await process_frame
    await process_frame
    lab = current_scene
    lab.set_physics_process(false)
    # Dispatch through the viewport, not directly into the handler: changing
    # scenes detaches the old lab during this very input propagation.
    var escape := InputEventKey.new()
    escape.physical_keycode = KEY_ESCAPE
    escape.pressed = true
    key(KEY_F, true)
    key(KEY_K, true)
    Input.flush_buffered_events()
    check(Input.is_physical_key_pressed(KEY_F) and Input.is_physical_key_pressed(KEY_K), "strike keys are physically held across navigation")
    root.push_input(escape)
    check(root.is_input_handled(), "Esc is consumed before scene replacement")
    await process_frame
    await process_frame
    check(current_scene.scene_file_path == "res://scenes/training_lab.tscn", "viewport-dispatched Esc returns to movement lab")
    current_scene.set_physics_process(false)
    button_named(current_scene, "Combat lab").pressed.emit()
    await process_frame
    await process_frame
    lab = current_scene
    check(lab.scene_file_path == "res://scenes/combat_lab.tscn", "navigation reopens combat scene")
    lab.set_physics_process(false)
    for i in range(40):
        await tick(lab)
        for id in [1, 2]:
            check(lab.simulation.fighters[id].activation_id == "", "held strike cannot activate on reentry: P%d" % id)
            check(lab.simulation.fighters[id].buffer.debug_pending().is_empty(), "held strike is not queued on reentry: P%d" % id)
            check(lab.simulation.fighters[id].percent == 0.0, "no held-key damage on reentry: P%d" % id)
    # Separate actors so P1's resolved hit cannot interrupt P2's activation.
    lab.actors[0].position.x = -5.0
    lab.actors[1].position.x = 5.0
    key(KEY_F, false)
    key(KEY_K, false)
    await tick(lab)
    key(KEY_F, true)
    key(KEY_K, true)
    await tick(lab)
    for id in [1, 2]:
        check(lab.simulation.fighters[id].activation_id != "", "release/repress rearms strike: P%d" % id)
    key(KEY_F, false)
    key(KEY_K, false)
    current_scene.free()
    if failures == 0: print("PASS: combat lab UI navigation and cleanup")
    quit(1 if failures else 0)
