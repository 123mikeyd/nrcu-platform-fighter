extends SceneTree
# WP-5 RESULTS-UI LANE — presentation, binding, hero rendering and route edges.
#
# Authority: corrective Doc 06 (Results composition, team semantics, the
# MatchResult snapshot, hero framing, actions/reveal safety), Doc 01 §12/§14
# (winner-first team layout with shared team ranks, Results cancel), the
# canonical Results doc §9/§10/§16 (hero through FighterRenderView, no repeated
# sine, reveal under a second), Doc 08 §2 (public-input acceptance) and §3 (the
# route matrix's Results edges).
#
# The data contract is WP-5 lane B's (tests/test_match_resolution_data.gd);
# this suite proves the SCREEN binds to it:
#   * every case is driven through the PRODUCTION route (MatchFlow -> CSS ->
#     SSS -> gameplay -> the arena's elimination signal -> PostMatch), never by
#     injecting a payload with semantics production does not produce;
#   * the winner group renders through the WP-3 presentation factory
#     (FighterRenderView + RESULTS_HERO/RESULTS_TEAM), each subject with its own
#     resolved palette variant, LIVE_IDLE while visible, ONE viewport;
#   * the team hero field's aspect IS the measured wide group field (Doc 06 §7
#     "do not render 2:1 and crop into 1.1:1");
#   * the standings show the shared team rank as a group header ("1ST · TEAM A",
#     Doc 01 §12) with member rows that carry no rank of their own;
#   * an eliminated member of the WINNING team is still displayed as a winner
#     (OUT, no damage) and is still part of the hero group;
#   * simultaneous eliminations display the SHARED rank (never an invented
#     4TH/3RD split), and the final-batch DRAW shows DRAW with no hero;
#   * the route matrix's Results edges + the cancel safety hold with real input.

const Tokens = preload("res://scripts/ui_tokens.gd")

var failures := 0
var vs = null

