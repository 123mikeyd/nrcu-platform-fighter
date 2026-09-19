extends "res://tests/test_core_combat_lab.gd"

# Only the outer CanvasLayer bands belong to this viewport's arena HUD.
# OptionButton popup windows own hidden theme panels and empty internal scrolls.
func hud_panels(lab) -> Array:
    var panels: Array = []
    for layer in lab.get_children():
        if layer is CanvasLayer:
            for child in layer.get_children():
                if child is PanelContainer: panels.append(child)
    return panels

func control_reachable(control: Control, viewport: SubViewport) -> bool:
    if not control.is_visible_in_tree() or control.get_viewport() != viewport: return false
    var rect := control.get_global_rect()
    if not rect.has_area() or not Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(rect): return false
    var ancestor := control.get_parent()
    while ancestor != null and ancestor != viewport:
        if ancestor is Control and ancestor.clip_contents:
            var clip: Rect2 = ancestor.get_global_rect()
            # Scrollbars occupy real input space, not usable content area.
            if ancestor is ScrollContainer:
                if ancestor.get_v_scroll_bar().visible: clip.size.x -= ancestor.get_v_scroll_bar().size.x
                if ancestor.get_h_scroll_bar().visible: clip.size.y -= ancestor.get_h_scroll_bar().size.y
            if not clip.encloses(rect): return false
        ancestor = ancestor.get_parent()
    return true

func hud_clears(panel: Control, region: Rect2) -> bool:
    return not panel.is_visible_in_tree() or not panel.get_global_rect().intersects(region)

