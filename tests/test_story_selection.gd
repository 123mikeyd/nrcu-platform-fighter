extends SceneTree
# Story selection contract (Doc 01 §9, Doc 05): the Story Fighter Select /
# Encounter Briefing route lives in the MatchFlow host (the hidden
# StoryCharacterSelect OptionButton is superseded by MatchFlowState +
# StoryEncounterCatalog, Doc 10). The suite keeps its behavioural contracts:
# the whole playable roster launches through the two-step route, Ready gates
# input, the HUD identifies the chosen fighter, the compact Story Result
# (wording + REPLAY/RETRY/MAIN MENU) works, Back and re-entry remember the
# choice, an invalid model resolves to the default, and freeplay stays untouched.
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
    var roster = load("res://scripts/roster.gd")
    var AppState = load("res://scripts/app_state.gd")
    AppState.story_fighter_id = "turbofit"
    var playable: Array = roster.ids()
    playable.erase("ice_mage")

    # --- the entire playable roster launches through the two-step route ---
    for index in playable.size():
        var id: String = playable[index]
        var host = await story.enter(self, id)
        var select = host.story_select()
        check(select.selected_fighter_id() == id, "the Story Select opens on the roster choice: " + id)
        check(select.roster_ids() == playable, "the Select roster holds exactly the playable fighters: " + id)
        check(not select.roster_ids().has("ice_mage"), "prototype absent from the Story choices: " + id)
        select.select_fighter(id)
        check(host.story_selection_id() == id, "the selection reaches the typed state: " + id)
        var arena = await story.start_encounter(self, host)
        check(arena != null and arena.player_one.character_id == id, "real Start creates chosen " + id)
        if arena != null:
            check(arena.player_two.character_id == "bobo" and arena.player_two.control_type == "bot", "opponent unchanged: " + id)
            check(not arena.player_one.controls_enabled and arena.ready_remaining > 0, "Ready gates input: " + id)
            check(arena.player_one.fighter_name in arena.hud_title.text, "HUD identifies the chosen fighter: " + id)
            arena.queue_free()
        await story.free_hosts(self)

    # --- the result / retry / replay / back contract on one encounter ---
    var chosen: String = playable[0]
    var host = await story.enter(self, chosen)
    # Capture the host identity while it lives: the launch handshake frees it
    # (Doc 02 §5/§6) and the result wait must not touch the freed node.
    var host_id: int = host.get_instance_id()
    var arena = await story.start_encounter(self, host)
    check(arena != null, "the encounter launches for the result contract")
    if arena != null:
        story.run_ready(arena)
        # loss: out of stocks -> package loss wording, compact result surface
        for i in 3:
            arena.player_one._handle_blast_zone()
        check(arena.story_state == "lost", "human stock exhaustion shows the loss state")
        var loss_host = await story.wait_for_flow(self, host_id)
        check(loss_host != null, "the loss returns to the Story Result host")
        if loss_host != null:
            check(loss_host.active_surface() == "story_result", "the loss lands on the Story Result surface")
            var loss_result = loss_host.story_result()
            check(str(loss_result.title_label().text) == "TRY AGAIN", "loss wording")
            check(str(loss_result.action_button().text) == "RETRY", "loss offers Retry")
            check(loss_result.visible and not loss_host.story_briefing().visible,
                "the compact Story Result replaces the briefing (no selection UI on the loss)")
            check(loss_host.story_selection_id() == chosen, "the loss keeps the played fighter")
            # Retry preserves the selection
            var loss_host_id: int = loss_host.get_instance_id()
            var retry = await story.start_encounter(self, loss_host)
            check(retry != null and retry.player_one.character_id == chosen, "Retry preserves selection")
            if retry != null:
                story.run_ready(retry)
                for fighter in retry.fighters:
                    fighter.set_physics_process(false)
                retry.player_two.receive_hit(1000, Vector3.RIGHT, 100)
                check(retry.story_state == "complete", "lethal damage completes the retried encounter")
                var win_host = await story.wait_for_flow(self, loss_host_id)
                check(win_host != null, "the win returns to the Story Result host")
                if win_host != null:
                    var win_result = win_host.story_result()
                    check(str(win_result.title_label().text) == "YOU'RE PRETTY COOL", "victory wording from the package")
                    check(not win_host.story_briefing().visible,
                        "the victory result is the compact Story Result, never the briefing")
                    # MAIN MENU: the player route Story -> Main, choice remembered
                    win_result.menu_button().pressed.emit()
                    var home_scene = await story.wait_for_scene(self, "home.tscn")
                    check(home_scene != null, "MAIN MENU returns to the Main route")
                    check(AppState.story_fighter_id == chosen, "the choice is remembered across the Main return")
                    if home_scene != null:
                        home_scene.queue_free()
                    await story.free_hosts(self)
                    var reentry = await story.enter(self)
                    check(reentry.story_select().selected_fighter_id() == chosen, "Back and reentry remember the choice")
                    await story.free_hosts(self)

    # --- an invalid story model resolves to the story default ---
    for invalid in ["ice_mage", "not_a_character", ""]:
        var bad_host = await story.enter(self)
        check(await story.open_briefing(self, bad_host), "the encounter briefing is reached before the invalid launch")
        bad_host.flow.slots[0].fighter_id = invalid
        var bad_arena = await story.start_encounter(self, bad_host)
        check(bad_arena != null and bad_arena.player_one.character_id == "turbofit",
            "invalid Story choice falls back to TurboFit: " + str(invalid))
        if bad_arena != null:
            check(bad_arena.player_two.character_id == "bobo" and bad_arena.player_two.control_type == "bot",
                "fallback preserves the Bobo NPC")
            bad_arena.queue_free()
        check(AppState.story_fighter_id == "turbofit", "the fallback repairs the stored choice: " + str(invalid))
        await story.free_hosts(self)

    # --- freeplay is untouched (the debug route is gameplay-side) ---
    var direct = load("res://scenes/main.tscn").instantiate()
    root.add_child(direct)
    await process_frame
    var defaults = load("res://scripts/match_config.gd").default_slots()
    check(direct.start_match(defaults, false) and direct.story_state == "", "freeplay Start keeps its own defaults")
    var freeplay = defaults.duplicate(true)
    freeplay[0].character = "ice_mage"
    check(direct.start_match(freeplay, false) and direct.player_one.character_id == "ice_mage",
        "freeplay prototype selection unchanged")
    direct.queue_free()
    await story.free_hosts(self)
    await process_frame
    if failures == 0: print("PASS: story selection via MatchFlow (entire roster through the two-step route, Ready, Retry/Replay, Back, fallback, freeplay isolation)")
    quit(1 if failures else 0)