func _initialize(): call_deferred("run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func frames(count: int):
    for i in count:
        await process_frame

func escape() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.pressed = true
    return event

func click_at(position: Vector2) -> void:
    # Real pointer activation through the viewport (Doc 08 §2), local coords.
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

func eliminations(arena: Node, order: Array) -> void:
    # The production elimination signal, one TICK per element: separate entries
    # are separate batches (Doc 06 §2). Physics is stopped first so the arena
    # cannot resolve anything on its own between the signals.
    for fighter in arena.fighters:
        fighter.set_physics_process(false)
    for i in order.size():
        var target: Node = null
        for fighter in arena.fighters:
            if int(fighter.player_index) == int(order[i]):
                target = fighter
        if target == null:
            check(false, "no fighter for player_index %d" % int(order[i]))
            return
        target.stocks = 0
        arena._on_fighter_eliminated(target)
        if i + 1 < order.size():
            await frames(2)

func run():
    root.size = Vector2i(1280, 720)
    vs = load("res://tests/fixtures/vs_route.gd").new()
    await part_a_team_win_with_out_member()
    await part_a2_independent_palettes()
    await part_b_ffa_simultaneous_tie()
    await part_c_draw()
    await part_d_route_and_cancel_edges()
    await vs.free_hosts(self)
    await vs.free_arenas(self)
    if failures > 0:
        print("FAILURES: %d" % failures)
        quit(1)
        return
    print("PASS: WP-5 Results UI (winner-first header, team group standings with shared ranks, OUT-member hero via the WP-3 factory, simultaneous ties, DRAW, route + cancel edges)")
    quit(0)

# ---------------------------------------------------------------------------
# Part A — the REAL route to a team win whose winning team has an OUT member
# ---------------------------------------------------------------------------
func part_a_team_win_with_out_member() -> void:
    print("--- part A: team win incl. an OUT member, through the production route ---")
    var host = await vs.enter(self)
    var host_ids: Array = vs.host_ids(self)
    check(vs.set_mode(host, 1), "the flow state switches to teams")
    var arena = await vs.launch(self, host, ["teknium", "doge_man", "ggb", "turbofit"], "debug")
    check(arena != null, "the 2v2 match launches from the flow")
    if arena == null:
        return
    # TEAM A = P1/P3, TEAM B = P2/P4. P4 (a future winner) falls out FIRST, then
    # TEAM A is wiped: TEAM B wins with an eliminated member on its roster.
    await eliminations(arena, [4, 3, 1])
    check(arena.match_over, "the match resolves when only TEAM B remains")
    host = await vs.wait_for_new_host(self, host_ids)
    check(host != null, "the resolved team match RETURNs to the PostMatch surface")
    if host == null:
        return
    var post = host.post_match()
    var rs = post.result_screen
    var result = rs.get_result()
    check(result != null and bool(result.team_mode), "the presented payload is a team result")
    check(int(result.winning_team) == 1, "TEAM B is the declared winner")
    var out_member: Dictionary = result.entry_for_player(4)
    check(bool(out_member["eliminated"]), "P4 (TEAM B) was eliminated before match end")
    check(bool(out_member["is_winner"]), "the eliminated teammate is still a WINNER (Doc 06 §3)")
    check(int(out_member["team_placement"]) == 1 and int(result.entry_for_player(2)["team_placement"]) == 1,
        "both TEAM B members share the team rank")
    check(int(out_member["elimination_batch"]) == 0 and int(result.entry_for_player(3)["elimination_batch"]) == 1
        and int(result.entry_for_player(1)["elimination_batch"]) == 2,
        "the three eliminations are three distinct batches")
    check(result.winning_entries().size() == 2, "the hero group carries the whole winning team")

    # Winner-first header (Doc 01 §12, corrective schematic): WINNER / TEAM B.
    check(post.outcome_label.visible and post.outcome_label.text == "TEAM B", "the outcome header names the winning team")
    var eyebrow = rs.find_child("OutcomeEyebrow", true, false)
    check(eyebrow.visible and eyebrow.text == "WINNER", "the WINNER eyebrow sits above the team identity")
    check(rs.get_accent_color() == Tokens.TEAM_B, "the team accent is the team color, not a player color")

    # --- the hero: every winning teammate, including the OUT one ---
    check(rs.get_hero_ids() == ["doge_man", "turbofit"], "the hero group is the winning team in standings order")
    var view = rs.hero_view()
    check(view != null, "the hero renders through the shared FighterRenderView")
    if view != null:
        check(view.profile_name() == "RESULTS_TEAM", "the team hero uses the WP-3 RESULTS_TEAM profile")
        check(view.get_subject_count() == 2, "both winning teammates are rendered")
        check(view.subjects() == ["doge_man", "turbofit"],
            "the hero includes the teammate eliminated before match end (Doc 06 §3/§7)")
        check(view.presentation_mode_name() == "LIVE_IDLE", "the visible hero runs the deliberate LIVE_IDLE presentation")
        # Per-subject palette identity is bound from the snapshot (Doc 06 §10).
        var nodes: Array = view.subject_nodes()
        var palettes_ok := true
        for i in nodes.size():
            var id := str(view.subjects()[i])
            var entry: Dictionary = result.entry_for_player(2 if id == "doge_man" else 4)
            if nodes[i].body_color != load("res://scripts/roster.gd").palette(id, int(entry["palette_index"])):
                palettes_ok = false
        check(palettes_ok, "each hero subject carries its own resolved palette variant")
        # One viewport (the live-view budget): the group is ONE render view.
        check(post.find_children("*", "SubViewport", true, false).size() == 1, "the team hero is exactly one render viewport")
        # Doc 06 §7: the aspect IS the wide group field, and nothing is cropped.
        var ctrl_aspect: float = view.size.x / view.size.y
        var render_aspect: float = float(view.render_size().x) / float(maxi(view.render_size().y, 1))
        var box_aspect: float = rs.hero_rect().size.x / rs.hero_rect().size.y
        check(absf(ctrl_aspect - render_aspect) <= 0.06,
            "the render target aspect is the destination aspect (%.3f vs %.3f)" % [ctrl_aspect, render_aspect])
        check(absf(ctrl_aspect - box_aspect) <= 0.06,
            "the hero field aspect is the measured group field, not the FFA frame (%.3f vs %.3f)" % [ctrl_aspect, box_aspect])
        check(view.texture_fit_mode() == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
            "the group render is contained, never cover-cropped")
        check(rs.hero_rect().size.x > 436.0, "the team field is wider than the FFA hero frame")

    # --- team standings: shared-rank group headers + member rows ---
    check(rs.row_count() == 6, "the team standings plan two group headers and four member rows")
    check(rs.row_text(0) == "1ST · TEAM B", "the winning team leads under its shared-rank header")
    check(rs.row_text(1) == "P2  DOGE MAN" and rs.row_text(2) == "P4  TURBOFIT",
        "the winning team's members follow their header")
    check(rs.row_text(3) == "2ND · TEAM A", "the losing team's header carries its own shared rank")
    check(rs.row_text(4) == "P1  TEKNIUM" and rs.row_text(5) == "P3  GGB", "every losing member stays listed")
    check(int(result.entry_for_player(4)["placement"]) == 1,
        "the OUT winner is never re-ranked below a teammate by the screen")
    # The OUT member of the WINNING team reads OUT with no damage field.
    var list = rs.find_child("StandingsList", true, false)
    var out_row = list.get_child(2)
    check(out_row.find_child("Stocks", true, false).text == "OUT", "the OUT winner row reads OUT")
    check(not out_row.find_child("Damage", true, false).visible, "the OUT row shows no meaningless damage (Doc 06 §4)")
    var survivor_row = list.get_child(1)
    check(survivor_row.find_child("Stocks", true, false).text.begins_with("STOCKS"),
        "the surviving winner still shows its stocks")
    check(survivor_row.find_child("Damage", true, false).visible, "the surviving winner still shows damage")
    # Composition guard: the six-row team layout clears the action bar band.
    var bar: Button = rs.find_child("Rematch", true, false)
    check(list.get_child(5).get_global_rect().end.y < bar.get_global_rect().position.y,
        "the team standings clear the action bar")
    check(Rect2(0.0, 0.0, 1280.0, 720.0).encloses(list.get_child(5).get_global_rect()),
        "the team standings stay inside the reference frame")

    # --- reveal: six rows staggered, complete on the agreed timeline ---
    check(rs.is_revealing(), "the reveal starts on entry")
    await frames(48)
    check(rs.is_interactive(), "the reveal completes without input on the agreed timeline")
    for i in 6:
        check(rs.is_row_revealed(i), "row %d revealed on the automatic timeline" % i)
    await vs.free_hosts(self)
    await frames(3)

# ---------------------------------------------------------------------------
# Part A2 — independent palettes for two subjects of the SAME fighter
# ---------------------------------------------------------------------------
func part_a2_independent_palettes() -> void:
    print("--- part A2: two independently paletted subjects (Doc 06 §10) ---")
    var host = await vs.enter(self)
    var host_ids: Array = vs.host_ids(self)
    var arena = await vs.launch(self, host, ["ggb", "ggb", "", ""], "sky")
    check(arena != null, "the palette-proof match launches")
    if arena == null:
        return
    await vs.resolve(self, arena, [1])
    host = await vs.wait_for_new_host(self, host_ids)
    check(host != null, "the palette-proof match RETURNs to PostMatch")
    if host == null:
        return
    var post = host.post_match()
    var rs = post.result_screen
    var Payload = load("res://scripts/match_result.gd")
    var Roster = load("res://scripts/roster.gd")
    # Explicit payload (the shipped from_entries API, as the evidence fixtures
    # use): the winning team is two GGBs with their own resolved variants 2 and
    # 0, and one of them is OUT.
    var payload = Payload.from_entries("WIN", true, 0, [
        {"player_index": 1, "fighter_id": "ggb", "fighter_name": "GGB", "palette_index": 2, "team_id": 0,
            "stocks_remaining": 0, "damage_percent": 0, "eliminated": true, "elimination_batch": 0,
            "placement": 1, "team_placement": 1, "is_winner": true},
        {"player_index": 2, "fighter_id": "ggb", "fighter_name": "GGB", "palette_index": 0, "team_id": 0,
            "stocks_remaining": 2, "damage_percent": 33, "eliminated": false, "elimination_batch": -1,
            "placement": 1, "team_placement": 1, "is_winner": true},
        {"player_index": 3, "fighter_id": "teknium", "fighter_name": "TEKNIUM", "palette_index": 0, "team_id": 1,
            "stocks_remaining": 0, "damage_percent": 0, "eliminated": true, "elimination_batch": 1,
            "placement": 2, "team_placement": 2, "is_winner": false},
    ])
    post.present(payload, true)
    rs.finish_reveal()
    check(rs.is_interactive(), "the explicit payload completes the reveal")
    check(rs.get_hero_ids() == ["ggb", "ggb"], "duplicate winners both appear in the hero group")
    var view = rs.hero_view()
    if view != null:
        var nodes: Array = view.subject_nodes()
        check(nodes.size() == 2, "two subjects rendered")
        check(nodes[0].body_color == Roster.palette("ggb", 2), "the first subject uses its own resolved variant (2)")
        check(nodes[1].body_color == Roster.palette("ggb", 0), "the second subject uses its own resolved variant (0)")
        check(nodes[0].body_color != nodes[1].body_color, "two duplicates do NOT collapse to one colour")
        check(view.palette_index() == 2, "the view remembers the first subject's variant")
    await vs.free_hosts(self)
    await frames(3)

# ---------------------------------------------------------------------------
# Part B — simultaneous eliminations display the SHARED rank (never invented)
# ---------------------------------------------------------------------------
func part_b_ffa_simultaneous_tie() -> void:
    print("--- part B: FFA with a simultaneous elimination (Doc 06 §2) ---")
    var host = await vs.enter(self)
    var host_ids: Array = vs.host_ids(self)
    var arena = await vs.launch(self, host, ["teknium", "doge_man", "ggb", "turbofit"], "debug")
    check(arena != null, "the tie FFA launches from the flow")
    if arena == null:
        return
    for fighter in arena.fighters:
        fighter.set_physics_process(false)
    # Same tick: P1 and P2, no frame between (one batch); P3 resolves next tick.
    arena.fighters[0].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[0])
    arena.fighters[1].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[1])
    await frames(2)
    arena.fighters[2].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[2])
    check(arena.match_over, "the third elimination resolves the tie match")
    var host2 = await vs.wait_for_new_host(self, host_ids)
    check(host2 != null, "the tie match RETURNs to PostMatch")
    if host2 != null:
        var rs = host2.post_match().result_screen
        var tie = rs.get_result()
        check(not bool(tie.team_mode), "the payload is FFA")
        check(int(tie.entry_for_player(1)["placement"]) == 3 and int(tie.entry_for_player(2)["placement"]) == 3,
            "the simultaneous pair shares 3RD")
        check(rs.row_count() == 4, "four FFA player rows")
        check(rs.row_text(0) == "1ST  P4  TURBOFIT", "the survivor leads")
        check(rs.row_text(1) == "2ND  P3  GGB", "the later elimination follows")
        check(rs.row_text(2) == "3RD  P1  TEKNIUM" and rs.row_text(3) == "3RD  P2  DOGE MAN",
            "both simultaneous eliminations display the SAME rank")
        var invented := false
        for i in rs.row_count():
            if "4TH" in rs.row_text(i):
                invented = true
        check(not invented, "no invented 4TH is ever displayed for a tie")
        var hero = rs.hero_view()
        check(hero != null and hero.profile_name() == "RESULTS_HERO",
            "an FFA winner renders through the RESULTS_HERO profile")
        check(rs.get_hero_ids() == ["turbofit"], "the FFA hero is the declared survivor")
        var order: Array = []
        for i in rs.row_count():
            order.append(int(rs.row_entry(i).get("player_index", 0)))
        check(order == [4, 3, 1, 2], "the displayed order follows placement, then station only")
    await vs.free_hosts(self)
    await frames(3)

