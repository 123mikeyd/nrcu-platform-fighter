extends SceneTree
# WP-E test migration (Doc 06 §26), MIGRATED to the PostMatch owner in WP-0
# step 5: Results is presentation/navigation over an explicit MatchResult
# snapshot, presented by the MatchFlow host's PostMatch surface — gameplay hosts
# no Results screen any more. Rejected architecture is asserted GONE: StatPanel,
# page label, Prev/Next, 160-tick wait. Rank is never inferred from damage/stocks,
# and the winner model resolves from fighter_id only.
#
# The suite drives three real resolutions through the production route (four-player
# FFA, teams, draw — each launched from the flow and resolved through the
# production elimination signal) and then presents explicit payload fixtures
# directly on the surface, exactly like the pre-migration suite did on the arena's
# result screen.
const AppStateScript = preload("res://scripts/app_state.gd")

var failures := 0
var rematch_emits := 0
var reveal_events := 0
var vs = null
var host = null
var post = null
var rs = null

func _initialize(): call_deferred("run")

func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func make_key(code: int) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    return event

func frames(count: int):
    for i in count:
        await process_frame

func act(node_name: String) -> Button:
    # The shipped action button inside the presented Results surface.
    if rs == null:
        return null
    return rs.find_child(node_name, true, false)

func resolve_ffa_match(arena: Node, survivors: Array) -> void:
    for fighter in arena.fighters:
        fighter.set_physics_process(false)
    for fighter in arena.fighters:
        if int(fighter.player_index) in survivors:
            continue
        fighter.stocks = 0
        arena._on_fighter_eliminated(fighter)

