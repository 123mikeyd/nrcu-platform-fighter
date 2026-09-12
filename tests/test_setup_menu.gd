extends SceneTree
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
    var setup = arena.setup
    check(setup.main_menu.visible and not setup.player_menu.visible, "main list shown, subpage hidden")
    check(setup.main_menu.rows.size() == 6, "main list has mode, level and four players")
    await create_timer(0.4).timeout
    # open player 2's subpage through the list
    setup.main_menu.set_focus(3)
    setup.main_menu.confirm()
    await create_timer(0.5).timeout
    check(setup.player_menu.visible and not setup.main_menu.visible, "player subpage opens")
    check(setup.player_menu.rows.size() == 6, "subpage rows: kind..input + back")
    # change a value and check it wrote into the hidden model
    await create_timer(0.15).timeout
    setup.player_menu.set_focus(0)
    setup.player_menu.adjust(1)
    check(setup.rows[1].kind.selected == 2, "subpage writes into the hidden dropdown (Bot -> Empty)")
    await create_timer(0.15).timeout
    # back lands on the player row we entered from (reference rule)
    setup.player_menu.set_focus(5)
    setup.player_menu.confirm()
    await create_timer(0.5).timeout
    check(setup.main_menu.visible and not setup.player_menu.visible, "back returns to the main list")
    check(setup.main_menu.focus == 3, "back lands on the entry option (player 2)")
    # mode row drives the hidden dropdown
    await create_timer(0.15).timeout
    setup.main_menu.set_focus(0)
    setup.main_menu.adjust(1)
    check(setup.mode.selected == 1, "mode row drives its dropdown")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: setup menu layer (subpages, writeback, back-to-entry rule)")
    quit(1 if failures else 0)
