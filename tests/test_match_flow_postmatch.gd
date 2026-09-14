extends SceneTree
# MatchFlow PostMatch contract — WP-0 step 5 (Doc 02 §1 POST-MATCH, §4 immutable
# end-state data, §5 router verbs/RETURN, §10.6; Doc 01 §14 Results cancel;
# Doc 06 §5 PostMatch ownership, §8 action routes, §9 no hidden shortcut;
# Doc 03 §11 back/cancel matrix).
#
# Protected contract:
#   * gameplay owns NO Results screen: at resolution it builds the immutable
#     MatchResult and hands it to the router (RETURN), and the completed arena is
#     torn down before the PostMatch surface becomes interactive;
#   * MatchFlow hosts PostMatch, which presents the SHIPPED result_screen over
#     the typed payload (no live fighter is read);
#   * REMATCH LAUNCHes from the PRESERVED MatchLaunchConfig (never re-seeded
#     defaults), CHANGE FIGHTERS PUSHes the CSS with origin RESULTS, CHANGE STAGE
#     PUSHes the SSS with origin RESULTS and its Back POPs back to Results,
#     MAIN MENU clears the stack to Main;
#   * the SSS from the normal flow still Backs to the CSS;
#   * Results cancel (Doc 01 §14): the first input that merely completes/skips
#     the reveal never also leaves the screen; after reveal safety ui_cancel
#     takes the same route as the visible MAIN MENU action.
#
# Evidence class: PUBLIC_INPUT_ACCEPTANCE for the route actions (the shipped
# action buttons / real Esc events) and ROUTE_CONTRACT for the typed payload
# hand-off, which IS the subject under test here.
#
# The route fixture and result_screen.gd are loaded inside run(): a top-level
# preload of a script that reads an autoload compiles before the autoloads are
# registered.

const AppStateScript = preload("res://scripts/app_state.gd")
const StateScript = preload("res://scripts/match_flow_state.gd")

var failures := 0
var vs                        # tests/fixtures/vs_route.gd helper
var result_screen_script = null

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func frames(count: int) -> void:
    for i in count:
        await process_frame

func escape() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.pressed = true
    return event

func run() -> void:
    root.size = Vector2i(1280, 720)
    result_screen_script = load("res://scripts/result_screen.gd")
    vs = load("res://tests/fixtures/vs_route.gd").new()
    await part_a_payload_ownership()
    await part_b_route_actions()
    await part_c_sss_from_results()
    await part_d_cancel_semantics()
    await part_e_rematch_preserved_config()
    if failures > 0:
        print("FAILURES: %d" % failures)
        quit(1)
        return
    print("PASS: MatchFlow PostMatch (typed RETURN hand-off, ownership/teardown, route actions + origins, SSS-from-Results, cancel safety, preserved-config rematch)")
    quit(0)

# --- helpers ----------------------------------------------------------------

func post_match_flow(host_id: int, arena: Node) -> Node:
    # Resolves the launched match and waits for the re-entered PostMatch host.
    # The launched host frees itself when it releases gameplay, so its instance
    # id — not the node — is what identifies it here.
    await vs.resolve(self, arena, [1])
    return await vs.wait_for_flow(self, host_id)

