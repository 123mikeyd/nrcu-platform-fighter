extends "res://tests/test_core_combat_lab.gd"
func key(code: int, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code; event.physical_keycode = code; event.pressed = pressed
    Input.parse_input_event(event)
func click(control: Control) -> void:
    var point := control.get_global_rect().get_center()
    for down in [true, false]:
        var event := InputEventMouseButton.new()
        event.position = point; event.global_position = point
        event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
        Input.parse_input_event(event)
        Input.flush_buffered_events()
    await process_frame
    await process_frame
func run() -> void:
    root.size = Vector2i(1280,720)
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab); current_scene = lab; lab.set_physics_process(false)
    await process_frame; await process_frame
    var button = lab.find_child("CollisionEditor",true,false)
    check(button != null, "combat has Collision editor navigation")
    if button == null: lab.free(); quit(1); return
    print("COMBAT EDITOR RECT ",button.get_global_rect())
    check(button.focus_mode == Control.FOCUS_NONE, "navigation never steals gameplay focus")
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://.verification/core/collision-authoring-nav/native-combat.png")
    key(KEY_F,true); Input.flush_buffered_events()
    await click(button)
    var editor = current_scene
    check(editor.scene_file_path == "res://scenes/collision_authoring_lab.tscn", "parsed mouse opens editor")
    if editor.scene_file_path != "res://scenes/collision_authoring_lab.tscn": editor.free(); quit(1); return
    check(editor.find_child("ReturnCombat",true,false) != null, "explicit reset-on-return control")
    await click(editor.body_fields[0])
    key(KEY_ESCAPE,true); Input.flush_buffered_events(); await process_frame
    check(current_scene == editor, "Escape in text field does not navigate")
    key(KEY_ESCAPE,false); Input.flush_buffered_events()
    editor.body_fields[0].release_focus()
    editor.reset_dialog.popup_centered()
    await process_frame
    key(KEY_ESCAPE,true); Input.flush_buffered_events(); await process_frame
    check(current_scene == editor, "Escape dismisses dialog not editor")
    key(KEY_ESCAPE,false); Input.flush_buffered_events()
    await click(editor.find_child("ReturnCombat",true,false))
    lab = current_scene; lab.set_physics_process(false)
    check(lab.scene_file_path == "res://scenes/combat_lab.tscn", "parsed return opens fresh combat")
    check(lab.selected_fighters == ["teknium","teknium"] and lab.simulation.rules == null, "return explicitly resets selections and rules")
    for i in range(40):
        await tick(lab)
        check(lab.simulation.fighters[1].activation_id == "", "held attack suppressed after return")
    key(KEY_F,false); await tick(lab); key(KEY_F,true); await tick(lab)
    check(lab.simulation.fighters[1].activation_id != "", "release repress rearms attack")
    key(KEY_F,false)
    await click(lab.find_child("CollisionEditor",true,false))
    editor = current_scene
    key(KEY_ESCAPE,true); Input.flush_buffered_events()
    await process_frame; await process_frame
    check(current_scene.scene_file_path == "res://scenes/combat_lab.tscn", "Escape without editing navigates to fresh combat")
    key(KEY_ESCAPE,false); current_scene.free()
    if not failures: print("PASS collision authoring navigation")
    quit(1 if failures else 0)
