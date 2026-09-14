extends SceneTree
# MatchFlow STORY route contract — corrective package Doc 02 §1 (boundary), §3
# (story payload in the immutable launch config), §5 (router verbs), §6
# (destination readiness), §10 step 4; Doc 01 §9 (story flow; the shipped
# briefing visuals are unchanged — WP-4 owns the redesign), Doc 07 §11-16 and
# Doc 10 (supersession: the hidden production StoryCharacterSelect and the
# in-gameplay story panel are gone).
#
# Protected contract (WP-0 step 4):
#   * STORY MODE reaches the MatchFlow host in story mode; the Encounter
#     Briefing is a CHILD of the host, outside gameplay;
#   * no arena exists while the briefing is up (WP-0 gate);
#   * START ENCOUNTER freezes a story MatchLaunchConfig (encounter id + selected
#     fighter + the encounter stage from the catalog) and launches gameplay
#     through the SAME §6 handshake as the VS path (constructed hidden,
#     presentation_ready, released after ready, match started from the config);
#   * gameplay carries the Story state machine over the payload and the Story
#     Result is presented by the host (the frontend owns the post-match surface);
#   * Back keeps working (selection preserved) and the Story Result keeps its
#     shipped wording + REPLAY/RETRY + MAIN MENU.

const StateScript = preload("res://scripts/match_flow_state.gd")
const EncounterCatalog = preload("res://scripts/catalogs/story_encounter_catalog.gd")
const AppStateScript = preload("res://scripts/app_state.gd")

const ENCOUNTER := "story_01"

var failures := 0
var story                     # tests/fixtures/story_route.gd helper

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func frames(count: int) -> void:
    for i in count:
        await process_frame

func encounter_stage() -> String:
    return str(EncounterCatalog.by_id(ENCOUNTER).get("stage_id", ""))

func run() -> void:
    story = load("res://tests/fixtures/story_route.gd").new()
    AppStateScript.story_fighter_id = "turbofit"
    await part_a_host_composition()
    await part_b_story_entry_from_main()
    await part_c_story_launch_from_config()
    await part_d_selection_and_back()
    await part_e_story_result_and_replay()
    await part_f_superseded_story_code_removed()
    if failures > 0:
        print("FAILURES: %d" % failures)
        quit(1)
        return
    print("PASS: MatchFlow story route (host-owned briefing, story launch config, handshake, selection/back return, Story Result replay)")
    quit(0)

# ---------------------------------------------------------------------------
# Part A — the host owns the Story surface (no arena while briefing)
# ---------------------------------------------------------------------------
func part_a_host_composition() -> void:
    print("--- part A: host owns the Story surface ---")
    var host = await story.enter(self)
    check(host.has_method("open_story") and host.has_method("story_briefing"),
        "MatchFlow exposes the Story verb and its surface read")
    check(host.entry_mode() == "story" and host.is_story_mode(), "the host entered Story mode")
    check(host.active_surface() == "story", "a fresh Story flow activates the briefing surface")
    check(host.route_stack_names() == ["story"], "the route stack starts at the Story surface")
    check(host.presented_surfaces() == ["story"], "exactly one surface is presented (the briefing)")
    check(host.input_scope() == "frontend", "the flow claims the frontend input scope while active")
    check(root.get_node_or_null("MainArena") == null and host.gameplay_node() == null,
        "gameplay does not exist while briefing (WP-0 gate)")
    var briefing = host.story_briefing()
    check(briefing != null and briefing.get_parent() != null and briefing.get_parent().get_parent() == host,
        "the Encounter Briefing is a CHILD of the MatchFlow host")
    check(not (briefing is Node3D), "the briefing is a frontend Control, not gameplay")
    check(host.story_encounter_id() == ENCOUNTER, "the host presents encounter 01 from the catalog")
    check(host.story_selection_id() == "turbofit", "the story state opens on the encounter default fighter")
    var allowed: Array = []
    for id in host.story_playable_ids():
        allowed.append(str(id))
    check(allowed == EncounterCatalog.allowed_fighter_ids(ENCOUNTER),
        "the briefing roster comes from the encounter catalog (never a hidden control)")
    check(briefing.selected_fighter_id() == "turbofit", "the briefing opens on the story default fighter")
    check(str(briefing.action_button().text) == "START ENCOUNTER", "the briefing exposes START ENCOUNTER")
    check(str(briefing.back_button().text) == "BACK", "the briefing keeps its Back affordance")
    await story.free_hosts(self)

