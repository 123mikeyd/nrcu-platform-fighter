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
    var choice = arena.story_panel.find_child("StoryCharacterSelect", true, false)
    check(choice != null, "story intro must offer playable character selection instead of hardcoded TurboFit")
    if choice != null:
        var roster = load("res://scripts/roster.gd")
        var playable = roster.ids()
        playable.erase("ice_mage")
        check(choice.item_count == 6 and choice.item_count == playable.size(), "six Story choices: prototype Ice Mage excluded")
        for index in choice.item_count:
            check(choice.get_item_metadata(index) != "ice_mage", "prototype absent from Story choices")
        arena.setup._start()
        var previous = arena.active_slots.duplicate(true)
        for index in playable.size():
            arena.open_story()
            choice.select(index)
            choice.item_selected.emit(index)
            arena.story_action.pressed.emit()
            check(choice.get_item_metadata(index) == playable[index] and choice.get_item_text(index) == roster.display_name(playable[index]), "filtered labels and IDs retain roster order")
            check(arena.player_one.character_id == playable[index], "real Start creates chosen " + playable[index])
            check(arena.player_two.character_id == "bobo" and arena.player_two.control_type == "bot", "opponent unchanged")
            check(not arena.player_one.controls_enabled and arena.ready_remaining > 0, "Ready gates input")
            check(arena.player_one.fighter_name in arena.hud_title.text, "HUD identifies chosen fighter")
            arena.player_one.stocks = 0
            arena._on_fighter_eliminated(arena.player_one)
            check(arena.story_title.text == "TRY AGAIN" and not choice.is_visible_in_tree(), "loss wording and locked selection")
            check(not arena.story_panel.find_child("RosterStrip", true, false).is_visible_in_tree(),
                "the loss result locks the briefing selection away")
            arena.story_action.pressed.emit()
            check(arena.player_one.character_id == playable[index], "Retry preserves selection")
            arena.player_two.stocks = 0
            arena._on_fighter_eliminated(arena.player_two)
            check(arena.story_title.text == "your pretty cool", "literal victory wording")
            check(not arena.story_panel.find_child("RosterStrip", true, false).is_visible_in_tree(),
                "the victory result locks the briefing selection away")
            arena._reset_match()
            check(arena.player_one.character_id == playable[index], "Replay preserves selection")
            arena.story_back.pressed.emit()
            arena.open_story()
            check(choice.selected == index, "Back and reentry remember choice")
        arena.story_back.pressed.emit()
        arena.setup._start()
        check(arena.story_state == "" and arena.active_slots == previous, "cancel returns to original freeplay")
        var freeplay = previous.duplicate(true)
        freeplay[0].character = "ice_mage"
        check(arena.start_match(freeplay, false) and arena.player_one.character_id == "ice_mage", "freeplay prototype selection unchanged")
        for invalid in ["ice_mage", "not_a_character", null]:
            arena.open_story()
            choice.add_item("Stale programmatic choice")
            var stale_index = choice.item_count - 1
            choice.set_item_metadata(stale_index, invalid)
            choice.select(stale_index)
            arena.story_action.pressed.emit()
            check(arena.player_one.character_id == "turbofit", "invalid Story choice falls back to TurboFit: " + str(invalid))
            check(arena.player_two.character_id == "bobo" and arena.player_two.control_type == "bot", "fallback preserves Bobo NPC")
            check(choice.get_selected_metadata() == "turbofit", "fallback repairs selection for reentry")
            arena._reset_match()
            check(arena.player_one.character_id == "turbofit", "fallback remains safe on restart")
            choice.remove_item(stale_index)
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: story selection entire playable roster, Start, Ready, Retry, Replay, Back and freeplay isolation")
    quit(1 if failures else 0)
