extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func make_key(code: int) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    return event
func run():
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    for i in 5: await process_frame
    var slots = load("res://scripts/match_config.gd").default_slots()
    check(arena.start_match(slots, false), "match starts")
    for fighter in arena.fighters:
        fighter.set_physics_process(false)
    # finish it: only P4 survives
    arena.fighters[0].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[0])
    arena.fighters[1].stocks = 0
    arena.fighters[2].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[2])
    check(arena.match_over and arena.result_panel.visible, "result panel shows at match end")
    check(arena.winner_label.visible and "P4" in arena.winner_label.text, "winner banner is up immediately")
    var rs = arena.result_panel.find_child("ResultScreen", true, false)
    check(rs != null, "result screen exists")
    if rs == null:
        arena.queue_free()
        await process_frame
        quit(1)
        return
    check(rs.is_waiting(), "160-tick wait phase first (gmresult x1==0)")
    check(rs.get_page_count() == 4, "one page per active player")
    check(rs.get_page_name() == "TEKNIUM", "page 0 shows the first player")
    check(rs.get_page_stocks() == 0, "eliminated first player reads OUT")
    arena._unhandled_key_input(make_key(KEY_SPACE))
    check(not rs.is_waiting() and rs.get_page_index() == 0, "first input starts the panels without navigating")
    arena._unhandled_key_input(make_key(KEY_RIGHT))
    check(rs.get_page_index() == 1, "right walks the pages")
    arena._unhandled_key_input(make_key(KEY_LEFT))
    arena._unhandled_key_input(make_key(KEY_LEFT))
    check(rs.get_page_index() == 3, "left wraps around to the last page")
    check(rs.get_page_name() == "TURBOFIT", "page 3 shows the survivor")
    check(rs.get_page_stocks() == 3, "survivor still holds three stocks")
    arena.find_child("Rematch", true, false).pressed.emit()
    check(not arena.result_panel.visible and arena.ready_remaining > 0, "rematch hides results and restarts the countdown")
    check(not arena.match_over and arena.fighters.size() == 4, "rematch rebuilds the match")
    # second finish: without input the panels auto-start after 160 ticks
    for fighter in arena.fighters:
        fighter.set_physics_process(false)
    arena.fighters[0].stocks = 0
    arena.fighters[1].stocks = 0
    arena.fighters[2].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[2])
    check(arena.result_panel.visible and rs.is_waiting(), "result again in the wait phase")
    await create_timer(2.8).timeout
    check(not rs.is_waiting(), "no input: panels auto-start after 160 ticks")
    arena.find_child("ChangeFighters", true, false).pressed.emit()
    check(arena.setup.visible and not arena.result_panel.visible, "change fighters returns to the setup")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: result screen (banner, 160-tick wait, page walk, rematch, change fighters)")
    quit(1 if failures else 0)
