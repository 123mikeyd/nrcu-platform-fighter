extends SceneTree
# Story suite migration (Doc 07 §11-16, Doc 01 §9) — the Story route is
# TWO-STEP and owned by the MatchFlow host: Story Fighter Select -> Encounter
# Briefing -> gameplay. The legacy StoryStage card row is gone by design; the
# roster lives on the Select (the Briefing has no embedded strip).
#
# Asserted against the route: the host opens on the Select, the roster lists the
# encounter's playable fighters (prototype Ice Mage excluded), select_fighter()
# selects and the selection is visible on the strip, the legacy card/chip nodes
# are gone, the Briefing presents the committed choice after Continue, Briefing
# Back returns to the Select (choice preserved), Select Back returns to Main
# with the choice preserved, and START ENCOUNTER launches the encounter with the
# roster choice.
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
    check(host.entry_mode() == "story" and host.active_surface() == "story_select",
        "story opens from Main into the host's Story Fighter Select")
    var select = host.story_select()
    check(select != null and select.get_parent().get_parent() == host,
        "the Story Select scene is a child of the MatchFlow host")
    var roster = load("res://scripts/roster.gd")
    var playable: Array = roster.ids()
    playable.erase("ice_mage")
    check(select.roster_ids() == playable, "the Story Select lists the playable fighters (Ice Mage excluded)")
    var tiles: Array = select.roster_tiles()
    check(tiles.size() == playable.size(), "one roster tile per playable fighter")
    check(select.selected_fighter_id() == "turbofit", "the Select opens on the story default fighter")
    check(host.story_selection_id() == "turbofit", "the typed state carries the same default")
    select.select_fighter(playable[2])
    check(select.selected_fighter_id() == playable[2], "select_fighter selects the id")
    if tiles.size() == playable.size():
        check(tiles[2].is_candidate(), "the selection is visible on the roster strip")
    check(host.story_selection_id() == playable[2], "the story selection reaches the typed state (the MatchFlowState authority)")
    check(AppState.story_fighter_id == playable[2], "the selection is carried across the route returns")
    var cursor_layer = root.get_node_or_null("Cursor")
    check(cursor_layer != null and cursor_layer.hand != null and not cursor_layer.hand.is_carrying(),
        "the Story route never carries the legacy selection chip")
    var briefing = host.story_briefing()
    check(briefing.find_child("StoryStage", true, false) == null, "the legacy StoryStage card overlay is gone")
    check(briefing.find_child("FighterCard0", true, false) == null, "the legacy fighter cards are gone")
    check(briefing.find_child("StoryToken", true, false) == null, "the legacy selection chip is gone")
    check(briefing.find_child("RosterStrip", true, false) == null, "the Briefing has no embedded roster strip (Doc 05)")
    # --- step 2: Continue reaches the Briefing, which presents the commitment ---
    check(await story.open_briefing(self, host), "Continue steps the Select into the Encounter Briefing")
    check(briefing.visible, "the Briefing is presented after the Select step")
    var zone_name := briefing.get_node_or_null("ReferenceFrame/BriefingBody/FighterZone/FighterName") as Label
    check(zone_name != null and zone_name.text == roster.display_name(playable[2]).to_upper(),
        "the selection is named on the briefing")
    check(briefing.selected_fighter_id() == playable[2], "the Briefing presents the committed fighter")
    # --- Back from the Briefing: Story Fighter Select (Doc 01 §9 / Doc 03 §11) ---
    briefing.back_button().pressed.emit()
    var back_reached: bool = await story.wait_for(self, func() -> bool:
        return host.active_surface() == "story_select" and select.visible, 240)
    check(back_reached, "the Briefing Back returns to the Story Fighter Select")
    check(select.selected_fighter_id() == playable[2], "the Briefing Back preserves the committed fighter")
    # --- Back from the Select: the player route Story -> Main ---
    select.back_button().pressed.emit()
    var home_scene = await story.wait_for_scene(self, "home.tscn")
    check(home_scene != null, "the Select Back returns to Main without starting")
    check(AppState.story_fighter_id == playable[2], "Back preserves the roster choice")
    if home_scene != null:
        home_scene.queue_free()
    await story.free_hosts(self)
    check(root.get_node_or_null("MainArena") == null, "no arena was ever constructed for a Back return")
    # --- re-entry: the Select restores the choice ---
    var reentry = await story.enter(self)
    check(reentry.story_select().selected_fighter_id() == playable[2], "reentry keeps the roster choice")
    # --- START: the encounter launches with the roster choice ---
    var arena = await story.start_encounter(self, reentry)
    check(arena != null and arena.story_state == "playing" and arena.player_one.character_id == playable[2],
        "START ENCOUNTER launches the encounter with the roster choice")
    check(arena.player_two.character_id == "bobo" and arena.player_two.control_type == "bot", "the opponent is the encounter NPC")
    check(not is_instance_valid(reentry), "the host released the flow into gameplay")
    arena.queue_free()
    await story.free_hosts(self)
    if failures == 0: print("PASS: story two-step route hosted by MatchFlow (Select roster, commitment, Briefing, Briefing->Select->Main Back chain, launch)")
    quit(1 if failures else 0)
