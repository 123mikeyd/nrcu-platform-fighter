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
    check(arena.has_method("open_vs"), "arena exposes the VS entry")
    # player-facing entry: home sets the mode, main opens the CSS
    arena.open_vs()
    for i in 2: await process_frame
    var css = arena.char_panel.find_child("CharSelect", true, false)
    check(css != null, "character select exists")
    if css == null:
        arena.queue_free()
        await process_frame
        quit(1)
        return
    check(arena.char_panel.visible and not arena.setup.visible, "VS entry shows the CSS, not the setup")
    check(arena.selection_state != null, "persistent selection state created")
    var state = arena.selection_state
    check(state.slots.size() == 4, "four player slots in the state")
    var cards: Array = css.get_cards()
    check(cards.size() == 7, "seven fighter cards")
    var kind1 = css.find_child("PanelKind1", true, false)
    var diff1 = css.find_child("PanelDiff1", true, false)
    var team0 = css.find_child("PanelTeam0", true, false)
    var box1 = css.find_child("PanelBox1", true, false)
    var mode = css.find_child("ModeToggle", true, false)
    var ready = css.find_child("ReadyButton", true, false)
    check(kind1 != null and diff1 != null and team0 != null and box1 != null and mode != null and ready != null, "CSS panels and controls exist")
    check(state.slots[1].kind == "bot" and diff1.visible, "default P2 is a CPU with a difficulty cell")
    check(not team0.visible, "team cells hidden in free-for-all")
    kind1.pressed.emit()
    check(state.slots[1].kind == "empty", "kind cycles bot -> empty")
    check(not diff1.visible, "difficulty hides for empty")
    kind1.pressed.emit()
    check(state.slots[1].kind == "human", "kind cycles empty -> human")
    kind1.pressed.emit()
    check(state.slots[1].kind == "bot", "kind cycles human -> bot")
    var before_diff: String = str(state.slots[1].difficulty)
    diff1.pressed.emit()
    check(str(state.slots[1].difficulty) != before_diff, "difficulty cycles on the CPU panel")
    mode.pressed.emit()
    check(state.mode == 1, "mode toggle switches to teams")
    check(team0.visible, "team cells appear in team mode")
    team0.pressed.emit()
    check(int(state.slots[0].team) == 1, "team cell flips A -> B")
    mode.pressed.emit()
    check(state.mode == 0, "mode toggles back")
    # wait out the scene-start entry before the card presses (Melee-style
    # input lock, same as the other screens)
    await create_timer(0.7).timeout
    # assignment: the active panel (P1) receives the clicked fighter
    cards[2].pressed.emit()
    check(str(state.slots[0].character) == "ggb", "card press assigns to the active panel")
    box1.pressed.emit()
    check(css.get_active() == 1, "panel click activates that player")
    cards[0].pressed.emit()
    check(str(state.slots[1].character) == "teknium", "next card press goes to the activated panel")
    # ready gating mirrors match_config.validate
    var kind2 = css.find_child("PanelKind2", true, false)
    var kind3 = css.find_child("PanelKind3", true, false)
    kind2.pressed.emit()
    kind3.pressed.emit()
    check(state.active_count() == 2 and state.can_ready(), "two active fighters can ready")
    kind1.pressed.emit()
    check(state.active_count() == 1 and not state.can_ready(), "one fighter cannot ready")
    check(ready.disabled, "READY is disabled below the minimum")
    ready.pressed.emit()
    check(arena.char_panel.visible, "READY without the minimum does nothing")
    kind1.pressed.emit()
    check(state.active_count() == 2 and state.can_ready(), "config valid again")
    # chip flow: the token is set down on the assigned card
    var hand = css.cursor
    check(not hand.is_carrying(), "token released on the first assignment")
    await create_timer(0.4).timeout
    check(css.is_chip_landed(), "token set down")
    var chip_pos: Vector2 = css.get_chip_position()
    check(cards[0].get_global_rect().grow(12.0).has_point(chip_pos), "token set down on the assigned card")
    # READY -> stage page
    ready.pressed.emit()
    check(css.is_exiting(), "READY exits the CSS")
    await create_timer(0.6).timeout
    check(not arena.char_panel.visible and arena.stage_panel.visible, "stage page opens after READY")
    var sss = arena.stage_panel.find_child("StageSelect", true, false)
    check(sss != null, "stage page exists")
    await create_timer(0.6).timeout
    check(sss.get_hovered_id() == str(state.stage), "stage page starts on the stored stage")
    # back from the stage page returns to the CSS with everything kept
    sss.request_back()
    await create_timer(0.6).timeout
    check(arena.char_panel.visible and not arena.stage_panel.visible, "stage back returns to the CSS")
    check(str(state.slots[0].character) == "ggb" and str(state.slots[1].character) == "teknium", "selections survive the stage round trip")
    # READY again, confirm a stage -> the match launches through start_match
    await create_timer(0.4).timeout
    css.find_child("ReadyButton", true, false).pressed.emit()
    await create_timer(0.7).timeout
    check(arena.stage_panel.visible, "stage page again")
    await create_timer(0.5).timeout
    sss.hover_slot(1)
    check(sss.get_hovered_id() == "toy_room", "hovered toy room")
    sss.confirm()
    check(sss.get_confirmed_id() == "toy_room", "stage confirmed")
    await create_timer(1.0).timeout
    check(not arena.stage_panel.visible and not arena.char_panel.visible, "VS screens closed after the confirm")
    check(arena.active_level == "toy_room", "confirmed stage applied to the match")
    check(arena.fighters.size() == 2, "two fighters from the selection state")
    check(arena.fighters[0].character_id == "ggb" and arena.fighters[1].character_id == "teknium", "fighters match the state")
    check(arena.story_state == "" and arena.match_over == false, "freeplay match running")
    # results: regular cursor, visible actions, change-stage round trip
    for f in arena.fighters:
        f.set_physics_process(false)
    arena.fighters[1].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[1])
    check(arena.result_panel.visible, "result screen after the VS match")
    var rs = arena.result_panel.find_child("ResultScreen", true, false)
    rs.skip_wait()
    var hand2 = arena.get_node_or_null("/root/Cursor").hand
    check(hand2.visible, "results show the regular cursor again")
    check(not hand2.is_carrying(), "no token state leaks into the results")
    var change_stage = arena.find_child("ChangeStage", true, false)
    check(change_stage.visible, "change stage visible in the VS flow")
    change_stage.pressed.emit()
    for i in 2: await process_frame
    check(arena.stage_panel.visible and not arena.result_panel.visible, "change stage opens the stage page")
    await create_timer(0.6).timeout
    sss.request_back()
    await create_timer(0.6).timeout
    check(arena.char_panel.visible, "stage back from the results path lands on the CSS")
    check(str(state.slots[0].character) == "ggb", "fighters preserved through the results round trip")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: VS flow (CSS panels/mode/ready -> SSS -> start_match, state round trip)")
    quit(1 if failures else 0)