# ---------------------------------------------------------------------------
# Part B — Main's STORY MODE row is the production entry
# ---------------------------------------------------------------------------
func part_b_story_entry_from_main() -> void:
    print("--- part B: STORY MODE enters MatchFlow ---")
    var home = load("res://scenes/home.tscn").instantiate()
    root.add_child(home)
    await frames(45)
    var rows: Array = home.menu_rows()
    check(rows.size() == 4, "the Main Menu still carries its four destinations")
    if rows.size() != 4:
        home.queue_free()
        return
    var story_row: Control = rows[1]
    check(str(story_row.get_node("Label").text) == "STORY MODE", "row 2 is STORY MODE (no encounter details)")
    var events_node = root.get_node("FrontendEvents")
    var seen: Array = []
    events_node.confirm.connect(func(id: String) -> void: seen.append(id))
    var hit: Button = story_row.get_node("HitArea")
    hit.pressed.emit()
    var host = await story.wait_for_flow(self)
    check(host != null, "STORY MODE reaches the MatchFlow host")
    check(seen.has("main_story"), "the STORY MODE row reports an accepted semantic confirm")
    if home.is_inside_tree():
        home.queue_free()
    await frames(3)
    if host == null:
        return
    check(host.entry_mode() == "story" and host.active_surface() == "story",
        "the production Story route enters the host in story mode on the briefing")
    check(root.get_node_or_null("MainArena") == null, "no arena exists on the way into the briefing")
    check(host.surface_root_alpha("story") > 0.0, "the briefing is presented visibly on entry")
    var briefing = host.story_briefing()
    check(briefing != null and briefing.visible, "the hosted briefing is visible")
    check(AppStateScript.enter_mode == "debug", "the entry flag is consumed by the host")
    await story.free_hosts(self)

