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
    arena.setup.story_requested.emit()
    for i in 2: await process_frame
    var stage = arena.story_panel.find_child("StoryStage", true, false)
    check(stage != null, "story stage exists")
    if stage != null:
        var roster = load("res://scripts/roster.gd")
        var playable: Array = roster.ids()
        playable.erase("ice_mage")
        var cards: Array = stage.get_cards()
        check(cards.size() == 6, "six fighter cards")
        var hand = stage.cursor
        check(hand != null and hand.targets.size() >= 6, "hand cursor registered on cards")
        check(cards[0].name == "FighterCard0", "card naming")
        if cards.size() == 6:
            var label := cards[2].get_child(1) as Label
            check(label != null and label.text == roster.display_name(playable[2]).to_upper(), "card label matches roster")
            check(hand.is_carrying(), "hand carries the chip before a pick")
            check(hand.active_texture() == hand._tex_carry, "carry pose while carrying")
            check(not hand.press_frame_enabled, "no tap frame during the selection")
            hand._press = 0.2
            check(hand.active_texture() == hand._tex_carry, "carry pose wins over the tap frame")
            hand._press = 0.0
            cards[2].pressed.emit()
            check(stage.get_selected_id() == playable[2], "card press selects id")
            check(arena.story_character.get_selected_metadata() == playable[2], "selection model synced")
            check(not hand.is_carrying(), "chip released on pick")
            await create_timer(0.7).timeout
            check(stage.is_chip_landed(), "chip placed")
            var chip_pos: Vector2 = stage.get_chip_position()
            check(cards[2].get_global_rect().grow(12.0).has_point(chip_pos), "chip set down on the picked card")
            check(not cards[1].get_global_rect().has_point(chip_pos), "chip not on another card")
            arena.story_action.pressed.emit()
            check(arena.player_one.character_id == playable[2], "encounter starts with card choice")
            check(arena.story_state == "playing", "story running")
            hand._pressed_held = true
            check(hand.active_texture() == hand._tex_press, "tap frame while the button is held")
            hand._pressed_held = false
            hand._press = 0.0
            check(hand.active_texture() != hand._tex_press, "tap frame ends on release")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: story stage cards, hand cursor, model sync, encounter start")
    quit(1 if failures else 0)