# ---------------------------------------------------------------------------
# Part A — gameplay hands the immutable payload over and is gone before the
# PostMatch surface is interactive
# ---------------------------------------------------------------------------
func part_a_payload_ownership() -> void:
    print("--- part A: RETURN payload ownership ---")
    var host = await vs.enter(self)
    var host_id: int = host.get_instance_id()
    var captured: Dictionary = {}
    host.launch_requested.connect(func(config) -> void: captured["config"] = config)
    var arena = await vs.launch(self, host, ["ggb", "ggb", "", ""], "sky")
    check(arena != null, "the VS route launches gameplay from the flow")
    if arena == null:
        await vs.free_hosts(self)
        return
    var config = captured.get("config", null)
    check(config != null and config.is_valid(), "the launch froze a valid MatchLaunchConfig")
    var post = await post_match_flow(host_id, arena)
    check(post != null, "the completed match RETURNs to the MatchFlow host")
    if post == null:
        return
    check(not is_instance_valid(arena), "gameplay is torn down before the PostMatch surface becomes interactive")
    check(post.active_surface() == "postmatch", "PostMatch is the active surface after the RETURN")
    check(post.route_stack_names() == ["postmatch"], "the route stack is the returned PostMatch region")
    check(post.presented_surfaces() == ["postmatch"], "exactly one surface is presented")
    check(post.input_scope() == "frontend", "PostMatch claims the frontend input scope")
    check(root.get_node_or_null("MainArena") == null, "no arena survives behind PostMatch")
    check(post.post_match() != null and post.post_match().visible, "the PostMatch surface is hosted and presented")

    var payload: Dictionary = post.post_match_payload()
    check(str(payload.get("kind", "")) == "vs", "the hand-off carries the typed VS payload")
    check(payload.get("result", null) != null, "the payload carries the immutable MatchResult")
    check(payload.get("config", null) == config, "the payload preserves the EXACT launch config instance")
    check(str(payload.get("stage", "")) == "sky", "the payload records the played stage")
    var result = post.post_match_result()
    check(str(result.outcome) == "WIN", "the presented result is a WIN")
    var winner: Dictionary = result.winner_entry()
    check(int(winner.get("player_index", 0)) == 1, "P1 is the declared winner (from the payload, not a live fighter)")
    check(str(result.entry_for_player(2)["fighter_id"]) == "ggb", "eliminated entries carry stable fighter ids")
    check(post.post_match().outcome_label.text == "P1 GGB", "the shipped outcome header names the payload winner")
    check(post.post_match().is_revealing(), "the shipped reveal runs on the PostMatch surface")
    # The surface becomes interactive on its own timeline; nothing about the
    # torn-down arena is needed for that.
    var interactive: bool = await vs.wait_for(self, func() -> bool: return post.post_match().is_interactive(), 180)
    check(interactive, "the reveal completes into an interactive surface")
    check(not is_instance_valid(arena), "gameplay stays torn down while Results is interactive")
    await vs.free_hosts(self)
    await vs.free_arenas(self)
    await frames(3)

# ---------------------------------------------------------------------------
# Part B — each action routes to the right destination with the right origin
# ---------------------------------------------------------------------------
func part_b_route_actions() -> void:
    print("--- part B: action routes ---")
    # CHANGE FIGHTERS -> PUSH the CSS with origin RESULTS.
    var host = await vs.enter(self)
    var host_id: int = host.get_instance_id()
    var arena = await vs.launch(self, host, ["ggb", "ggb", "", ""], "sky")
    var post = await post_match_flow(host_id, arena)
    check(post != null, "the post-match flow is reachable for the action routes")
    if post == null:
        return
    var change_fighters: Button = post.post_match().result_screen.find_child("ChangeFighters", true, false)
    check(change_fighters != null and change_fighters.visible, "Results offers the visible CHANGE FIGHTERS action")
    change_fighters.pressed.emit()
    var pushed: bool = await vs.wait_for(self, func() -> bool: return post.active_surface() == "css", 120)
    check(pushed, "CHANGE FIGHTERS PUSHes Character Select")
    check(post.is_surface_presented("css") and not post.is_surface_presented("postmatch"),
        "the PUSH settles on exactly one presented surface")
    check(post.route_origin() == "results", "the CSS route records the RESULTS origin")
    check(post.origin_stack_names().has("results"), "the typed origin stack carries RESULTS")
    check(str(post.selection_state.slots[0]["character"]) == "ggb", "the CSS re-opens on the played fighters (MatchFlowState preserved, not defaults)")
    check(str(post.selection_state.slots[2]["kind"]) == "empty", "the preserved state keeps the EMPTY stations empty")
    # The normal flow is unaffected: CSS READY -> SSS, SSS Back -> CSS (POP).
    var ready: bool = await vs.ready(post, self)
    check(ready, "the restored CSS still readies into Stage Select")
    var sss = post.stage_select()
    sss.request_back()
    var back: bool = await vs.wait_for(self, func() -> bool: return post.active_surface() == "css", 180)
    check(back, "SSS from the normal flow still Backs to the CSS (POP)")
    await vs.free_hosts(self)
    await frames(3)

    # MAIN MENU -> clear the stack to Main.
    host = await vs.enter(self)
    host_id = host.get_instance_id()
    arena = await vs.launch(self, host, ["ggb", "ggb", "", ""], "toy_room")
    post = await post_match_flow(host_id, arena)
    if post == null:
        return
    var menu_action: Button = post.post_match().result_screen.find_child("MainMenu", true, false)
    check(menu_action != null and menu_action.visible, "Results offers the visible MAIN MENU action")
    menu_action.pressed.emit()
    var home = await vs.wait_for_scene(self, "home.tscn")
    check(home != null, "MAIN MENU clears the route to Main")
    if home != null:
        home.queue_free()
    await vs.free_hosts(self)
    await frames(3)

