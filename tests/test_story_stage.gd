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
        var hand = stage.find_child("HandCursor", true, false)
        check(hand != null and hand.targets.size() >= 6, "hand cursor registered on cards")
        check(cards[0].name == "FighterCard0", "card naming")
        if cards.size() == 6:
            var label := cards[2].get_child(1) as Label
            check(label != null and label.text == roster.display_name(playable[2]).to_upper(), "card label matches roster")
            cards[2].pressed.emit()
            check(stage.get_selected_id() == playable[2], "card press selects id")
            check(arena.story_character.get_selected_metadata() == playable[2], "selection model synced")
            check(cards[2].get_child(2).visible, "token shown on selected card")
            check(not cards[1].get_child(2).visible, "token hidden elsewhere")
            arena.story_action.pressed.emit()
            check(arena.player_one.character_id == playable[2], "encounter starts with card choice")
            check(arena.story_state == "playing", "story running")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: story stage cards, hand cursor, model sync, encounter start")
    quit(1 if failures else 0)