# ---------------------------------------------------------------------------
# Part C — START produces the story launch config and the §6 handshake
# ---------------------------------------------------------------------------
func part_c_story_launch_from_config() -> void:
    print("--- part C: START -> story MatchLaunchConfig -> gameplay ---")
    var host = await story.enter(self)
    var briefing = host.story_briefing()
    briefing.select_fighter("ggb")
    check(host.story_selection_id() == "ggb", "the briefing selection reaches the typed state")
    check(AppStateScript.story_fighter_id == "ggb", "the selection is carried for the route returns")

    var captured: Dictionary = {}
    host.launch_requested.connect(func(config) -> void: captured["config"] = config)
    host.launch_finished.connect(func() -> void: captured["report"] = host.handshake_report())
    host.presentation_ready_received.connect(func() -> void: captured["ready"] = true)

    var arena = await story.start_encounter(self, host)
    check(arena != null, "START ENCOUNTER launches the encounter")
    if arena == null:
        return
    var released: bool = await story.wait_for(self, func() -> bool: return captured.has("report"))
    check(released, "the launch transition released the frontend")

    var config = captured.get("config", null)
    check(config != null and config.is_valid(), "START freezes a VALID MatchLaunchConfig")
    if config != null:
        check(config.has_story(), "the config carries the Story payload")
        check(config.story_encounter_id() == ENCOUNTER, "the payload carries the encounter id")
        check(config.stage_id() == encounter_stage(), "the encounter stage comes from the catalog")
        check(int(config.mode()) == StateScript.Mode.FFA, "the snapshot mode is FFA")
        check(str(config.slot(0).get("fighter_id", "")) == "ggb", "the snapshot carries the selected fighter")
        check(int(config.slot(1).get("kind", -1)) == StateScript.Kind.CPU, "P2 is the CPU opponent slot")
        check(str(config.slot(1).get("fighter_id", "")) == "bobo", "P2 is the encounter enemy")
        check(str(config.story_payload().get("enemy_id", "")) == "bobo",
            "the frozen payload carries the encounter metadata (not a screen reference)")

    var report: Dictionary = captured.get("report", {})
    print("STORY_HANDSHAKE " + JSON.stringify(report))
    check(bool(captured.get("ready", false)) and bool(report.get("presentation_ready_received", false)),
        "gameplay reported presentation_ready during the story handshake")
    check(bool(report.get("constructed_hidden_while_frontend_up", false)),
        "gameplay was prewarmed hidden while the briefing stayed presented (Doc 02 §6)")
    check(not bool(report.get("presentation_timed_out", true)),
        "the story release waited on the destination's own signal, not the deadline")
    check(bool(report.get("frontend_released_after_ready", false)),
        "the frontend was released only after readiness")
    check(bool(report.get("match_started_from_config", false)),
        "the match started from the immutable snapshot")

    await frames(2)
    check(root.get_node_or_null("MatchFlow") == null, "the released host is gone after the launch")
    check(arena.story_state == "playing", "gameplay runs the Story state machine from the payload")
    check(arena.fighters.size() == 2 and get_nodes_in_group("fighters").size() == 2,
        "only two active fighters; no phantom bots")
    check(arena.player_one.character_id == "ggb" and arena.player_one.control_type == "human"
        and arena.player_one.input_device == -1, "P1 is the selected human on keyboard")
    check(arena.player_two.character_id == "bobo" and arena.player_two.control_type == "bot",
        "the opponent is the encounter NPC bot")
    check(not arena.teams_enabled, "the story encounter has no teams")
    check(arena.player_one.stocks == 3 and arena.player_two.stocks == 3, "three-stock encounter")
    check(arena.player_one.spawn_position.x < 0 and arena.player_two.spawn_position.x > 0,
        "the duel starts on opposite arena sides")
    check(arena.active_level == encounter_stage(), "the encounter stage reaches the match")
    check("STORY 01 — %s VS BOBO" % arena.player_one.fighter_name == arena.hud_title.text,
        "the HUD title template comes from the payload")
    var hud = arena.find_child("MatchControls", true, false)
    check(hud != null and "Bobo: 400 HP" in str(hud.text), "the story HUD keeps the encounter vocabulary")
    # WP-0 step 8 (Doc 02 §9): a production arena — the story launch included —
    # constructs NO debug setup screen, so the debug vocabulary can never appear
    # in the story flow.
    check(arena.setup == null, "a story launch constructs no debug setup screen")
    arena.queue_free()
    await story.free_hosts(self)

# ---------------------------------------------------------------------------
# Part D — Back returns to Main and preserves the selection
# ---------------------------------------------------------------------------
func part_d_selection_and_back() -> void:
    print("--- part D: Back -> Main, selection preserved ---")
    var host = await story.enter(self)
    var briefing = host.story_briefing()
    var playable: Array = []
    for id in host.story_playable_ids():
        playable.append(str(id))
    briefing.select_fighter(str(playable[2]))
    check(host.story_selection_id() == playable[2], "the selection reaches the typed state")
    briefing.back_button().pressed.emit()
    await frames(2)
    check(briefing.is_exiting(), "Back runs the briefing exit choreography")
    var home_scene = await story.wait_for_scene(self, "home.tscn")
    check(home_scene != null, "Back returns to the Main route")
    check(AppStateScript.story_fighter_id == playable[2], "the Story selection survives the Main return")
    if home_scene != null:
        home_scene.queue_free()
    # The manually mounted host is not the current scene, so the route's own
    # scene change cannot free it: this test frees it before the re-entry.
    await story.free_hosts(self)
    var reentry = await story.enter(self)
    check(reentry.story_briefing().selected_fighter_id() == playable[2], "re-entry restores the roster choice")
    check(reentry.story_selection_id() == playable[2], "the typed state keeps the roster choice")
    await story.free_hosts(self)