# ---------------------------------------------------------------------------
# Part C — CHANGE STAGE PUSHes the SSS with origin RESULTS, and its Back POPs
# back to Results (Doc 03 §11 "SSS from Results -> Results")
# ---------------------------------------------------------------------------
func part_c_sss_from_results() -> void:
    print("--- part C: SSS from Results ---")
    var host = await vs.enter(self)
    var host_id: int = host.get_instance_id()
    var arena = await vs.launch(self, host, ["ggb", "doge_man", "", ""], "sky")
    var post = await post_match_flow(host_id, arena)
    check(post != null, "the post-match flow is reachable for Change Stage")
    if post == null:
        return
    check(post.post_match().result_screen.find_child("ChangeStage", true, false).visible,
        "Results offers the visible CHANGE STAGE action")
    post.post_match().result_screen.finish_reveal()
    check(post.post_match().is_interactive(), "the Results surface is interactive before the route")
    post.post_match().result_screen.find_child("ChangeStage", true, false).pressed.emit()
    var pushed: bool = await vs.wait_for(self, func() -> bool: return post.active_surface() == "sss", 120)
    check(pushed, "CHANGE STAGE PUSHes Stage Select")
    check(post.route_origin() == "results", "the SSS route records the RESULTS origin")
    check(post.origin_stack_names().has("results"), "the origin stack carries RESULTS")
    check(post.is_surface_presented("sss") and not post.is_surface_presented("postmatch"),
        "the SSS PUSH settles on exactly one presented surface")

    # Back: POP back to Results — the SAME MatchResult screen, not re-revealed.
    post.stage_select().request_back()
    var restored: bool = await vs.wait_for(self, func() -> bool:
            return post.active_surface() == "postmatch" and post.is_surface_presented("postmatch"), 180)
    check(restored, "the SSS Back POPs back to Results")
    check(post.last_popped_origin() == "results", "the POP consumed the RESULTS origin")
    check(post.route_stack_names() == ["postmatch"], "the route stack is back at PostMatch")
    check(post.presented_surfaces() == ["postmatch"], "exactly one surface is presented again")
    check(post.post_match().is_interactive() and not post.post_match().is_revealing(),
        "the restored Results keeps its revealed state (the reveal is never replayed)")
    check(post.post_match().outcome_label.text == "P1 GGB", "the restored Results still shows the same payload")

    # Change Stage again: confirm LAUNCHes the same roster on the new stage
    # (Doc 06 §8).
    var second: Dictionary = {}
    post.launch_requested.connect(func(config) -> void: second["config"] = config)
    post.post_match().result_screen.find_child("ChangeStage", true, false).pressed.emit()
    await vs.wait_for(self, func() -> bool: return post.active_surface() == "sss", 120)
    var arena2 = await vs.confirm_stage(post, "toy_room", self)
    check(arena2 != null, "the SSS confirm launches gameplay again")
    var config2 = second.get("config", null)
    check(config2 != null and config2.is_valid(), "the re-launch freezes a valid config")
    if config2 != null:
        check(config2.stage_id() == "toy_room", "the new stage reaches the new match")
        check(str(config2.slot(0).get("fighter_id", "")) == "ggb", "the roster is preserved across Change Stage")
        check(str(config2.slot(1).get("fighter_id", "")) == "doge_man", "the second fighter is preserved too")
    if arena2 != null and is_instance_valid(arena2):
        check(arena2.active_level == "toy_room" and arena2.fighters.size() == 2, "the confirmed stage and roster reach gameplay")
    await vs.free_hosts(self)
    await vs.free_arenas(self)
    await frames(3)