func run():
    var Tokens = load("res://scripts/ui_tokens.gd")
    var Payload = load("res://scripts/match_result.gd")
    vs = load("res://tests/fixtures/vs_route.gd").new()

    # ---------------------------------------------------------------------
    # The hidden PostMatch surface: mounted by the host, inert while merely
    # configuring, and it must not eat input while it is not presented.
    # ---------------------------------------------------------------------
    host = await vs.enter(self)
    post = host.post_match()
    check(post != null, "the MatchFlow host owns a PostMatch surface")
    check(not post.visible and not host.is_surface_presented("postmatch"),
        "PostMatch stays unpresented while merely configuring")
    # WALK-UP (Doc 08 §2 public input): a real pointer click through the tree
    # proves the hidden surface neither answers nor routes anything.
    var probe_click := InputEventMouseButton.new()
    probe_click.button_index = MOUSE_BUTTON_LEFT
    probe_click.pressed = true
    probe_click.position = Vector2(640.0, 300.0)
    Input.parse_input_event(probe_click)
    await frames(3)
    check(not post.visible and host.active_surface() == "css",
        "a hidden result screen does not answer clicks (surface unchanged)")
    check(rematch_emits == 0, "a hidden results surface never routes an action")

    # ---------------------------------------------------------------------
    # FFA: the real resolution path hands the payload over, PostMatch presents it
    # ---------------------------------------------------------------------
    var host_id: int = host.get_instance_id()
    var arena = await vs.launch(self, host, ["teknium", "doge_man", "ggb", "turbofit"], "debug")
    check(arena != null, "the four-player FFA launches from the flow")
    if arena == null:
        quit(1)
        return
    # P1 out first, P2 next, P3 last — P4 survives.
    resolve_ffa_match(arena, [4])
    check(arena.match_over, "the match resolves at the last elimination")
    host = await vs.wait_for_flow(self, host_id)
    check(host != null, "the completed match RETURNs to the MatchFlow host")
    check(not is_instance_valid(arena), "gameplay is torn down before Results is interactive")
    if host == null:
        quit(1)
        return
    post = host.post_match()
    check(post != null and post.visible, "PostMatch is presented over the payload")
    rs = post.result_screen
    rs.rematch_requested.connect(func(): rematch_emits += 1)
    var events = root.get_node_or_null("FrontendEvents")
    if events != null:
        events.results_reveal.connect(func(): reveal_events += 1)

    var result = rs.get_result()
    check(result != null, "the host passed the payload gameplay produced")
    if result == null:
        quit(1)
        return
    check(str(result.outcome) == "WIN", "FFA outcome is WIN")
    check(not bool(result.team_mode), "FFA payload is not team mode")
    check(int(result.winning_team) == -1, "no winning team in FFA")
    check(result.entries.size() == 4, "one entry per active player")
    var required := ["player_index", "fighter_id", "fighter_name", "team_id", "placement",
        "stocks_remaining", "damage_percent", "eliminated", "elimination_order", "is_winner"]
    var complete := true
    var ids: Array = []
    var places: Array = []
    for entry in result.entries:
        for field in required:
            if not entry.has(field):
                complete = false
        check(str(entry.get("fighter_id", "")) != "", "entry carries a mandatory fighter_id")
        ids.append(str(entry["fighter_id"]))
        places.append(int(entry["placement"]))
    check(complete, "every entry carries the full MatchResult field set")
    check(ids.size() == 4 and ids.count("turbofit") == 1, "stable fighter ids identify all four players")
    check(places.min() == 1 and places.max() == 4 and not places.has(0), "placement is assigned by match logic")
    check(int(result.entry_for_player(4)["placement"]) == 1, "survivor is 1ST")
    check(int(result.entry_for_player(3)["placement"]) == 2, "last eliminated is 2ND")
    check(int(result.entry_for_player(2)["placement"]) == 3, "previous elimination is 3RD")
    check(int(result.entry_for_player(1)["placement"]) == 4, "first eliminated is 4TH")
    var ffa_winner: Dictionary = result.winner_entry()
    check(not ffa_winner.is_empty() and int(ffa_winner["player_index"]) == 4 and bool(ffa_winner["is_winner"]), "declared winner is P4")
    check(str(result.entry_for_player(4)["fighter_id"]) == "turbofit", "winner fighter_id is stable")
    check(int(result.entry_for_player(1)["elimination_order"]) == 0, "first elimination is order 0")
    check(int(result.entry_for_player(2)["elimination_order"]) == 1, "elimination order tracks the match sequence")
    check(int(result.entry_for_player(3)["elimination_order"]) == 2, "last eliminated carries the final order")

    # Top outcome header: winner identity is the primary title, no second line.
    check(post.outcome_label.visible, "outcome header is up with the result")
    check(post.outcome_label.text == "P4 TURBOFIT", "outcome header names the declared winner")
    check(not ("WINS!" in post.outcome_label.text), "no redundant WINS! line beneath the name")
    check(rs.find_child("OutcomeEyebrow", true, false).visible and rs.find_child("OutcomeEyebrow", true, false).text == "WINNER", "WINNER eyebrow sits above the identity")

    # Winner hero resolves DIRECTLY from fighter_id.
    check(rs.get_hero_ids() == ["turbofit"], "winner hero resolves from the payload fighter_id")

    # Standings: placement order, one row per player, OUT without damage.
    var list = rs.find_child("StandingsList", true, false)
    check(list != null, "standings list exists")
    check(list.get_child_count() == 4, "four standings rows")
    var row0 = list.get_child(0)
    var row1 = list.get_child(1)
    var row2 = list.get_child(2)
    var row3 = list.get_child(3)
    check(row0.find_child("Rank", true, false).text == "1ST" and row0.find_child("Name", true, false).text == "TURBOFIT", "standings lead with the 1ST placement")
    check(row1.find_child("Rank", true, false).text == "2ND" and row1.find_child("Name", true, false).text == "GGB", "standings follow elimination order")
    check(row3.find_child("Rank", true, false).text == "4TH" and row3.find_child("Name", true, false).text == "TEKNIUM", "first eliminated is last in the standings")
    check(row0.find_child("Stocks", true, false).text == "STOCKS 3", "surviving player shows stocks")
    check(row0.find_child("Damage", true, false).visible, "surviving player shows damage")
    check(row1.find_child("Stocks", true, false).text == "OUT", "eliminated player reads OUT")
    check(not row1.find_child("Damage", true, false).visible, "eliminated player shows no damage field (Doc 06 §19)")
    check(row0.find_child("Port", true, false).text == "P4" and row0.find_child("Port", true, false).get_theme_color("font_color") == Tokens.PLAYER_COLORS[3], "player identity marker uses the player color")

    # Rejected architecture must be gone.
    check(rs.find_child("StatPanel", true, false) == null, "no StatPanel inspector")
    check(rs.find_child("PageLabel", true, false) == null, "no page label")
    check(rs.find_child("PrevPage", true, false) == null and rs.find_child("NextPage", true, false) == null, "no page buttons")
    check(rs.find_child("WaitHint", true, false) == null, "no long wait hint")
    check(act("MainMenu") != null and act("MainMenu").visible, "visible Main Menu action")
    check(act("ChangeFighters").visible, "visible Change Fighters action")
    check(act("ChangeStage").visible, "Change Stage is supported by the PostMatch route")

    # Reveal timeline (Doc 06 §16) + RESULT_REVEAL_GUARD.
    check(rs.is_revealing() and not rs.is_interactive(), "reveal starts on entry, actions are not yet interactive")
    check(not rs.is_outcome_revealed(), "nothing is revealed on the first frame")
    check(act("Rematch").disabled, "action buttons are disabled during the reveal")
    await frames(8)
    check(rs.is_outcome_revealed(), "outcome + hero resolve in the first frames (4-18f)")
    check(not rs.is_row_revealed(0), "standings have not entered yet at ~8f")
    check(not rs.is_interactive(), "controls are not withheld but still resolving at ~8f")
    await frames(8)
    check(rs.is_row_revealed(0) and rs.is_row_revealed(1), "standings entered top-to-bottom by ~16f")
    check(not rs.is_row_revealed(3), "later rows still staggered")
    check(not rs.is_interactive(), "action bar still resolving at ~16f")
    # One fresh confirm finishes the reveal and must NOT trigger an action.
    # WALK-UP (Doc 08 §2 public input): the confirm is a real keyboard accept
    # event through the tree; the reveal guard is answered on the semantic path.
    Input.parse_input_event(make_key(KEY_ENTER))
    await frames(3)
    check(rs.is_interactive(), "a fresh confirm finishes the reveal immediately")
    check(rematch_emits == 0, "the finishing input did not trigger Rematch")
    check(post.visible and host.active_surface() == "postmatch", "no action fired from the finishing input")
    check(reveal_events == 1, "reveal completion emits the semantic results_reveal event exactly once")
    check(not act("Rematch").disabled, "action bar is interactive once the reveal completes")
    for i in 4:
        check(rs.is_row_revealed(i), "row %d revealed after the reveal completes" % i)
    # Composition guard: the payoff stays inside the frame and clear of the bar.
    var frame_rect := Rect2(0.0, 0.0, 1280.0, 720.0)
    check(frame_rect.encloses(list.get_global_rect()) and frame_rect.encloses(row3.get_global_rect()), "standings stay inside the reference frame")
    check(not list.get_global_rect().intersects(act("Rematch").get_global_rect()), "standings never collide with the action bar")
    check(row3.get_global_rect().end.y < act("Rematch").get_global_rect().position.y, "main payoff clears the action bar band")
    check(rs.find_child("OutcomeRule", true, false).get_global_rect().end.y < row0.get_global_rect().position.y, "outcome header band sits above the payoff")
    check(rs.find_child("HeroField", true, false).get_global_rect().end.y < act("Rematch").get_global_rect().position.y, "winner hero clears the action bar")
    check(frame_rect.encloses(act("MainMenu").get_global_rect()), "action bar stays inside the reference frame")

    # The actions themselves still work after the reveal: REMATCH is the router's
    # LAUNCH from the preserved config and rebuilds the same match.
    act("Rematch").pressed.emit()
    check(rematch_emits == 1, "exactly one action fired from the real activation")
    var arena2: Node = host.gameplay_node()
    var relaunched := false
    for i in 240:
        await process_frame
        if arena2 != null and is_instance_valid(arena2) and arena2.ready_remaining > 0 and not is_instance_valid(host):
            relaunched = true
            break
    check(relaunched, "rematch relaunches gameplay with the shipped READY countdown")
    if relaunched:
        check(not arena2.match_over and arena2.fighters.size() == 4, "rematch rebuilds the four-player match")

    # Second result: no input at all; the reveal must complete on its own.
    if relaunched:
        var before_ids: Array = vs.host_ids(self)
        resolve_ffa_match(arena2, [4])
        host = await vs.wait_for_new_host(self, before_ids)
        check(host != null, "the second match RETURNs to PostMatch")
        if host != null:
            post = host.post_match()
            rs = post.result_screen
            check(rs.is_revealing(), "result again in the reveal phase")
            check(post.find_children("*", "SubViewport", true, false).size() == 1, "exactly one winner render viewport")
            await frames(48)
            check(rs.is_interactive(), "no input: the full reveal completes within the agreed timeline (~40f)")
            check(reveal_events == 2, "the automatic reveal also emits exactly one results_reveal")
            check(not act("Rematch").disabled, "action bar interactive after the automatic reveal")
            for i in 4:
                check(rs.is_row_revealed(i), "row %d revealed on the automatic timeline" % i)

    # ---------------------------------------------------------------------
    # Team mode (Doc 06 §5): the winning TEAM is the outcome, its players
    # are the hero group, rows stay individual.
    # ---------------------------------------------------------------------
    var team_before: Array = vs.host_ids(self)
    host = await vs.enter(self)
    host_id = host.get_instance_id()
    check(vs.set_mode(host, 1), "the flow state switches to teams")
    arena = await vs.launch(self, host, ["teknium", "doge_man", "ggb", "turbofit"], "debug")
    check(arena != null, "the team match launches")
    if arena != null:
        for fighter in arena.fighters:
            fighter.set_physics_process(false)
        arena.fighters[0].stocks = 0
        arena._on_fighter_eliminated(arena.fighters[0])
        check(not arena.match_over, "team match continues after one elimination")
        arena.fighters[2].stocks = 0
        arena._on_fighter_eliminated(arena.fighters[2])
        check(arena.match_over, "team result resolves")
        host = await vs.wait_for_new_host(self, team_before)
        if host != null:
            post = host.post_match()
            rs = post.result_screen
            var team_result = rs.get_result()
            check(bool(team_result.team_mode), "team payload is marked team mode")
            check(int(team_result.winning_team) == 1, "winning team comes from match logic")
            check(str(team_result.entry_for_player(2)["team_id"]) == "1", "entries supply team ids in team mode")
            check(post.outcome_label.text == "TEAM B WINS!", "team heading names the winning team")
            check(rs.get_accent_color() == Tokens.TEAM_B, "team result uses the team color, not a player color")
            check(rs.get_hero_ids() == ["doge_man", "turbofit"], "winner group contains the winning team players")
            var team_list = rs.find_child("StandingsList", true, false)
            check(team_list.get_child(0).find_child("Name", true, false).text == "DOGE MAN", "team standings stay individual and placed")
            check(team_list.get_child(3).find_child("Name", true, false).text == "TEKNIUM", "eliminated team players remain in the standings")

    # ---------------------------------------------------------------------
    # Draw (Doc 06 §4): heading DRAW, placements as supplied, no winner hero.
    # ---------------------------------------------------------------------
    var draw_before: Array = vs.host_ids(self)
    host = await vs.enter(self)
    host_id = host.get_instance_id()
    arena = await vs.launch(self, host, ["teknium", "doge_man", "ggb", "turbofit"], "debug")
    check(arena != null, "the draw match launches")
    if arena != null:
        for fighter in arena.fighters:
            fighter.set_physics_process(false)
        for fighter in arena.fighters:
            fighter.stocks = 0
        arena._on_fighter_eliminated(arena.fighters[3])
        check(arena.match_over, "no survivors resolves the match")
        host = await vs.wait_for_new_host(self, draw_before)
        if host != null:
            post = host.post_match()
            rs = post.result_screen
            var draw_result = rs.get_result()
            check(str(draw_result.outcome) == "DRAW", "payload declares DRAW")
            check(int(draw_result.winning_team) == -1, "no winning team on a draw")
            check(post.outcome_label.text == "DRAW", "draw heading is DRAW")
            check(rs.get_hero_ids().is_empty(), "no winner hero on a draw")

    if host == null or post == null or rs == null:
        await vs.free_hosts(self)
        await vs.free_arenas(self)
        quit(1 if failures else 0)
        return

    # ---------------------------------------------------------------------
    # Explicit placement vs damage order: the display follows placement,
    # never stats (Doc 06 §2).
    # ---------------------------------------------------------------------
    var placed = Payload.from_entries("WIN", false, -1, [
        {"player_index": 4, "fighter_id": "turbofit", "fighter_name": "TURBOFIT", "team_id": -1, "placement": 2, "stocks_remaining": 3, "damage_percent": 12, "eliminated": false, "elimination_order": -1, "is_winner": false},
        {"player_index": 3, "fighter_id": "ggb", "fighter_name": "GGB", "team_id": -1, "placement": 3, "stocks_remaining": 0, "damage_percent": 0, "eliminated": true, "elimination_order": 1, "is_winner": false},
        {"player_index": 1, "fighter_id": "teknium", "fighter_name": "TEKNIUM", "team_id": -1, "placement": 4, "stocks_remaining": 0, "damage_percent": 0, "eliminated": true, "elimination_order": 0, "is_winner": false},
        {"player_index": 2, "fighter_id": "doge_man", "fighter_name": "DOGE MAN", "team_id": -1, "placement": 1, "stocks_remaining": 1, "damage_percent": 137, "eliminated": false, "elimination_order": -1, "is_winner": true},
    ])
    rs.show_result(placed, false)
    rs.finish_reveal()
    check(rs.is_interactive(), "explicit payload completes the reveal")
    check(post.outcome_label.text == "P2 DOGE MAN", "outcome follows the declared winner, not the stocks leader")
    check(rs.get_hero_ids() == ["doge_man"], "hero follows the declared winner, not the stocks/damage leader")
    var placed_list = rs.find_child("StandingsList", true, false)
    var ports: Array = []
    for i in 4:
        var row = placed_list.get_child(i)
        ports.append(row.find_child("Port", true, false).text)
    check(ports == ["P2", "P4", "P3", "P1"], "standings sorted by placement, each player exactly once")
    check(placed_list.get_child(0).find_child("Rank", true, false).text == "1ST" and placed_list.get_child(0).find_child("Name", true, false).text == "DOGE MAN", "row 0 is the explicitly placed 1ST")
    check(placed_list.get_child(1).find_child("Name", true, false).text == "TURBOFIT", "row 1 is the explicitly placed 2ND despite the damage order")
    check(placed_list.get_child(1).find_child("Damage", true, false).visible and placed_list.get_child(1).find_child("Damage", true, false).text == "12%", "surviving row shows its damage")
    check(not placed_list.get_child(2).find_child("Damage", true, false).visible and placed_list.get_child(2).find_child("Stocks", true, false).text == "OUT", "eliminated row shows OUT and no damage")
    check(placed_list.get_child(1).find_child("Port", true, false).text == "P4", "player tags stay individual")

    # Unknown fighter_id: text hero only, NEVER a display-name reverse lookup.
    var bad = Payload.from_entries("WIN", false, -1, [
        {"player_index": 1, "fighter_id": "not_a_fighter", "fighter_name": "TEKNIUM", "team_id": -1, "placement": 1, "stocks_remaining": 2, "damage_percent": 10, "eliminated": false, "elimination_order": -1, "is_winner": true},
        {"player_index": 2, "fighter_id": "doge_man", "fighter_name": "DOGE MAN", "team_id": -1, "placement": 2, "stocks_remaining": 0, "damage_percent": 0, "eliminated": true, "elimination_order": 0, "is_winner": false},
    ])
    rs.show_result(bad, false)
    rs.finish_reveal()
    check(rs.get_hero_ids().is_empty(), "unknown fighter_id never falls back to a display-name lookup")
    check(rs.find_child("HeroText", true, false).visible, "unresolvable id keeps a text hero, never a blank frame")

    # Change Stage appears only when the route supports it (no blank slot).
    rs.show_result(placed, true)
    check(act("ChangeStage").visible, "Change Stage appears only when supported")
    check(act("ChangeStage").position.x == 456.0, "no blank slot: Main Menu closes the gap")
    rs.show_result(placed, false)
    check(not act("ChangeStage").visible, "Change Stage hidden again when unsupported")

    # Regular cursor: no token state, stale hover cleared, focus seeds Rematch.
    var hand = host.get_node_or_null("/root/Cursor").hand
    var token := Control.new()
    rs.add_child(token)
    hand.set_carry(token)
    check(hand.is_carrying(), "precondition: a token is being carried")
    rs.show_result(placed, false)
    check(not hand.is_carrying(), "results use the regular cursor (carry state dropped)")
    check(hand.hovered == null, "stale hover cleared on entry")
    token.queue_free()
    rs.finish_reveal()
    var rematch_button = act("Rematch")
    hand.set_mode(1)   # HandCursor.Mode.FOCUS
    check(rematch_button.has_focus(), "controller focus seeds REMATCH")
    var anchor = post.find_child("CursorAnchor", true, false)
    check(anchor != null and anchor.get_script() != null, "REMATCH exposes an authored CursorAnchor")
    hand.set_mode(0)

    # Story vocabulary: the player route is Story -> Main and the story surface
    # is frontend-owned since WP-0 step 4 — the arena mounts no story panel of
    # its own, no Results screen (WP-0 step 5), and the briefing's at-rest Back
    # samples the player route.
    var briefing = load("res://scenes/story_briefing.tscn").instantiate()
    root.add_child(briefing)
    await process_frame
    check(str(briefing.back_button().text) == "BACK TO MAIN", "story back uses the player route vocabulary")
    briefing.queue_free()
    await process_frame
    var direct = load("res://scenes/main.tscn").instantiate()
    root.add_child(direct)
    await frames(5)
    check(direct.find_child("StoryBriefing", true, false) == null, "gameplay mounts no story panel")
    check(direct.find_child("StoryCharacterSelect", true, false) == null,
        "no hidden story selection model inside gameplay (superseded by MatchFlowState)")
    check(direct.story_state == "", "the arena carries no story state outside a story launch")
    check(direct.find_child("ResultPanel", true, false) == null, "gameplay hosts no Results screen (WP-0 step 5)")
    check(direct.find_child("ResultScreen", true, false) == null, "gameplay hosts no result_screen instance")
    check(direct.get("result_screen") == null and direct.get("winner_label") == null,
        "gameplay exposes no Results handles")
    direct.queue_free()
    await process_frame

    await vs.free_hosts(self)
    await vs.free_arenas(self)
    if failures == 0:
        print("PASS: results payload (explicit placement/fighter_id), winner-first rebuild, reveal timeline, team/draw, cursor and story vocabulary — presented by the MatchFlow PostMatch owner")
    quit(1 if failures else 0)

