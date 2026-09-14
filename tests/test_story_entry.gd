extends SceneTree
# Story entry contract — MIGRATED for WP-0 step 4: the Story route is
# frontend-owned. Main Menu STORY MODE enters the MatchFlow host in story mode,
# the host presents the Encounter Briefing, START ENCOUNTER freezes a story
# MatchLaunchConfig and the encounter runs in the arena (Bobo NPC, three stocks,
# opposite spawn sides, player-facing HUD). The debug setup stays gameplay-side
# and freeplay keeps its own defaults.
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
    # --- Main Menu: the STORY MODE row is the entry ---
    var home = load("res://scenes/home.tscn").instantiate()
    root.add_child(home)
    for i in 40: await process_frame
    var rows: Array = home.menu_rows()
    check(rows.size() == 4, "Main keeps its four destinations")
    if rows.size() != 4:
        home.queue_free()
        quit(1)
        return
    check(str(rows[1].get_node("Label").text) == "STORY MODE", "Story entry uses the mode name without encounter details")
    rows[1].get_node("HitArea").pressed.emit()
    var host = await story.wait_for_flow(self)
    check(host != null, "STORY MODE enters the MatchFlow host")
    if host == null:
        quit(1)
        return
    check(host.entry_mode() == "story" and host.active_surface() == "story_select",
        "the host opens the story route on the Story Fighter Select")
    check(root.get_node_or_null("MainArena") == null, "no unattended fight exists while selecting")
    check(host.gameplay_node() == null, "no arena exists while selecting")
    # --- step 1: the Story Fighter Select is the entry surface ---
    var select = host.story_select()
    check(select != null and select.visible, "the host presents the Story Fighter Select")
    check(not host.story_briefing().visible, "the Encounter Briefing is not skipped on entry")
    if home.is_inside_tree():
        home.queue_free()
    await process_frame
    # --- step 2: Continue reaches the hosted briefing ---
    var reached: bool = await story.open_briefing(self, host)
    check(reached and host.story_briefing().visible, "Continue reaches the Encounter Briefing")
    var briefing = host.story_briefing()
    check(briefing != null and briefing.visible, "the host presents the Encounter Briefing")
    check(briefing.selected_fighter_id() == "turbofit", "ready screen identifies the default fighter")
    check(str(briefing.objective_label().text).find("Bobo") != -1, "the briefing identifies the encounter")
    check(str(briefing.action_button().text) == "START ENCOUNTER", "the briefing offers the START ENCOUNTER action")
    # --- START: the encounter launches from the frozen config ---
    var arena = await story.start_encounter(self, host)
    check(arena != null, "the actual START ENCOUNTER action launches the encounter")
    if arena == null:
        quit(1)
        return
    check(arena.story_state == "playing" and arena.fighters.size() == 2 and get_nodes_in_group("fighters").size() == 2,
        "only two active fighters; no phantom bots")
    check(not arena.teams_enabled, "story has no teams")
    var hud_controls = arena.find_child("MatchControls", true, false)
    check(hud_controls != null and "Bobo: 400 HP" in hud_controls.text,
        "story HUD teaches human controls and identifies the NPC, not a second keyboard player")
    check(arena.setup == null, "no debug setup screen is constructed for a story launch (Doc 02 §9)")
    var hero = arena.fighters[0]
    var mage = arena.fighters[1]
    check(hero.character_id == "turbofit" and hero.control_type == "human" and hero.player_index == 1 and hero.input_device == -1,
        "TurboFit uses human P1 keyboard")
    check(mage.character_id == "bobo" and mage.control_type == "bot" and mage.player_index == 2, "Bobo is a distinct NPC bot")
    check(hero.team_id == -1 and mage.team_id == -1 and hero.stocks == 3 and mage.stocks == 3,
        "three-stock duel with opposing targets")
    check(hero.spawn_position.x < 0 and mage.spawn_position.x > 0, "duel starts on opposite arena sides")
    check(load("res://scripts/roster.gd").ids().has("ice_mage"), "Ice Mage stays in the freeplay roster")
    # --- freeplay separation (the debug launcher stays gameplay-side) ---
    var direct = load("res://scenes/main.tscn").instantiate()
    root.add_child(direct)
    for i in 5: await process_frame
    direct.setup._start()
    check(direct.story_state == "" and direct.fighters.size() == 4, "existing freeplay Start retains all four defaults")
    check(direct.find_child("StoryBriefing", true, false) == null, "no story UI over freeplay")
    check(direct.find_child("StoryCharacterSelect", true, false) == null, "no hidden story selection model inside gameplay")
    direct.queue_free()
    arena.queue_free()
    await story.free_hosts(self)
    if failures == 0: print("PASS: story entry through MatchFlow (Main row, hosted briefing, launch config, two distinct fighters, freeplay separation)")
    quit(1 if failures else 0)
