extends "res://tests/test_core_combat_lab.gd"
func click(control: Control) -> void:
    for down in [true,false]:
        var event := InputEventMouseButton.new()
        event.position = control.get_global_rect().get_center()
        event.global_position = event.position
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = down
        root.push_input(event,true)
    await process_frame
func capture(label: String) -> void:
    if DisplayServer.get_name() == "headless": return
    await RenderingServer.frame_post_draw
    var path := "res://.verification/core/collision-lab/" + label + ".png"
    check(root.get_texture().get_image().save_png(path) == OK,"native capture")
    print("SCREENSHOT: ",path)
func shortcut(code: int) -> void:
    key(code,true); key(code,false)
    Input.flush_buffered_events()
    for i in 2: await process_frame
func run() -> void:
    for dimensions in [Vector2i(1280,720),Vector2i(960,540)]:
        root.content_scale_size = Vector2i.ZERO; root.size = dimensions
        var lab = load("res://scenes/combat_lab.tscn").instantiate()
        root.add_child(lab); lab.set_paused(true)
        lab.select_fighter(1,"turbofit")
        for i in 4: await process_frame
        var toggle = lab.find_child("GeneratedCollision",true,false)
        check(toggle is CheckButton,"visible explicit draft generated toggle")
        if not toggle is CheckButton:
            lab.free(); quit(1); return
        check(toggle.text == "Teknium / Turbo collision (reset) [F5]" and toggle.tooltip_text.contains("draft"),"simple collision label and draft/reset disclosure")
        check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(toggle.get_global_rect()),"toggle fits " + str(dimensions))
        await click(toggle)
        check(lab.generated_collision_enabled,"real native mouse enables")
        check(root.gui_get_focus_owner() != toggle,"focus free toggle")
        var notice: Label = lab.find_child("GeneratedCollisionNotice",true,false)
        check(notice.text.contains("all accepted Teknium/Turbo recipient routes") and notice.text.contains("DRAFT") and notice.text.contains("ON/OFF resets"),"all accepted recipient routes and draft/reset disclosure")
        check(notice.get_global_rect().end.y <= notice.get_parent().get_parent().get_global_rect().end.y, "complete damage disclosure visible without scrolling")
        await shortcut(KEY_F2)
        for i in 3: await physics_frame
        await capture("native-%dx%d-canonical-no-outline" % [dimensions.x,dimensions.y])
        lab.set_collision_shapes_visible(true)
        check(lab.simulation.tick == 1,"real physics paused step exactly once")
        var snapshot: Dictionary = lab.get_snapshot()
        check(snapshot.get("generated_collision_enabled",false) and snapshot.actors[1].has("collision"),"browser snapshot publishes mode and pose summaries")
        check(snapshot.actors[1].get("collision",{}).get("current_pose",{}).get("clip","") != "","browser canonical source clip")
        print("UI_STATE: ", dimensions, " toggle=", toggle.get_global_rect(), " phase=", lab.collision_snapshot_button.get_global_rect(), " enabled=",lab.generated_collision_enabled)
        await capture("native-%dx%d-current" % [dimensions.x,dimensions.y])
        var phase_button = lab.find_child("CollisionSnapshotPhase",true,false)
        await click(phase_button)
        check(lab.collision_snapshot_phase == "contact_snapshot","real mouse selects precontact")
        await capture("native-%dx%d-contact" % [dimensions.x,dimensions.y])
        # Native real physics movement/jump after mouse controls, not injected frames.
        await shortcut(KEY_F1)
        for i in 40: await physics_frame
        check(lab.actors[0].runtime.grounded,"settled real floor prerequisite")
        key(KEY_SPACE,true)
        for i in 10: await physics_frame
        check(lab.actors[0].velocity.y > 0,"Space jumps after controls")
        key(KEY_SPACE,false)
        await shortcut(KEY_F1)
        var old_tick: int = lab.simulation.tick
        for i in 3: await physics_frame
        check(lab.simulation.tick == old_tick,"native pause stops real physics")
        await shortcut(KEY_F5)
        check(not lab.generated_collision_enabled and lab.simulation.tick == 0,"F5 restores legacy with reset")
        await capture("native-%dx%d-compatibility" % [dimensions.x,dimensions.y])
        lab.free()
    if not failures: print("PASS: collision lab native UI two sizes mouse keys real physics pause step reset captures")
    quit(1 if failures else 0)
