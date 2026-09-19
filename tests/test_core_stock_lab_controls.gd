extends "res://tests/test_core_combat_lab.gd"
func click_button(viewport, lab, prefix: String) -> void:
    var button: Button
    for candidate in lab.find_children("*", "Button", true, false):
        if candidate.text.begins_with(prefix): button = candidate; break
    check(button != null, "mouse target exists " + prefix)
    if button == null: return
    for pressed in [true, false]:
        var event := InputEventMouseButton.new()
        event.position = button.get_global_rect().get_center()
        event.global_position = event.position
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        viewport.push_input(event, true)
    await process_frame
func run() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    root.add_child(viewport)
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    viewport.add_child(lab)
    lab.set_physics_process(false)
    for i in range(3): await process_frame
    await click_button(viewport, lab, "Start 3-stock")
    check(lab.simulation.rules != null, "mouse opts into stocks")
    for i in range(40): await tick(lab)
    for code in [KEY_F, KEY_G, KEY_K, KEY_L]: key(code, true)
    await tick(lab)
    await click_button(viewport, lab, "Sandbox")
    check(lab.simulation.rules == null, "mouse returns sandbox")
    for i in range(45): await tick(lab)
    for id in [1, 2]: check(lab.simulation.fighters[id].activation_id.is_empty(), "mode change discards held action edges")
    await click_button(viewport, lab, "Start 3-stock")
    lab.simulation.fighters[1].stocks = 1
    lab.actors[0].position.x = -17
    await tick(lab)
    lab._process(0)
    check("RESULTS" in lab.telemetry_label.text and "ELIMINATED" in lab.telemetry_label.text and "DISCONNECTED" not in lab.telemetry_label.text, "results telemetry not live or disconnected")
    await click_button(viewport, lab, "Rematch")
    check(lab.simulation.result.is_empty() and lab.simulation.fighters[1].stocks == 3, "mouse explicitly rematches")
    for i in range(45): await tick(lab)
    for id in [1, 2]: check(lab.simulation.fighters[id].activation_id.is_empty(), "mouse rematch suppresses held actions")
    check(viewport.gui_get_focus_owner() == null, "mode/result controls preserve physical keyboard focus")
    for code in [KEY_F, KEY_G, KEY_K, KEY_L]: key(code, false)
    lab.free()
    viewport.free()
    # Results are navigable for either policy outcome.
    for draw in [false, true]:
        lab = load("res://scenes/combat_lab.tscn").instantiate()
        root.add_child(lab)
        current_scene = lab
        lab.set_physics_process(false)
        lab.start_stock_match()
        lab.simulation.fighters[1].stocks = 1
        lab.actors[0].position.x = -17
        if draw:
            lab.simulation.fighters[2].stocks = 1
            lab.actors[1].position.x = 17
        await tick(lab)
        check(not lab.simulation.result.is_empty(), "navigation terminal fixture")
        var simulation = lab.simulation
        lab.back_to_movement()
        await process_frame
        await process_frame
        check(current_scene.scene_file_path == "res://scenes/training_lab.tscn" and simulation.fighters.is_empty(), "WIN/DRAW back navigation tears down")
        current_scene.free()
        current_scene = null
    if failures == 0: print("PASS: stock lab mouse modes rematch input suppression and results navigation")
    quit(1 if failures else 0)