func run() -> void:
    # SubViewports exercise real layout at each size, independent of window stretch.
    for viewport_size in [Vector2i(1280, 720), Vector2i(960, 540)]:
        var viewport := SubViewport.new()
        viewport.size = viewport_size
        root.add_child(viewport)
        var lab = load("res://scenes/combat_lab.tscn").instantiate()
        viewport.add_child(lab)
        lab.set_physics_process(false)
        var camera: Camera3D = viewport.get_camera_3d()
        check(camera.size == 14 and camera.position == Vector3(0, 6, 28), "layout preserves accepted camera")
        for actor in lab.actors:
            var labels = actor.find_children("*", "Label3D", true, false)
            check(labels.size() == 1 and labels[0].font_size >= 44 and labels[0].pixel_size >= 0.008, "player identity labels readable at arena scale")
        for i in range(40): await tick(lab)
        # Physical recovery reproduces the browser's rising source, not a static UI proxy.
        key(KEY_W, true)
        key(KEY_G, true)
        await tick(lab)
        key(KEY_W, false)
        key(KEY_G, false)
        check(lab.get_snapshot().actors[0].recovery_active, "physical recovery starts")
        var panels = hud_panels(lab)
        check(panels.size() == 2, "test measures both actual outer HUD bands")
        for i in range(28):
            await tick(lab)
            await process_frame
            var actor = lab.actors[0]
            var feet := camera.unproject_position(actor.global_position)
            var head := camera.unproject_position(actor.global_position + Vector3(0, 2.9, 0))
            var region := Rect2(Vector2(head.x - 24, head.y), Vector2(48, feet.y - head.y + 8))
            for panel in panels:
                check(hud_clears(panel, region), "%s HUD %s must not occlude projected recovery region %s at tick %d" % [viewport_size, panel.get_global_rect(), region, lab.simulation.tick])
                if i == 0:
                    var old_position: Vector2 = panel.position
                    panel.position = region.position
                    check(not hud_clears(panel, region), "counterfactual HUD occlusion is detected")
                    panel.position = old_position
        await process_frame
        var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
        for panel in panels:
            print("LAYOUT %s panel %s" % [viewport_size, panel.get_global_rect()])
            check(panel.is_visible_in_tree(), "actual HUD bands remain visible")
            check(bounds.encloses(panel.get_global_rect()), "HUD panel fits viewport")
        var telemetry_rect: Rect2 = lab.telemetry_label.get_global_rect()
        check(telemetry_rect.position.y >= viewport_size.y * 0.79, "diagnostics below visible floor")
        for button in lab.find_children("*", "BaseButton", true, false):
            if not button.is_visible_in_tree() or button.get_viewport() != viewport: continue
            check(button.focus_mode == Control.FOCUS_NONE, "combat buttons do not steal physical jump focus")
            check(control_reachable(button, viewport), "visible control remains reachable without scrolling: " + button.name)
        # Explicit inventory prevents a hidden critical control from disappearing
        # from the visible-only traversal and falsely passing the layout test.
        for button in [lab.p2_input_button, lab.ai_difficulty_button, lab.comparison_button, lab.pause_button, lab.reset_button, lab.generated_collision_button]:
            check(control_reachable(button, viewport), "critical control visible and unclipped: " + button.name)
            button.hide()
            check(not control_reachable(button, viewport), "counterfactual hidden critical control is detected")
            button.show()
        for panel in panels:
            var scroll_count := 0
            for scroll in panel.get_children():
                if not scroll is ScrollContainer: continue
                scroll_count += 1
                check(scroll.get_child_count() > 0, "HUD scroll has authored content")
                print("SCROLL %s h=%s v=%s" % [scroll.get_global_rect(), scroll.get_h_scroll_bar().visible, scroll.get_v_scroll_bar().visible])
                check(scroll.clip_contents, "overflow is clipped to edge band, not drawn over recovery")
                check(scroll.focus_mode == Control.FOCUS_NONE and scroll.get_v_scroll_bar().focus_mode == Control.FOCUS_NONE and scroll.get_h_scroll_bar().focus_mode == Control.FOCUS_NONE, "scrolling does not steal jump focus")
            check(scroll_count == 1, "each HUD band owns one content scroll")
        # Explanatory text may scroll at either resolution; controls may not.
        # Real mouse input on the moved controls, followed by both physical jumps.
        for click_index in range(2):
            for down in [true, false]:
                var event := InputEventMouseButton.new()
                event.position = lab.pause_button.get_global_rect().get_center()
                event.global_position = event.position
                event.button_index = MOUSE_BUTTON_LEFT
                event.pressed = down
                viewport.push_input(event, true)
            await process_frame
            check(lab.paused == (click_index == 0), "moved pause button remains mouse operable")
        check(viewport.gui_get_focus_owner() == null, "click leaves physical canvas input unfocused")
        lab.reset_lab()
        for i in range(40): await tick(lab)
        key(KEY_SPACE, true)
        key(KEY_ENTER, true)
        # Jump has an accepted jump-squat before upward motion.
        for i in range(8): await tick(lab)
        key(KEY_SPACE, false)
        key(KEY_ENTER, false)
        check(not lab.paused and lab.actors[0].velocity.y > 0 and lab.actors[1].velocity.y > 0, "both physical jump keys work after clicking controls")
        # AI adds identity/pose rows and stocks adds Rematch. Exercise those
        # actual visible states too, rather than validating only two-human UI.
        check(lab.set_p2_repo_ai(true), "layout enables actual AI comparison")
        for mode in ["grounded_jostle", "legacy_solid"]:
            check(lab.set_comparison_interaction(mode), "layout installs comparison arm")
            for stock_mode in [false, true]:
                if stock_mode: lab.start_stock_match()
                else: lab.enter_sandbox()
                await process_frame
                await process_frame
                for button in lab.find_children("*", "BaseButton", true, false):
                    if button.is_visible_in_tree() and button.get_viewport() == viewport:
                        check(control_reachable(button, viewport), "%s %s stocks=%s visible control reachable: %s" % [viewport_size, mode, stock_mode, button.name])
                for button in [lab.p2_input_button, lab.ai_difficulty_button, lab.comparison_button, lab.pause_button, lab.reset_button, lab.collision_snapshot_button]:
                    check(control_reachable(button, viewport), "AI critical control is visible and unclipped: " + button.name)
                if stock_mode: check(control_reachable(lab.rematch_button, viewport), "stock rematch is visible and unclipped")
        lab.free()
        viewport.free()
    if failures == 0: print("PASS: combat rendered HUD clears physical recovery at 1280x720 and 960x540")
    quit(1 if failures else 0)