# ---------------------------------------------------------------------------
# Part C — the final-batch DRAW: no winner hero, entries as supplied
# ---------------------------------------------------------------------------
func part_c_draw() -> void:
    print("--- part C: DRAW (Doc 06 §2/§4) ---")
    var host = await vs.enter(self)
    var host_ids: Array = vs.host_ids(self)
    var arena = await vs.launch(self, host, ["teknium", "doge_man", "", ""], "debug")
    check(arena != null, "the two-player match launches")
    if arena == null:
        return
    for fighter in arena.fighters:
        fighter.set_physics_process(false)
    # The deciding tick removes every survivor: P1's elimination ends the match,
    # P2's arrives in the SAME tick and joins the final batch.
    arena.fighters[0].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[0])
    check(arena.match_over, "the first elimination of the deciding tick ends the match")
    arena.fighters[1].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[1])
    var host2 = await vs.wait_for_new_host(self, host_ids)
    check(host2 != null, "the drawn match RETURNs to PostMatch")
    if host2 != null:
        var post = host2.post_match()
        var rs = post.result_screen
        var result = rs.get_result()
        check(str(result.outcome) == "DRAW", "the payload declares DRAW")
        check(int(result.winning_team) == -1, "a draw names no winning team")
        check(post.outcome_label.text == "DRAW", "the heading is DRAW")
        check(not rs.find_child("OutcomeEyebrow", true, false).visible, "no WINNER eyebrow on a draw")
        check(rs.get_hero_ids().is_empty(), "a draw renders no winner hero")
        check(rs.hero_view() == null, "a draw owns no render view at all")
        check(rs.get_accent_color() == Tokens.CREAM_DIM, "a draw uses the neutral accent")
        check(rs.row_count() == 2, "both drawn players stay listed")
        check(rs.row_text(0) == "1ST  P1  TEKNIUM" and rs.row_text(1) == "1ST  P2  DOGE MAN",
            "the drawn pair shares the rank the match supplied")
        var list = rs.find_child("StandingsList", true, false)
        check(list.get_child(0).find_child("Stocks", true, false).text == "OUT", "drawn players read OUT")
        check(not list.get_child(0).find_child("Damage", true, false).visible, "no damage on an OUT entry")
        check(rs.find_child("Rematch", true, false) != null and rs.find_child("Rematch", true, false).visible,
            "the actions stay available on a draw")
    await vs.free_hosts(self)
    await frames(3)

