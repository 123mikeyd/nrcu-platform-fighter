extends SceneTree
# Story suite migration (Doc 07 §11-16) — MIGRATED for WP-0 step 4: the Story
# route (Fighter Select/Briefing) is owned by the MatchFlow host. The legacy
# StoryStage card row is gone by design — Story selection is the briefing's
# compact roster strip, hosted OUTSIDE gameplay.
#
# Asserted against the new route: the host owns the story surface, the roster
# strip lists the encounter's playable fighters (prototype Ice Mage excluded),
# select_fighter() selects and the selection is visible on the strip, the legacy
# card/chip nodes are gone, the selection reaches the typed state, Back returns
# to Main with the choice preserved, and START ENCOUNTER launches the encounter
# with the roster choice.
var failures := 0
var story

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func run():
    root.size = Vector2i(1280, 720)
    story = load("res://tests/fixtures/story_route.gd").new()
    var AppState = load("res://scripts/app_state.gd")
    AppState.story_fighter_id = "turbofit"
    var host = await story.enter(self)
    check(host.entry_mode() == "story" and host.active_surface() == "story",
        "story opens from Main into the host's briefing surface")
    var briefing = host.story_briefing()
    check(briefing != null and briefing.get_parent().get_parent() == host,
        "the briefing scene is a child of the MatchFlow host")
    var roster = load("res://scripts/roster.gd")
    var playable: Array = roster.ids()
    playable.erase("ice_mage")
    check(briefing.roster_ids() == playable, "the roster strip lists the playable fighters (Ice Mage excluded)")
    var tiles: Array = briefing.roster_tiles()
    check(tiles.size() == playable.size(), "one roster tile per playable fighter")
    check(briefing.selected_fighter_id() == "turbofit", "the briefing opens on the story default fighter")
    check(host.story_selection_id() == "turbofit", "the typed state carries the same default")
    briefing.select_fighter(playable[2])
    check(briefing.selected_fighter_id() == playable[2], "select_fighter selects the id")
    if tiles.size() == playable.size():
        check(tiles[2].is_candidate(), "the selection is visible on the roster strip")
    var zone_name := briefing.get_node_or_null("ReferenceFrame/BriefingBody/FighterZone/FighterName") as Label
    check(zone_name != null and zone_name.text == roster.display_name(playable[2]).to_upper(), "the selection is named on the briefing")
    check(host.story_selection_id() == playable[2], "the story selection reaches the typed state (the MatchFlowState authority)")
    check(AppState.story_fighter_id == playable[2], "the selection is carried across the route returns")
    var cursor_layer = root.get_node_or_null("Cursor")
    check(cursor_layer != null and cursor_layer.hand != null and not cursor_layer.hand.is_carrying(),
        "the briefing never carries the legacy selection chip")
    check(briefing.find_child("StoryStage", true, false) == null, "the legacy StoryStage card overlay is gone")
    check(briefing.find_child("FighterCard0", true, false) == null, "the legacy fighter cards are gone")
    check(briefing.find_child("StoryToken", true, false) == null, "the legacy selection chip is gone")
    # --- Back: the player route Story -> Main, with the choice preserved ---
    briefing.back_button().pressed.emit()
    var home_scene = await story.wait_for_scene(self, "home.tscn")
    check(home_scene != null, "Back returns to Main without starting")
    check(AppState.story_fighter_id == playable[2], "Back preserves the roster choice")
    if home_scene != null:
        home_scene.queue_free()
    await story.free_hosts(self)
    check(root.get_node_or_null("MainArena") == null, "no arena was ever constructed for a Back return")
    # --- re-entry: the briefing restores the choice ---
    var reentry = await story.enter(self)
    check(reentry.story_briefing().selected_fighter_id() == playable[2], "reentry keeps the roster choice")
    # --- START: the encounter launches with the roster choice ---
    var arena = await story.start_encounter(self, reentry)
    check(arena != null and arena.story_state == "playing" and arena.player_one.character_id == playable[2],
        "START ENCOUNTER launches the encounter with the roster choice")
    check(arena.player_two.character_id == "bobo" and arena.player_two.control_type == "bot", "the opponent is the encounter NPC")
    check(not is_instance_valid(reentry), "the host released the flow into gameplay")
    arena.queue_free()
    await story.free_hosts(self)
    if failures == 0: print("PASS: story briefing hosted by MatchFlow (roster strip, selection sync, legacy nodes gone, route open/launch/back)")
    quit(1 if failures else 0)
