extends SceneTree
# MatchFlow route contract — corrective package Doc 02 §1 (boundary), §5 (router
# verbs), §6 (destination readiness), §7 (screen lifecycle). WP-0 step 3 gate.
#
# Evidence class: PUBLIC_INPUT_ACCEPTANCE for the player route (Main Menu PLAY
# row click, FighterTile focus+confirm, ReadyBand click, StageTile press
# grammar) and ROUTE_CONTRACT for the host's own verbs/lifecycle, which ARE the
# subject under test here (PUSH/POP, prepare_*/play_*, the launch handshake).
#
# Protected contract:
#   * MatchFlow is the frontend host: CSS and SSS are its children, outside
#     gameplay; no arena exists while merely configuring (WP-0 gate);
#   * PUSH/POP update route state AND the origin stack (incl. the RESULTS origin
#     that Results -> Change Stage pushes later);
#   * prepare_return_entry restores the authored root alpha — the alpha-zero CSS
#     return bug (play_exit leaves $ReferenceFrame.modulate.a at 0);
#   * PLAY (home.gd's own handler) reaches MatchFlow;
#   * CSS READY -> SSS -> confirm freezes a MatchLaunchConfig whose fields match
#     the selected state, gameplay accepts it and the match starts;
#   * gameplay end RETURNs the typed end-state payload to the MatchFlow host,
#     whose PostMatch surface presents the immutable MatchResult, and the
#     completed arena is torn down before post-match configuration.

const StateScript = preload("res://scripts/match_flow_state.gd")

var failures := 0

