extends "res://tests/test_core_combat_lab_layout.gd"
func run() -> void:
    for viewport_size in [Vector2i(1280, 720), Vector2i(960, 540)]:
        var viewport := SubViewport.new()
        viewport.size = viewport_size
        root.add_child(viewport)
        var lab = load("res://scenes/combat_lab.tscn").instantiate()
        viewport.add_child(lab)
        lab.set_physics_process(false)
        if lab.get("stock_label") == null:
            check(false, "visible stock/mode/result HUD exists")
            lab.free()
            viewport.free()
            continue
        lab._process(0)
        var text := ""
        for label in lab.find_children("*", "Label", true, false): text += label.text
        check("33-tick respawn stun" in text and "protection 0" in text and "not new defense" in text, "visible source respawn scope; no invented immunity")
        check("SANDBOX" in lab.stock_label.text and "Reset sandbox" in lab.reset_button.text, "default sandbox label and F3 reset clear")
        lab.start_stock_match()
        lab._process(0)
        check("P1 3" in lab.stock_label.text and "P2 3" in lab.stock_label.text, "both stock counts visible")
        check("Rematch" in lab.reset_button.text and lab.rematch_button.visible, "stock F3 explicitly rematch")
        var snapshot: Dictionary = lab.get_snapshot()
        check(snapshot.get("mode") == "stocks" and snapshot.has("result") and snapshot.actors[0].get("stocks") == 3, "web stock snapshot")
        for i in range(3): await process_frame
        var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
        var arena := Rect2(Vector2(0, viewport_size.y * .27), Vector2(viewport_size.x, viewport_size.y * .52))
        for button in lab.find_children("*", "Button", true, false):
            if not button.visible: continue
            check(bounds.encloses(button.get_global_rect()) and not arena.intersects(button.get_global_rect()), "stock controls on-screen in edge bands")
            check(button.focus_mode == Control.FOCUS_NONE, "stock buttons never steal gameplay keys")
            print("STOCK UI %s %s %s" % [viewport_size, button.text, button.get_global_rect()])
        check(not arena.intersects(lab.stock_label.get_global_rect()), "stock HUD outside central arena")
        # Reviewed bounded-scroll contract: preserve all stock assertions; explanatory scrolling
        # is accepted, but real critical controls must be visible and unclipped.
        for control in [lab.p2_input_button, lab.ai_difficulty_button, lab.comparison_button, lab.pause_button, lab.reset_button, lab.rematch_button]:
            check(control_reachable(control, viewport), "stock critical control visible and unclipped")
        for panel in hud_panels(lab):
            for scroll in panel.get_children():
                if scroll is ScrollContainer:
                    check(scroll.clip_contents, "stock explanatory scrolling stays in edge band")
        for draw in [false, true]:
            lab.rematch_lab()
            lab.simulation.fighters[1].stocks = 1
            lab.actors[0].position.x = -17
            if draw:
                lab.simulation.fighters[2].stocks = 1
                lab.actors[1].position.x = 17
            await tick(lab)
            lab._process(0)
            check(("DRAW" if draw else "WIN — P2") in lab.stock_label.text, "HUD reads committed winner/draw")
            check(lab.get_snapshot().result == lab.simulation.result, "snapshot copies actual result")
        lab.enter_sandbox()
        lab._process(0)
        check(not lab.rematch_button.visible and lab.get_snapshot().mode == "sandbox", "sandbox removes result/rematch mode")
        lab.free()
        viewport.free()
    if failures == 0: print("PASS: stock lab controls committed HUD results and edge-band geometry")
    quit(1 if failures else 0)