# ---------------------------------------------------------------------------
# Part D — Results cancel semantics (Doc 01 §14)
# ---------------------------------------------------------------------------
func part_d_cancel_semantics() -> void:
    print("--- part D: cancel semantics ---")
    var host = await vs.enter(self)
    var host_id: int = host.get_instance_id()
    var arena = await vs.launch(self, host, ["ggb", "ggb", "", ""], "sky")
    var post = await post_match_flow(host_id, arena)
    check(post != null, "the post-match flow is reachable for the cancel contract")
    if post == null:
        return
    var surface = post.post_match()
    # (a) carry-over window: the very first ui_cancel is ignored entirely, like
    # the reveal-skip path.
    if surface.result_screen.reveal_tick() < result_screen_script.SAFETY_TICKS:
        root.push_input(escape())
        await frames(1)
        check(surface.is_revealing(), "ui_cancel inside the carry-over window is ignored")
        check(post.active_surface() == "postmatch", "the ignored cancel never leaves the screen")
    # (b) after the safety window the ui_cancel only completes the reveal: one
    # input cannot both skip the reveal and activate an action.
    var in_reveal := false
    for i in 60:
        await process_frame
        if surface.is_revealing() and surface.result_screen.reveal_tick() >= result_screen_script.SAFETY_TICKS:
            in_reveal = true
            break
    check(in_reveal, "the reveal is past its safety window and still running")
    root.push_input(escape())
    await frames(2)
    check(surface.is_interactive(), "the ui_cancel finishes/skips the reveal")
    check(not surface.is_revealing(), "the reveal is complete")
    check(post.active_surface() == "postmatch" and is_instance_valid(post),
        "the reveal-completing input does NOT also leave the screen")
    check(root.get_node_or_null("MainArena") == null and current_scene != null
        and is_instance_valid(current_scene)
        and str(current_scene.scene_file_path).find("match_flow") != -1,
        "no route happened: the flow is still the live scene")
    # (c) after reveal safety, ui_cancel takes the same semantic route as the
    # visible MAIN MENU action.
    var menu_action: Button = surface.result_screen.find_child("MainMenu", true, false)
    check(menu_action != null and menu_action.visible, "the visible MAIN MENU action is up")
    root.push_input(escape())
    var home = await vs.wait_for_scene(self, "home.tscn")
    check(home != null, "ui_cancel after reveal safety routes to Main")
    check(AppStateScript.post_match.is_empty(), "the RETURN payload is consumed on entry (no stale Results)")
    check(AppStateScript.enter_mode == "debug", "the entry flag is left in its consumed state (no origin strings)")
    if home != null:
        home.queue_free()
    await vs.free_hosts(self)
    await frames(3)

# ---------------------------------------------------------------------------
# Part E — REMATCH LAUNCHes from the PRESERVED config
# ---------------------------------------------------------------------------
func part_e_rematch_preserved_config() -> void:
    print("--- part E: rematch from the preserved config ---")
    var host = await vs.enter(self)
    var host_id: int = host.get_instance_id()
    var first: Dictionary = {}
    host.launch_requested.connect(func(config) -> void: first["config"] = config)
    # Deliberately NOT the fresh-VS shape: two active fighters, P3/P4 EMPTY.
    var arena = await vs.launch(self, host, ["mephisto", "teknium", "", ""], "toy_room")
    var post = await post_match_flow(host_id, arena)
    check(post != null, "the post-match flow is reachable for REMATCH")
    if post == null:
        return
    var config1 = first.get("config", null)
    check(config1 != null and config1.is_valid(), "the first launch froze a config")
    check(config1 != null and config1.slot_count() == 4
        and int(config1.slot(2).get("kind", -1)) == StateScript.Kind.EMPTY
        and int(config1.slot(3).get("kind", -1)) == StateScript.Kind.EMPTY,
        "the frozen snapshot keeps the two EMPTY stations")
    var second: Dictionary = {}
    post.launch_requested.connect(func(config) -> void: second["config"] = config)
    var rematch_action: Button = post.post_match().result_screen.find_child("Rematch", true, false)
    check(rematch_action != null and rematch_action.visible, "Results offers the visible REMATCH action")
    post.post_match().result_screen.finish_reveal()
    rematch_action.pressed.emit()
    var relaunched := false
    for i in 240:
        await process_frame
        if second.has("config") and post.pending_launch_config() != null:
            relaunched = true
            break
    check(relaunched, "REMATCH LAUNCHes again through the router")
    var config2 = second.get("config", null)
    check(config2 == config1, "REMATCH re-launches with the PRESERVED config instance")
    if config2 != null:
        check(config2.stage_id() == "toy_room", "the preserved stage reaches the re-launch")
        check(str(config2.slot(0).get("fighter_id", "")) == "mephisto"
            and str(config2.slot(1).get("fighter_id", "")) == "teknium",
            "the preserved fighters reach the re-launch")
    var arena2: Node = post.gameplay_node()
    var live := false
    for i in 240:
        await process_frame
        if arena2 != null and is_instance_valid(arena2) and arena2.fighters.size() == 2 and not is_instance_valid(post):
            live = true
            break
    check(live, "the re-launched gameplay is released to the player")
    if live:
        check(arena2.fighters.size() == 2, "REMATCH does NOT re-seed fresh VS defaults (four default stations)")
        check(bool(arena2._launched_from_flow), "the re-launch went through the flow handshake")
        check(str(arena2.fighters[0].character_id) == "mephisto", "the rematched match starts the preserved P1")
        check(arena2.active_level == "toy_room", "the rematched match runs the preserved stage")
        check(arena2.ready_remaining > 0 and not arena2.match_over, "the rematch runs the shipped READY gate")
    await vs.free_arenas(self)
    if is_instance_valid(post):
        post.queue_free()
    await frames(3)



