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
    check(arena.has_method("open_char_select"), "arena exposes the character page")
    # enter through the real chain: PLAYER 2 row -> subpage -> FIGHTER row
    await create_timer(0.4).timeout
    setup.main_menu.set_focus(3)
    setup.main_menu.confirm()
    await create_timer(0.5).timeout
    check(setup.player_menu.visible, "player subpage open")
    await create_timer(0.3).timeout
    setup.player_menu.set_focus(1)
    setup.player_menu.confirm()
    for i in 3: await process_frame
    var page = arena.char_panel.find_child("CharSelect", true, false)
    check(page != null, "character page exists")
    if page == null:
        arena.queue_free()
        await process_frame
        quit(1)
        return
    check(arena.char_panel.visible and not setup.visible, "character page replaces the setup")
    var cards: Array = page.get_cards()
    check(cards.size() == 7, "seven fighter cards")
    check(cards[0].name == "FighterCard0", "card naming")
    var label := cards[3].get_child(1) as Label
    check(label != null and label.text == "TURBOFIT", "card label matches the roster")
    var hand = page.cursor
    check(hand != null, "hand bound")
    check(page.get_input_lock() > 0.0, "scene-start lock active")
    check(hand.is_carrying(), "hand carries the token at open")
    check(not hand.press_frame_enabled, "no tap frame during the selection")
    check(page.get_hovered_id() == "", "no hover during the entrance")
    await create_timer(0.8).timeout
    check(page.get_hovered_id() == "doge_man", "focus id hovered after the entrance")
    check(page.get_box_visible(), "highlight box on the hovered card")
    check(page.get_name_text() == "DOGE MAN", "name display follows the hover")
    cards[0].pressed.emit()
    check(page.get_hovered_id() == "teknium", "first press moves the hover")
    check(page.get_confirmed_id() == "", "no confirm on a hover move")
    cards[0].pressed.emit()
    check(page.get_confirmed_id() == "teknium", "second press confirms")
    check(page.is_confirming(), "confirm lock engaged")
    check(setup.rows[1].character.selected == 0, "hidden model updated at confirm")
    check(not hand.is_carrying(), "token released on confirm")
    cards[4].pressed.emit()
    check(page.get_confirmed_id() == "teknium", "presses swallowed while confirming")
    await create_timer(0.4).timeout
    check(page.is_chip_landed(), "token set down")
    var chip_pos: Vector2 = page.get_chip_position()
    check(cards[0].get_global_rect().grow(12.0).has_point(chip_pos), "token set down on the picked card")
    check(not cards[1].get_global_rect().has_point(chip_pos), "token not on another card")
    await create_timer(0.7).timeout
    check(not arena.char_panel.visible, "character page closed after the confirm lock")
    check(setup.visible, "setup is back")
    check(setup.player_menu.visible, "back on the player subpage (entry row rule)")
    check(setup.player_menu.focus == 1, "focus landed on the FIGHTER row")
    check(setup.rows[1].character.selected == 0, "the chosen fighter sticks")
    await create_timer(0.4).timeout
    setup.player_menu.set_focus(5)
    setup.player_menu.confirm()
    await create_timer(0.5).timeout
    check(setup.main_menu.visible, "back to the main list")
    check("Teknium" in str(setup.main_menu.rows[3]["label"]), "main list row shows the new fighter")
    # back path keeps the previous choice
    setup.main_menu.set_focus(3)
    setup.main_menu.confirm()
    await create_timer(0.5).timeout
    await create_timer(0.3).timeout
    setup.player_menu.set_focus(1)
    setup.player_menu.confirm()
    for i in 3: await process_frame
    check(arena.char_panel.visible, "character page reopens")
    await create_timer(0.8).timeout
    check(page.get_hovered_id() == "teknium", "empty focus falls back to the current fighter")
    page.request_back()
    check(page.is_exiting(), "back exits")
    await create_timer(0.6).timeout
    check(not arena.char_panel.visible and setup.visible, "back closes the page")
    check(setup.player_menu.visible, "back lands on the subpage")
    check(setup.rows[1].character.selected == 0, "back keeps the choice")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: character page (grid, hand+token, confirm/back, entry row return, model sync)")
    quit(1 if failures else 0)