# ---------------------------------------------------------------------------
# Part E — gameplay end -> Story Result in the host, replay/retry, MAIN MENU
# ---------------------------------------------------------------------------
func part_e_story_result_and_replay() -> void:
    print("--- part E: Story Result + replay/retry + MAIN MENU ---")
    var host = await story.enter(self, "turbofit")
    var launch_host_id: int = host.get_instance_id()
    var arena = await story.start_encounter(self, host)
    check(arena != null, "the encounter launches")
    if arena == null:
        return
    story.run_ready(arena)
    for fighter in arena.fighters:
        fighter.set_physics_process(false)
    arena.player_two.receive_hit(1000, Vector3.RIGHT, 100)
    check(arena.story_state == "complete" and arena.match_over, "lethal damage completes the encounter")
    check(not arena.get("winner_label"), "the arena carries no generic freeplay winner text any more")
    var result_host = await story.wait_for_flow(self, launch_host_id)
    check(result_host != null, "the completed arena returns to the MatchFlow host")
    check(not is_instance_valid(arena), "the completed gameplay is torn down before the Story Result")
    if result_host == null:
        return
    var host_id: int = result_host.get_instance_id()
    var result_briefing = result_host.story_briefing()
    check(result_host.entry_mode() == "story" and result_host.active_surface() == "story",
        "the Story Result is the host's Story surface")
    check(str(result_briefing.title_label().text) == "your pretty cool", "the shipped win wording is preserved")
    check(str(result_briefing.action_button().text) == "REPLAY",
        "the win offers REPLAY (not the multiplayer Results screen)")
    check(str(result_briefing.back_button().text) == "MAIN MENU", "the Story Result routes to MAIN MENU")
    check(result_host.story_selection_id() == "turbofit", "the Story Result keeps the played fighter")

    # REPLAY: a fresh encounter from the same selection through the same path.
    var replay_captured: Dictionary = {}
    result_host.launch_requested.connect(func(config) -> void: replay_captured["config"] = config)
    var replay = await story.start_encounter(self, result_host)
    check(replay != null and replay.story_state == "playing", "REPLAY launches a fresh encounter")
    if replay == null:
        return
    story.run_ready(replay)
    var cfg = replay_captured.get("config", null)
    check(cfg != null and cfg.is_valid() and cfg.has_story(), "REPLAY freezes a story launch config again")
    check(str(cfg.slot(0).get("fighter_id", "")) == "turbofit", "REPLAY keeps the played fighter")
    check(replay.player_two.health == 400.0 and replay.player_one.stocks == 3,
        "REPLAY restores the encounter (full HP, three stocks)")
    for fighter in replay.fighters:
        fighter.set_physics_process(false)
    for i in 3:
        replay.player_one._handle_blast_zone()
    check(replay.story_state == "lost", "human stock exhaustion shows the loss state")
    var loss_host = await story.wait_for_flow(self, host_id)
    check(loss_host != null, "the loss returns to the Story Result host")
    if loss_host != null:
        check(str(loss_host.story_briefing().title_label().text) == "TRY AGAIN",
            "the shipped loss wording is preserved")
        check(str(loss_host.story_briefing().title_label().text) != "your pretty cool",
            "the loss never shows the victory line")
        check(str(loss_host.story_briefing().action_button().text) == "RETRY", "the loss offers RETRY")
        loss_host.story_briefing().back_button().pressed.emit()
        var home_scene = await story.wait_for_scene(self, "home.tscn")
        check(home_scene != null, "MAIN MENU returns to the Main route")
        if home_scene != null:
            home_scene.queue_free()
    await story.free_hosts(self)

# ---------------------------------------------------------------------------
# Part F — the superseded in-gameplay story code is gone (Doc 10)
# ---------------------------------------------------------------------------
func part_f_superseded_story_code_removed() -> void:
    print("--- part F: superseded story code removed ---")
    var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
    for removed in ["_build_story_panel", "StoryCharacterSelect", "story_panel", "story_briefing",
            "story_character", "func open_story", "func start_story", "_story_playable_ids"]:
        check(main_source.find(removed) == -1, "gameplay no longer carries the Story panel code: " + removed)
    check(FileAccess.get_file_as_string("res://scripts/match_setup.gd").find("story_requested") == -1,
        "the Debug Setup no longer carries a Story route")
    var direct = load("res://scenes/main.tscn").instantiate()
    root.add_child(direct)
    await frames(5)
    check(direct.find_child("StoryBriefing", true, false) == null, "gameplay mounts no story briefing node")
    check(direct.story_state == "" and direct.get("story_panel") == null,
        "a direct arena load starts with no Story surface and no story panel property")
    check(direct.get("story_briefing") == null, "gameplay exposes no story briefing handle")
    direct.queue_free()
    await frames(3)