# ---------------------------------------------------------------------------
# Part D — the route matrix's Results edges + the cancel safety, real input
# ---------------------------------------------------------------------------
func part_d_route_and_cancel_edges() -> void:
    print("--- part D: route edges + cancel safety ---")
    # D1: a standings row is not interactive; CHANGE STAGE PUSHes the SSS with
    # origin RESULTS and its Back POPs back to the SAME revealed Results.
    var host = await vs.enter(self)
    var host_ids: Array = vs.host_ids(self)
    var launched := {"count": 0}
    host.launch_requested.connect(func(_config) -> void: launched["count"] += 1)
    var arena = await vs.launch(self, host, ["ggb", "doge_man", "", ""], "sky")
    check(arena != null, "the route-edge match launches")
    if arena == null:
        return
    await vs.resolve(self, arena, [1])
    host = await vs.wait_for_new_host(self, host_ids)
    check(host != null, "the match RETURNs to PostMatch")
    if host == null:
        return
    var post = host.post_match()
    var rs = post.result_screen
    rs.finish_reveal()
    check(rs.is_interactive(), "Results is interactive")
    # A real pointer click ON a standings row: nothing happens (not a control).
    var list = rs.find_child("StandingsList", true, false)
    var row_center: Vector2 = (list.get_child(1) as Control).get_global_rect().get_center()
    var launches_before_click: int = int(launched["count"])
    click_at(row_center)
    await frames(3)
    check(host.active_surface() == "postmatch" and int(launched["count"]) == launches_before_click,
        "clicking a standings row neither routes nor activates anything")
    # CHANGE STAGE -> SSS (origin RESULTS) -> Back -> the SAME revealed Results.
    var change_stage: Button = rs.find_child("ChangeStage", true, false)
    check(change_stage != null and change_stage.visible, "Results offers Change Stage")
    change_stage.pressed.emit()
    var pushed: bool = await vs.wait_for(self, func() -> bool: return host.active_surface() == "sss", 180)
    check(pushed, "CHANGE STAGE PUSHes Stage Select")
    check(host.route_origin() == "results", "the SSS route records the RESULTS origin")
    host.stage_select().request_back()
    var back: bool = await vs.wait_for(self, func() -> bool:
            return host.active_surface() == "postmatch" and host.is_surface_presented("postmatch"), 180)
    check(back, "the SSS Back POPs back to Results")
    check(host.last_popped_origin() == "results", "the POP consumed the RESULTS origin")
    check(host.post_match().is_interactive() and not host.post_match().is_revealing(),
        "the restored Results keeps its revealed state (no replay)")
    await vs.free_hosts(self)
    await frames(3)

    # D2: the cancel safety (Doc 01 §14). A fresh RETURN: the first ui_cancel
    # inside the carry-over window is ignored; after the safety window it only
    # completes the reveal; a later ui_cancel takes the visible MAIN MENU route.
    var host2 = await vs.enter(self)
    var host2_ids: Array = vs.host_ids(self)
    var arena2 = await vs.launch(self, host2, ["ggb", "ggb", "", ""], "toy_room")
    check(arena2 != null, "the cancel-safety match launches")
    if arena2 == null:
        return
    await vs.resolve(self, arena2, [1])
    host2 = await vs.wait_for_new_host(self, host2_ids)
    check(host2 != null, "the match RETURNs for the cancel contract")
    if host2 == null:
        return
    var surface = host2.post_match()
    var rs2 = surface.result_screen
    var script = load("res://scripts/result_screen.gd")
    if rs2.reveal_tick() < script.SAFETY_TICKS:
        root.push_input(escape())
        await frames(1)
        check(surface.is_revealing(), "ui_cancel inside the carry-over window is ignored")
        check(host2.active_surface() == "postmatch", "the ignored cancel never leaves the screen")
    var in_reveal := false
    for i in 60:
        await process_frame
        if surface.is_revealing() and rs2.reveal_tick() >= script.SAFETY_TICKS:
            in_reveal = true
            break
    check(in_reveal, "the reveal is past its safety window and still running")
    root.push_input(escape())
    await frames(2)
    check(surface.is_interactive() and not surface.is_revealing(), "ui_cancel past the safety window finishes the reveal")
    check(host2.active_surface() == "postmatch" and is_instance_valid(host2),
        "one input never both finishes the reveal and leaves the screen")
    check(rs2.find_child("MainMenu", true, false).visible, "the visible MAIN MENU action is up")
    root.push_input(escape())
    var home = await vs.wait_for_scene(self, "home.tscn")
    check(home != null, "ui_cancel after reveal safety routes to Main")
    if home != null:
        home.queue_free()
    await vs.free_hosts(self)
    await frames(3)
