extends SceneTree
# Story suite migration (Doc 07 §11-16): the legacy StoryStage card row is gone
# by design — Story selection is now the briefing's compact roster strip.
# Asserted against the new structure: the briefing owns the story panel, the
# roster strip lists the playable fighters (prototype Ice Mage excluded),
# select_fighter() selects and the selection is visible on the strip, the
# legacy card/chip nodes are gone, and the Story route still opens from Main,
# launches the encounter and returns to Main.
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
    check(arena.story_state == "ready" and arena.story_panel.visible, "story opens from Main into the ready briefing")
    var briefing = arena.find_child("StoryBriefing", true, false)
    check(briefing != null and briefing == arena.story_panel, "the briefing scene owns the story panel")
    var roster = load("res://scripts/roster.gd")
    var playable: Array = roster.ids()
    playable.erase("ice_mage")
    if briefing != null:
        check(briefing.roster_ids() == playable, "the roster strip lists the playable fighters (Ice Mage excluded)")
        var tiles: Array = briefing.roster_tiles()
        check(tiles.size() == playable.size(), "one roster tile per playable fighter")
        check(briefing.selected_fighter_id() == "turbofit", "the briefing opens on the story default fighter")
        briefing.select_fighter(playable[2])
        check(briefing.selected_fighter_id() == playable[2], "select_fighter selects the id")
        if tiles.size() == playable.size():
            check(tiles[2].is_candidate(), "the selection is visible on the roster strip")
        var zone_name := briefing.get_node_or_null("ReferenceFrame/BriefingBody/FighterZone/FighterName") as Label
        check(zone_name != null and zone_name.text == roster.display_name(playable[2]).to_upper(), "the selection is named on the briefing")
        check(arena.story_character.get_selected_metadata() == playable[2], "the story selection model follows the briefing")
    var cursor_layer = root.get_node_or_null("Cursor")
    check(cursor_layer != null and cursor_layer.hand != null and not cursor_layer.hand.is_carrying(),
        "the briefing never carries the legacy selection chip")
    check(arena.story_panel.find_child("StoryStage", true, false) == null, "the legacy StoryStage card overlay is gone")
    check(arena.story_panel.find_child("FighterCard0", true, false) == null, "the legacy fighter cards are gone")
    check(arena.story_panel.find_child("StoryToken", true, false) == null, "the legacy selection chip is gone")
    arena.story_back.pressed.emit()
    await create_timer(0.4).timeout
    check(arena.setup.visible and arena.story_state == "" and not arena.story_panel.visible, "Back returns to Main without starting")
    arena.setup.story_requested.emit()
    for i in 2: await process_frame
    check(arena.story_state == "ready" and arena.story_panel.visible, "story reopens from Main")
    check(briefing.selected_fighter_id() == playable[2], "reentry keeps the roster choice")
    arena.story_action.pressed.emit()
    check(arena.story_state == "playing" and arena.player_one.character_id == playable[2],
        "START ENCOUNTER launches the encounter with the roster choice")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: story briefing roster strip, selection sync, legacy nodes gone, route open/launch/back")
    quit(1 if failures else 0)
