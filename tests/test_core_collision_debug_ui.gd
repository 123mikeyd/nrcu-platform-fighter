extends "res://tests/test_core_collision_debug.gd"
func click(control: Control) -> void:
    var point := control.get_global_rect().get_center()
    for down in [true, false]:
        var event := InputEventMouseButton.new()
        event.position = point
        event.global_position = point
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = down
        root.push_input(event, true)
    await process_frame
func capture(label: String) -> void:
    if DisplayServer.get_name() == "headless": return
    await RenderingServer.frame_post_draw
    var path := "res://.verification/core/collision-debug/" + label + ".png"
    check(root.get_texture().get_image().save_png(path) == OK, "native screenshot saved")
    print("SCREENSHOT: ", path)
func run() -> void:
    for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
        root.content_scale_size = Vector2i.ZERO
        root.size = dimensions
        var lab = load("res://scenes/combat_lab.tscn").instantiate()
        root.add_child(lab)
        lab.set_paused(true)
        for i in range(4): await process_frame
        var toggle: CheckButton = lab.collision_shapes_button
        check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(toggle.get_global_rect()), "toggle fits " + str(dimensions))
        await capture("native-%dx%d-off" % [dimensions.x, dimensions.y])
        await click(toggle)
        check(lab.collision_debug.visible, "real mouse toggles ON " + str(dimensions))
        for i in range(3): await process_frame
        var legend: Label = lab.find_child("CollisionLegend", true, false)
        check(legend.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(legend.get_global_rect()), "legend fits")
        await capture("native-%dx%d-on" % [dimensions.x, dimensions.y])
        for code in [KEY_SPACE, KEY_ENTER]: key(code)
        check(toggle.button_pressed and lab.paused and root.gui_get_focus_owner() != toggle, "jump keys do not reactivate clicked UI")
        var old_tick: int = lab.simulation.tick
        key(KEY_F2)
        for i in range(3): await physics_frame
        check(lab.simulation.tick == old_tick + 1, "real paused F2 advances exactly one tick")
        lab.actors[0].position += Vector3(1, 2, 0)
        for i in range(2): await process_frame
        var capsule = lab.actors[0].get_node("CoreCapsule")
        check(lab.collision_debug.entries[capsule.get_instance_id()].points == lab.collision_debug.world_lines(capsule), "paused render sync uses final pose")
        key(KEY_F3)
        check(lab.collision_debug.entries[capsule.get_instance_id()].points == lab.collision_debug.world_lines(capsule), "F3 same-frame reset pose")
        lab.free()
    if failures == 0: print("PASS: collision debug native UI both sizes, mouse focus, paused F2/F3 and screenshots")
    quit(1 if failures else 0)
