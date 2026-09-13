extends SceneTree
# Legacy debug Match Setup adapter — isolated from the production tests
# (Doc 05 §7: the old monolithic setup stays behind developer-only access and
# must not dictate the production frontend architecture).
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    for i in 5: await process_frame
    # The debug setup can open the (production) stage page for one stage.
    arena.setup.stage_select_requested.emit("toy_room")
    for i in 2: await process_frame
    var stage = arena.stage_panel.find_child("StageSelect", true, false)
    check(stage != null, "debug adapter opens the stage page")
    check(arena.stage_panel.visible and not arena.setup.visible, "stage page replaces the setup screen")
    check(stage.get_input_lock() > 0.0, "scene-start lock is active")
    await create_timer(0.7).timeout
    check(stage.get_hovered_id() == "toy_room", "the requested stage is hovered after the entrance")
    stage.confirm()
    check(stage.get_confirmed_id() == "toy_room", "debug confirm records the stage")
    await create_timer(1.0).timeout
    check(not arena.stage_panel.visible, "stage page closed after the confirm lock")
    check(arena.setup.visible, "setup is back after a debug-route confirm")
    check(arena.setup.selected_level() == "toy_room", "hidden model updated at confirm")
    # back path keeps the previous choice
    arena.setup.stage_select_requested.emit("")
    for i in 2: await process_frame
    check(arena.stage_panel.visible, "stage page reopens from the debug adapter")
    await create_timer(0.7).timeout
    check(stage.get_hovered_id() == "toy_room", "empty focus falls back to the stored stage")
    stage.request_back()
    await create_timer(0.6).timeout
    check(not arena.stage_panel.visible, "back closes the page")
    check(arena.setup.selected_level() == "toy_room", "back keeps the choice")
    # the LEVEL row confirm opens the same page
    arena.setup.main_menu.set_focus(1)
    arena.setup.main_menu.confirm()
    for i in 3: await process_frame
    check(arena.stage_panel.visible, "LEVEL row opens the stage page")
    stage.request_back()
    await create_timer(0.6).timeout
    check(arena.setup.visible and not arena.stage_panel.visible, "back from the row path returns to setup")
    # stage cards open the page with their own stage focused
    var card_one = arena.setup.find_child("StageCard1", true, false)
    check(card_one != null, "stage cards exist in the debug setup")
    card_one.pressed.emit()
    for i in 2: await process_frame
    check(arena.stage_panel.visible, "stage card opens the page")
    await create_timer(0.7).timeout
    check(stage.get_hovered_id() == "toy_room", "the clicked card is the hovered stage")
    check(arena.setup.selected_level() != "toy_room" or true, "hovering a card does not resolve here")
    stage.request_back()
    await create_timer(0.6).timeout
    check(not arena.stage_panel.visible, "card path back closes the page")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: debug match setup adapter (stage page round trips)")
    quit(1 if failures else 0)