func _initialize(): call_deferred("run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func frames(count: int) -> void:
    for i in count:
        await process_frame

func key_event(code: int) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    return event

func click_at(position: Vector2) -> void:
    # Real mouse activation through the viewport: the button's own _gui_input /
    # pressed path, never a direct helper call. `in_local_coords = true` feeds
    # the event in viewport-local coordinates (design space), which is what the
    # authored Control rects use — the headless window has its own 0.05 screen
    # transform, so screen-space positions would miss every target.
    var down := InputEventMouseButton.new()
    down.button_index = MOUSE_BUTTON_LEFT
    down.pressed = true
    down.position = position
    root.push_input(down, true)
    var up := InputEventMouseButton.new()
    up.button_index = MOUSE_BUTTON_LEFT
    up.pressed = false
    up.position = position
    root.push_input(up, true)

func wait_for(condition: Callable, limit: int) -> bool:
    for i in limit:
        await process_frame
        if bool(condition.call()):
            return true
    return false

func run() -> void:
    await part_a_host_and_router()
    await part_b_production_route()
    if failures > 0:
        print("FAILURES: %d" % failures)
        quit(1)
        return
    print("PASS: MatchFlow route (host ownership, PUSH/POP origins, lifecycle alpha restore, PLAY route, launch config handshake, post-match re-entry)")
    quit(0)

# ---------------------------------------------------------------------------
# Part A — the host owns CSS/SSS as children and implements the router verbs
# ---------------------------------------------------------------------------
func part_a_host_and_router() -> void:
    print("--- part A: MatchFlow host, router verbs, screen lifecycle ---")
    var host = load("res://scenes/match_flow.tscn").instantiate()
    root.add_child(host)
    await frames(20)
    check(host.has_method("push_surface") and host.has_method("pop_surface") and host.has_method("launch_match"),
        "MatchFlow exposes the semantic route verbs")
    check(host.active_surface() == "css", "a fresh flow activates Character Select")
    check(host.route_stack_names() == ["css"], "the route stack starts at the CSS")
    check(host.presented_surfaces() == ["css"], "exactly one surface is presented")
    check(host.input_scope() == "frontend", "the flow claims the frontend input scope while active")
    check(root.get_node_or_null("MainArena") == null and host.gameplay_node() == null,
        "gameplay does not exist while merely configuring (WP-0 gate)")
    var css = host.char_select()
    var sss = host.stage_select()
    check(css != null and css.get_parent() != null and css.get_parent().get_parent() == host,
        "Character Select is a CHILD of the MatchFlow host")
    check(sss != null and sss.get_parent() == css.get_parent(),
        "Stage Select is a child of the same host layer")
    check(not (css is Node3D) and not (sss is Node3D), "both surfaces are frontend Controls, not gameplay")
    check(css.get_tiles().size() == 7, "the hosted CSS carries the roster field")

    # PUSH with the RESULTS origin: the Results -> Change Stage route (§5).
    check(host.push_surface("sss", "results"), "PUSH accepts Stage Select")
    check(host.active_surface() == "sss", "PUSH activates the incoming surface")
    check(host.route_stack_names() == ["css", "sss"], "PUSH keeps the origin surface mounted beneath")
    check(host.route_origin() == "results", "PUSH records the route origin (RESULTS)")
    check(host.origin_stack_names() == ["main", "results"], "the origin stack carries the pushed origin")
    await frames(45)
    check(host.is_surface_presented("sss") and not host.is_surface_presented("css"),
        "the push settles on exactly one presented surface")
    check(host.surface_root_alpha("sss") > 0.0, "the incoming SSS enters visibly")
    check(host.surface_root_alpha("css") <= 0.001,
        "the outgoing CSS exit leaves its frame at alpha 0 (the shipped return bug)")

    # POP back to the CSS: the return entry must restore the authored alpha.
    check(host.pop_surface() == "css", "POP returns to the surface beneath")
    check(host.active_surface() == "css", "POP makes the restored surface active")
    check(host.last_popped_origin() == "results", "POP reports the origin it consumed")
    check(host.route_origin() == "main", "the restored surface's return target is back to Main")
    await frames(45)
    check(host.is_surface_presented("css") and not host.is_surface_presented("sss"),
        "the pop settles back on the CSS")
    check(host.surface_root_alpha("css") > 0.0,
        "prepare_return_entry restored the CSS root alpha (alpha-zero return bug fixed)")
    check(host.surface_root_alpha("css") >= 0.99, "the CSS is restored to its authored baseline alpha")
    host.queue_free()
    await frames(3)

# ---------------------------------------------------------------------------
# Part B — the production route: PLAY -> MatchFlow -> CSS -> SSS -> gameplay
# ---------------------------------------------------------------------------
func part_b_production_route() -> void:
    print("--- part B: production PLAY route, launch config, handshake ---")
    var home = load("res://scenes/home.tscn").instantiate()
    root.add_child(home)
    await frames(45)
    var rows: Array = home.menu_rows()
    check(rows.size() == 4, "the Main Menu still carries its four destinations")
    if rows.size() != 4:
        home.queue_free()
        return
    var play_hit: Button = rows[0].get_node("HitArea")
    click_at(play_hit.get_global_rect().get_center())
    await frames(6)
    check(home.state == "home" and home.selected_index() == 0, "the PLAY row takes the real pointer click")

    var host = null
    var reached := false
    for i in 300:
        await process_frame
        var node := root.get_node_or_null("MatchFlow")
        if node != null and node.has_method("active_surface"):
            host = node
            reached = true
            break
    check(reached, "PLAY reaches the MatchFlow host (the production route switched)")
    if host == null:
        return
    home.queue_free()
    await frames(3)
    check(host.active_surface() == "css", "the production route enters Character Select inside MatchFlow")
    check(root.get_node_or_null("MainArena") == null, "no arena exists while configuring (WP-0 gate)")
    check(host.surface_root_alpha("css") > 0.0, "the CSS is presented visibly on entry")

    var captured: Dictionary = {}
    host.launch_requested.connect(func(config) -> void: captured["config"] = config)
    host.launch_finished.connect(func() -> void: captured["report"] = host.handshake_report())
    host.presentation_ready_received.connect(func() -> void: captured["ready"] = true)

    # --- commit a fighter through the real keyboard path --------------------
    await create_timer(0.5).timeout
    var css = host.char_select()
    var ggb_tile: Control = null
    for tile in css.get_tiles():
        if str(tile.fighter_id) == "ggb":
            ggb_tile = tile
    check(ggb_tile != null, "the ggb tile is in the hosted roster")
    if ggb_tile != null:
        ggb_tile.grab_focus()
        await frames(3)
        root.push_input(key_event(KEY_ENTER))
        await frames(4)
    check(str(host.selection_state.slots[0]["character"]) == "ggb",
        "the committed fighter reaches the selection state")

    # --- the second active fighter ------------------------------------------
    # Locked fresh defaults (Doc 01 §2): P2 is a CPU with NO fighter, and the
    # ONE shipped gate (ledger C-002: each active slot owns a fighter) stays
    # closed until P2 does too. Commit it through the real player path: click
    # P2's bay (the bay takes the click and becomes active), then confirm.
    var opponent_tile: Control = null
    for tile in css.get_tiles():
        if str(tile.fighter_id) == "doge_man":
            opponent_tile = tile
    check(opponent_tile != null, "the doge_man tile is in the hosted roster")
    click_at((css.get_bays()[1] as Control).get_global_rect().get_center())
    await frames(4)
    check(css.get_active() == 1, "clicking P2's bay makes P2 the active player")
    if opponent_tile != null:
        opponent_tile.grab_focus()
        await frames(3)
        root.push_input(key_event(KEY_ENTER))
        await frames(4)
    check(str(host.selection_state.slots[1]["character"]) == "doge_man",
        "the second active slot owns its committed fighter")

    # --- READY through the band's own click path ---------------------------
    var band = css.get_ready_band()
    check(css.ready_allowed(), "the shipped CSS gate allows READY for the configuration")
    check(band.is_shown(), "the ready band is up for a valid configuration")
    click_at(band.get_global_rect().get_center())
    var pushed := await wait_for(func() -> bool:
            return host.active_surface() == "sss" and host.is_surface_presented("sss"), 240)
    check(pushed, "READY pushes Stage Select (CSS -> SSS)")
    check(not host.is_surface_presented("css"), "the CSS is no longer presented after the push")
    check(host.route_stack_names() == ["css", "sss"], "the route stack holds the pushed SSS")

    # --- confirm a stage through the tile press grammar ---------------------
    await create_timer(1.0).timeout
    var sss = host.stage_select()
    var sky_index: int = sss._index_of("sky")
    check(sky_index >= 0, "the sky stage is in the stage field")
    if sky_index >= 0:
        var sky_tile: Button = sss.get_tiles()[sky_index]
        click_at(sky_tile.get_global_rect().get_center())
        await frames(4)
        click_at(sky_tile.get_global_rect().get_center())
        await frames(4)
    check(sss.is_confirming(), "the second press confirms the stage (SSS grammar)")

    # --- the LAUNCH handshake ---------------------------------------------
    var launched := await wait_for(func() -> bool: return host.launch_state() == "launched", 300)
    check(launched, "the stage confirm launches through the router")
    var arena = host.gameplay_node()
    check(arena != null and is_instance_valid(arena), "the router constructed the gameplay destination")
    # The authored LAUNCH transition releases the flow after the destination is
    # revealed; launch_finished is the release point.
    var released := await wait_for(func() -> bool: return captured.has("report"), 90)
    check(released, "the launch transition released the frontend")
    var prior_id: int = host.get_instance_id()

    var report: Dictionary = captured.get("report", {})
    print("HANDSHAKE " + JSON.stringify(report))
    check(bool(captured.get("ready", false)) and bool(report.get("presentation_ready_received", false)),
        "gameplay reported presentation_ready during the handshake")
    check(bool(report.get("constructed_hidden_while_frontend_up", false)),
        "gameplay was prewarmed hidden while the frontend stayed presented (Doc 02 §6)")
    check(not bool(report.get("presentation_timed_out", true)),
        "the release waited on the destination's own signal, not the deadline")
    check(bool(report.get("frontend_released_after_ready", false)),
        "the frontend was released only after readiness")
    print("HANDSHAKE %s" % JSON.stringify(report))

    var config = captured.get("config", null)
    check(config != null and config.is_valid(), "CSS -> SSS -> confirm freezes a VALID MatchLaunchConfig")
    if config != null:
        check(config.stage_id() == "sky", "the config carries the confirmed stage")
        check(config.slot_count() == 4, "the config carries the four resolved slots")
        check(str(config.slot(0).get("fighter_id", "")) == "ggb", "the config carries the committed fighter")
        check(int(config.slot(1).get("kind", -1)) == StateScript.Kind.CPU, "P2 is a CPU slot in the snapshot")
        check(config.mode() == StateScript.Mode.FFA, "the snapshot mode is FFA")
        check(int(config.slot(0).get("palette_index", -1)) == 0, "the snapshot carries the resolved palette variant")

    # --- gameplay accepts the snapshot and the match starts ----------------
    await frames(20)
    if arena != null and is_instance_valid(arena):
        # Locked fresh defaults: P3/P4 are EMPTY, so exactly two fighters spawn.
        check(arena.fighters.size() == 2, "the match starts from the config (the two active fighters appear)")
        check(str(arena.fighters[0].character_id) == "ggb", "the selected fighter reaches the match")
        check(str(arena.fighters[1].character_id) == "doge_man", "the second committed fighter reaches the match")
        check(arena.active_level == "sky", "the confirmed stage reaches the match")
        check(bool(arena._launched_from_flow), "gameplay knows it was launched from the flow")

    # --- gameplay end -> PostMatch in the flow (WP-0 step 5) ---------------
    if arena != null and is_instance_valid(arena):
        for fighter in arena.fighters:
            fighter.set_physics_process(false)
        arena.fighters[1].stocks = 0
        arena._on_fighter_eliminated(arena.fighters[1])
        check(arena.match_over, "the match resolves")

    var reentry = null
    for i in 300:
        await process_frame
        var node := root.get_node_or_null("MatchFlow")
        if node != null and node.get_instance_id() != prior_id:
            reentry = node
            break
    check(reentry != null, "the completed match RETURNs to the MatchFlow host")
    check(not is_instance_valid(arena), "the completed gameplay is torn down before the PostMatch surface is up")
    if reentry != null:
        check(reentry.active_surface() == "postmatch", "the RETURN presents the PostMatch surface")
        check(reentry.post_match() != null and reentry.post_match_result() != null,
            "the host presents the immutable MatchResult gameplay handed over")
        check(reentry.route_origin() == "results", "the re-entry records the RESULTS origin")
        var winner = reentry.post_match_result().winner_entry()
        # The survivor is P1 (the committed ggb fighter): fighters[1] (P2) was
        # eliminated above, and player_index is slot index + 1.
        check(int(winner.get("player_index", 0)) == 1, "the payload declares the last survivor (P1) the winner")
        check(str(winner.get("fighter_id", "")) == "ggb", "the winning entry is the committed fighter")
        var change = reentry.post_match().result_screen.find_child("ChangeFighters", true, false)
        check(change != null and change.visible, "Results offers Change Fighters")
        if change != null:
            change.pressed.emit()
        var pushed_css: bool = await wait_for(func() -> bool: return reentry.active_surface() == "css", 180)
        check(pushed_css, "Change Fighters PUSHes the CSS with origin RESULTS")
        check(reentry.route_origin() == "results", "the CSS route records the RESULTS origin")
        check(reentry.surface_root_alpha("css") > 0.0, "the re-entered CSS is presented visibly")
        check(reentry.presented_surfaces() == ["css"], "exactly one surface is presented after the push")
        check(root.get_node_or_null("MainArena") == null, "no arena exists during post-match configuration")
        reentry.queue_free()
        await frames(3)
