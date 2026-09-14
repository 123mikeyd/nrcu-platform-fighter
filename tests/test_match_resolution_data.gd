extends SceneTree
# WP-5 LANE B — MATCH RESOLUTION DATA CONTRACT.
#
# Authority: Doc 06 §1-§4 (stable resolution boundary, elimination batches/ties,
# team semantics, the complete MatchResult snapshot), Doc 01 §3 (team mode:
# >= 2 active, both sides; members SHARE rank) and §12 (standings: FFA rows, team
# grouping, no pagination), Doc 02 §4 (immutable end-state data).
#
# Protected contract:
#   * one logical frame/tick collects ALL of its pending eliminations into ONE
#     batch BEFORE survivors/teams are resolved and the snapshot is constructed
#     (Doc 06 §1) — the transient-survivor winner bug cannot happen;
#   * simultaneous eliminations share an elimination_batch and share a placement
#     (Doc 06 §2: "P3 3RD, P4 3RD", never an invented player_index order);
#   * the final batch that removes every survivor is a DRAW (Doc 06 §2);
#   * team mode is TEAM-ranked: members share their team's rank, winning
#     teammates are NEVER ranked against each other (Doc 06 §3, Doc 01 §12);
#   * the snapshot carries the complete field set (Doc 02 §4) and is IMMUTABLE:
#     later fighter mutation cannot change it;
#   * the hero group contains EVERY winning teammate, including one eliminated
#     before match end (Doc 06 §3/§7).
#
# Evidence classes: DATA_CONTRACT for the resolution algebra (the subject under
# test), ROUTE_CONTRACT for the live arena -> PostMatch hand-off.

const StateScript = preload("res://scripts/match_flow_state.gd")

# The documented snapshot field set (Doc 02 §4 / Doc 06 §4).
const FIELDS := ["player_index", "fighter_id", "fighter_name", "palette_index", "team_id",
    "stocks_remaining", "damage_percent", "eliminated", "elimination_batch", "placement",
    "team_placement", "is_winner"]

var failures := 0
var payload                            # scripts/match_result.gd
var vs                                 # tests/fixtures/vs_route.gd helper
var roster                             # scripts/roster.gd palette authority

class FakeFighter extends RefCounted:
    # The resolver reads live fighter PROPERTIES; a lightweight stand-in lets the
    # data contract be exercised without a running match (the live path is
    # covered separately at the end of this suite).
    var player_index := 1
    var character_id := "ggb"
    var fighter_name := "GGB"
    var team_id := -1
    var stocks := 3
    var damage_percent := 0.0

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func frames(count: int) -> void:
    for i in count:
        await process_frame

func fighter(player_index: int, fighter_id: String, stocks: int, team_id := -1) -> RefCounted:
    var f := FakeFighter.new()
    f.player_index = player_index
    f.character_id = fighter_id
    f.fighter_name = fighter_id.to_upper()
    f.team_id = team_id
    f.stocks = stocks
    return f

func run() -> void:
    payload = load("res://scripts/match_result.gd")
    vs = load("res://tests/fixtures/vs_route.gd").new()
    roster = load("res://scripts/roster.gd")
    doc_example_batches_and_ties()
    tie_determinism()
    final_batch_draw()
    team_ranking_shares_rank()
    field_set_and_immutability()
    await live_frame_batch_boundary()
    await live_distinct_ticks_and_handoff()
    if failures > 0:
        print("FAILURES: %d" % failures)
        quit(1)
        return
    print("PASS: match resolution data (deferred elimination batches, simultaneous tie sharing, final-batch DRAW, shared team ranks, complete immutable field set)")
    quit(0)

# ---------------------------------------------------------------------------
# 1. Doc 06 §2's worked example, verbatim.
# ---------------------------------------------------------------------------
func doc_example_batches_and_ties() -> void:
    print("--- part 1: documented batch example ---")
    var fighters := [fighter(1, "teknium", 3), fighter(2, "doge_man", 0),
                     fighter(3, "ggb", 0), fighter(4, "turbofit", 0)]
    # batch 0: P3 + P4 eliminated together; batch 1: P2 eliminated; P1 survives.
    var result = payload.resolve(fighters, false, [[3, 4], [2]])
    check(str(result.outcome) == "WIN", "a surviving player means the outcome is WIN")
    check(int(result.winning_team) == -1, "FFA carries no winning team")
    check(int(result.entry_for_player(1)["placement"]) == 1, "survivor is 1ST")
    check(int(result.entry_for_player(2)["placement"]) == 2, "the later elimination is 2ND")
    check(int(result.entry_for_player(3)["placement"]) == 3, "a simultaneous elimination is 3RD")
    check(int(result.entry_for_player(4)["placement"]) == 3, "the other simultaneous elimination is 3RD too (never an invented 4TH)")
    check(int(result.entry_for_player(3)["elimination_batch"]) == 0, "P3 carries batch identity 0")
    check(int(result.entry_for_player(4)["elimination_batch"]) == 0, "P4 shares batch identity 0")
    check(int(result.entry_for_player(2)["elimination_batch"]) == 1, "P2 carries batch identity 1")
    check(int(result.entry_for_player(1)["elimination_batch"]) == -1, "a survivor carries no elimination batch")
    check(int(result.entry_for_player(1)["stocks_remaining"]) == 3, "the survivor snapshots its remaining stocks")
    var winner: Dictionary = result.winner_entry()
    check(not winner.is_empty() and int(winner["player_index"]) == 1, "the declared winner is the survivor")
    check(result.winning_entries().size() == 1, "exactly one hero entry in FFA")
    check(bool(result.entry_for_player(2)["eliminated"]), "an out-of-stocks entry is marked eliminated")
    var places: Array = []
    for entry in result.entries:
        places.append(int(entry["placement"]))
    check(places == [1, 2, 3, 3], "the standings order is rank order with the tie adjacent")

# ---------------------------------------------------------------------------
# 2. Batch identity decides ranks, never player index and never signal order.
# ---------------------------------------------------------------------------
func tie_determinism() -> void:
    print("--- part 2: tie determinism ---")
    var a := [fighter(1, "ggb", 0), fighter(2, "ggb", 0), fighter(3, "ggb", 0), fighter(4, "ggb", 3)]
    # Same simultaneity, opposite observation order inside the batch.
    var first = payload.resolve(a, false, [[2, 1], [3]])
    var second = payload.resolve(a, false, [[1, 2], [3]])
    var first_places: Array = []
    var second_places: Array = []
    for entry in first.entries:
        first_places.append(int(entry["placement"]))
    for entry in second.entries:
        second_places.append(int(entry["placement"]))
    check(first_places == second_places, "the batch's internal order never changes the placements")
    check(int(first.entry_for_player(1)["placement"]) == int(first.entry_for_player(2)["placement"]),
        "two players in the same batch always share a placement")
    check(int(first.entry_for_player(1)["placement"]) == 3, "the shared rank of the first batch is 3RD")
    check(int(first.entry_for_player(4)["placement"]) == 1, "the survivor stays 1ST")
    # Caller order of the fighter list is not rank data either.
    var shuffled := [a[3], a[0], a[2], a[1]]
    var reordered = payload.resolve(shuffled, false, [[2, 1], [3]])
    check(int(reordered.entry_for_player(1)["placement"]) == 3
        and int(reordered.entry_for_player(3)["placement"]) == 2,
        "a different fighter list order resolves to the same ranks")
    # A flat (non-batched) input is the historical shape: one batch per element,
    # so those eliminations are demonstrably NOT simultaneous.
    var flat = payload.resolve(a, false, [1, 2, 3])
    check(int(flat.entry_for_player(1)["placement"]) == 4 and int(flat.entry_for_player(2)["placement"]) == 3
        and int(flat.entry_for_player(3)["placement"]) == 2,
        "separately observed eliminations keep unique placements (later batch ranks better)")

# ---------------------------------------------------------------------------
# 3. Doc 06 §2: the final batch that removes every survivor is a DRAW.
# ---------------------------------------------------------------------------
func final_batch_draw() -> void:
    print("--- part 3: final-batch DRAW ---")
    var fighters := [fighter(1, "ggb", 0), fighter(2, "ggb", 0), fighter(3, "ggb", 0), fighter(4, "ggb", 0)]
    var result = payload.resolve(fighters, false, [[1], [2, 3, 4]])
    check(str(result.outcome) == "DRAW", "the final batch removed every survivor: DRAW")
    check(int(result.winning_team) == -1, "a draw names no winning team")
    check(result.winner_entry().is_empty(), "a draw has no FFA winner entry")
    check(result.winning_entries().is_empty(), "a draw has no hero group")
    check(int(result.entry_for_player(2)["placement"]) == 1
        and int(result.entry_for_player(3)["placement"]) == 1
        and int(result.entry_for_player(4)["placement"]) == 1,
        "the wiped batch shares 1ST instead of an invented order")
    check(int(result.entry_for_player(1)["placement"]) == 4,
        "the earlier elimination ranks below the whole wiped batch (competition ranking)")

# ---------------------------------------------------------------------------
# 4. Team semantics (Doc 06 §3, Doc 01 §3/§12).
# ---------------------------------------------------------------------------
func team_ranking_shares_rank() -> void:
    print("--- part 4: team ranking ---")
    # TEAM A = P1/P2, TEAM B = P3. P2 (a winning teammate) goes out first.
    var fighters := [fighter(1, "teknium", 3, 0), fighter(2, "doge_man", 0, 0), fighter(3, "ggb", 0, 1)]
    var result = payload.resolve(fighters, true, [[2], [3]])
    check(bool(result.team_mode), "the snapshot marks team mode")
    check(str(result.outcome) == "WIN", "one team standing means WIN")
    check(int(result.winning_team) == 0, "the surviving team is the declared winner")
    check(int(result.entry_for_player(1)["team_placement"]) == 1
        and int(result.entry_for_player(2)["team_placement"]) == 1,
        "both members of the winning team share rank 1")
    check(int(result.entry_for_player(1)["placement"]) == int(result.entry_for_player(2)["placement"]),
        "winning teammates are NOT ranked against each other (eliminated member keeps the rank)")
    check(int(result.entry_for_player(3)["team_placement"]) == 2, "the losing team ranks below")
    check(bool(result.entry_for_player(2)["is_winner"]), "an eliminated winning teammate is still a winner (Doc 06 §3)")
    check(result.winning_entries().size() == 2, "the hero group holds EVERY winning teammate")
    var hero_ids: Array = []
    for entry in result.winning_entries():
        hero_ids.append(str(entry["fighter_id"]))
    check(hero_ids == ["teknium", "doge_man"], "the hero group is the complete winning team, survivor first")
    var groups: Array = result.team_standings()
    check(groups.size() == 2, "team standings group by team")
    check(int(groups[0]["team_id"]) == 0 and int(groups[0]["placement"]) == 1, "the winning team leads the standings")
    check(groups[0]["entries"].size() == 2, "the winning group carries both member rows")
    check(int(groups[1]["team_id"]) == 1 and int(groups[1]["placement"]) == 2, "the losing team follows at 2ND")
    check(int(result.entry_for_player(3)["placement"]) == 2, "an eliminated losing member shares its team rank")

    # Both teams wiped in the deciding tick: no winner, both teams share 1ST.
    var wiped := [fighter(1, "ggb", 0, 0), fighter(2, "ggb", 0, 1)]
    var drawn = payload.resolve(wiped, true, [[1, 2]])
    check(str(drawn.outcome) == "DRAW", "a team draw is still a DRAW")
    check(int(drawn.winning_team) == -1, "a team draw names no winning team")
    check(drawn.winning_entries().is_empty(), "a team draw has no hero group")
    check(int(drawn.entry_for_player(1)["team_placement"]) == int(drawn.entry_for_player(2)["team_placement"]),
        "the wiped teams share a rank rather than inventing a team order")

# ---------------------------------------------------------------------------
# 5. The complete field set, and the snapshot's immutability.
# ---------------------------------------------------------------------------
func field_set_and_immutability() -> void:
    print("--- part 5: field set + immutability ---")
    var fighters := [fighter(1, "ggb", 0), fighter(2, "ggb", 0), fighter(3, "ggb", 4)]
    fighters[0].damage_percent = 61.0
    var result = payload.resolve(fighters, false, [[1, 2]])
    check(result.entries.size() == 3, "one snapshot entry per participating station")
    for entry in result.entries:
        var missing: Array = []
        for field in FIELDS:
            if not entry.has(field):
                missing.append(field)
        check(missing.is_empty(), "entry %d carries the documented field set (missing %s)" % [int(entry["player_index"]), str(missing)])
        check(entry.keys().size() == FIELDS.size(),
            "entry %d carries ONLY the documented field set (got %s)" % [int(entry["player_index"]), str(entry.keys())])
    # Palette variants resolve in station order: first occurrence keeps 0.
    check(int(result.entry_for_player(1)["palette_index"]) == 0, "the first occurrence of a fighter resolves variant 0")
    check(int(result.entry_for_player(2)["palette_index"]) == 1, "a duplicate resolves the next variant")
    check(int(result.entry_for_player(3)["palette_index"]) == 2, "the third duplicate keeps counting")
    check(int(result.entry_for_player(1)["damage_percent"]) == 61, "the snapshot rounds the live damage percent")
    check(int(result.entry_for_player(3)["stocks_remaining"]) == 4, "the snapshot copies the live stocks")
    check(bool(result.entry_for_player(1)["eliminated"]) and not bool(result.entry_for_player(3)["eliminated"]),
        "elimination is read from the live stocks")
    # IMMUTABILITY: the live match state moves on (reset / rematch / teardown) and
    # the snapshot does not.
    for f in fighters:
        f.stocks = 3
        f.damage_percent = 0.0
        f.character_id = "mephisto"
        f.fighter_name = "MEPHISTO"
        f.team_id = 1
        f.player_index = 9
    check(str(result.outcome) == "WIN" and result.entries.size() == 3, "the snapshot keeps its outcome and size")
    check(int(result.entry_for_player(1)["stocks_remaining"]) == 0, "the snapshot keeps the eliminated member's stocks")
    check(bool(result.entry_for_player(1)["eliminated"]), "the snapshot keeps the eliminated flag")
    check(int(result.entry_for_player(1)["damage_percent"]) == 61, "the snapshot keeps its damage reading")
    check(str(result.entry_for_player(1)["fighter_id"]) == "ggb", "the snapshot keeps the stable fighter id")
    check(str(result.entry_for_player(1)["fighter_name"]) == "GGB", "the snapshot keeps the display name")
    check(int(result.entry_for_player(1)["team_id"]) == -1, "the snapshot keeps the team id")
    check(int(result.entry_for_player(1)["team_placement"]) == 2, "the snapshot keeps its placement")
    check(int(result.entry_for_player(1)["player_index"]) == 1, "the snapshot keeps its player index")
    # A second resolution over the mutated fighters is independent data.
    var second = payload.resolve(fighters, false, [])
    check(second.entries.size() == 3 and int(second.entries[0]["stocks_remaining"]) == 3,
        "a later resolution reads the later state")
    check(int(second.entries[0]["player_index"]) == 9, "the later resolution sees the mutated station")
    check(int(result.entry_for_player(1)["stocks_remaining"]) == 0, "the earlier snapshot is untouched by it")

# ---------------------------------------------------------------------------
# 6. Live path: the batch boundary is the frame/tick (Doc 06 §1).
# ---------------------------------------------------------------------------
func live_frame_batch_boundary() -> void:
    print("--- part 6: live frame/tick batch boundary ---")
    # 6a — two of three players fall out in the SAME frame: one batch, shared rank.
    var before: Array = vs.host_ids(self)
    var arena := await launch_arena([["ggb", "human"], ["ggb", "bot"], ["ggb", "bot"], ["", "empty"]])
    check(arena != null, "the three-player FFA launches")
    if arena == null:
        return
    check(arena.fighters.size() == 3, "three active stations reach the match")
    # Same frame, same stack: no tick boundary between these two signals.
    arena.fighters[0].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[0])
    arena.fighters[1].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[1])
    check(arena.match_over, "the deciding elimination resolves the match")
    var host = await vs.wait_for_new_host(self, before)
    check(host != null, "the resolved match hands its payload to the PostMatch surface")
    if host != null:
        var result = host.post_match_result()
        check(result != null, "the payload carries the immutable MatchResult")
        if result != null:
            check(int(result.entry_for_player(1)["elimination_batch"]) == 0
                and int(result.entry_for_player(2)["elimination_batch"]) == 0,
                "both same-frame eliminations are recorded in ONE batch")
            check(int(result.entry_for_player(1)["placement"]) == int(result.entry_for_player(2)["placement"]),
                "same-frame eliminations share a placement")
            check(int(result.entry_for_player(1)["placement"]) == 2, "the simultaneous pair shares 2ND")
            check(int(result.entry_for_player(3)["placement"]) == 1, "the survivor is 1ST")
            check(int(result.winner_entry().get("player_index", 0)) == 3, "the deferred resolution crowns the real survivor")
    await teardown()

    # 6b — the deciding tick removes EVERY survivor: DRAW, not a transient winner.
    before = vs.host_ids(self)
    arena = await launch_arena([["ggb", "human"], ["ggb", "bot"], ["", "empty"], ["", "empty"]])
    check(arena != null, "the deciding-tick match launches")
    if arena == null:
        return
    check(arena.fighters.size() == 2, "two active stations reach the match")
    arena.fighters[0].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[0])
    check(arena.match_over, "the first elimination of the deciding tick ends the match")
    arena.fighters[1].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[1])
    host = await vs.wait_for_new_host(self, before)
    check(host != null, "the double knockout still hands a payload over")
    if host != null:
        var drawn = host.post_match_result()
        check(drawn != null, "the payload carries the immutable MatchResult")
        if drawn != null:
            check(int(drawn.entry_for_player(1)["elimination_batch"]) == int(drawn.entry_for_player(2)["elimination_batch"]),
                "the second fighter of the decisive tick joins the SAME batch")
            check(str(drawn.outcome) == "DRAW", "the final batch removed every survivor: DRAW")
            check(drawn.winner_entry().is_empty(), "no transient survivor is crowned from the first signal")
            check(int(drawn.winning_team) == -1, "a draw names no winning team")
    await teardown()

func arena_body_color(entry: Dictionary, arena: Node) -> Color:
    for f in arena.fighters:
        if int(f.player_index) == int(entry["player_index"]):
            return f.body_color
    return Color.BLACK

# ---------------------------------------------------------------------------
# 7. Live path: separate ticks stay separate batches; the hand-off field set.
# ---------------------------------------------------------------------------
func live_distinct_ticks_and_handoff() -> void:
    print("--- part 7: distinct ticks + hand-off ---")
    var before: Array = vs.host_ids(self)
    var arena := await launch_arena([["ggb", "human"], ["teknium", "bot"], ["ggb", "bot"], ["", "empty"]])
    check(arena != null, "the three-player FFA launches")
    if arena == null:
        return
    # Duplicate-fighter palette variants, cross-checked against the live bodies
    # the players actually saw.
    check(arena.fighters[0].body_color == roster.palette("ggb", 0), "P1 renders the first GGB variant")
    check(arena.fighters[2].body_color == roster.palette("ggb", 1), "P3 renders the duplicate GGB variant")
    # Tick 1: P1 out (not decisive).
    arena.fighters[0].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[0])
    check(not arena.match_over, "the FFA continues with two survivors")
    await frames(2)
    # Tick 2: P3 out -> decisive, in a batch of its own.
    arena.fighters[2].stocks = 0
    arena._on_fighter_eliminated(arena.fighters[2])
    check(arena.match_over, "the last elimination resolves the match")
    var host = await vs.wait_for_new_host(self, before)
    check(host != null, "the resolved match hands its payload to the PostMatch surface")
    if host != null:
        var result = host.post_match_result()
        check(result != null, "the payload carries the immutable MatchResult")
        if result != null:
            check(str(result.outcome) == "WIN" and not bool(result.team_mode), "the FFA payload is a WIN in FFA mode")
            check(int(result.entry_for_player(1)["elimination_batch"]) == 0, "the first tick is batch 0")
            check(int(result.entry_for_player(3)["elimination_batch"]) == 1, "the second tick is batch 1")
            check(int(result.entry_for_player(2)["placement"]) == 1, "the survivor is 1ST")
            check(int(result.entry_for_player(3)["placement"]) == 2, "the later elimination is 2ND")
            check(int(result.entry_for_player(1)["placement"]) == 3, "the earlier elimination is 3RD")
            var complete := true
            for entry in result.entries:
                for field in FIELDS:
                    if not entry.has(field):
                        complete = false
                if int(entry["palette_index"]) == 1 and str(entry["fighter_id"]) == "ggb":
                    check(int(entry["stocks_remaining"]) == 0, "the duplicate-variant entry snapshots its own stocks")
            check(complete, "every handed-over entry carries the full field set")
            var seen := {}
            for entry in result.entries:
                seen[int(entry["player_index"])] = int(entry["palette_index"])
            check(int(seen[1]) == 0 and int(seen[3]) == 1, "the hand-off resolves the duplicate variants")
            if is_instance_valid(arena):
                # The resolved variant is the body the players actually saw.
                var matches := true
                for entry in result.entries:
                    if roster.palette(str(entry["fighter_id"]), int(entry["palette_index"])) != arena_body_color(entry, arena):
                        matches = false
                check(matches, "every entry's resolved palette variant matches the live body color")
    await teardown()

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
func launch_arena(specs: Array) -> Node:
    # Direct debug-route start (the same arena the shipped debug launcher builds):
    # the resolution data path under test is the arena's own end path.
    var slots: Array = []
    for i in specs.size():
        slots.append({"kind": str(specs[i][1]), "character": str(specs[i][0]),
            "team": i % 2, "difficulty": "normal", "device": -1})
    var arena = (load("res://scenes/main.tscn") as PackedScene).instantiate()
    root.add_child(arena)
    await process_frame
    if not arena.start_match(slots, false):
        check(false, "the arena accepts the station configuration")
        arena.queue_free()
        await process_frame
        return null
    for f in arena.fighters:
        f.set_physics_process(false)
    return arena

func teardown() -> void:
    await vs.free_hosts(self)
    await vs.free_arenas(self)
    for child in root.get_children():
        if child.has_method("entry_mode") or (child is Node3D and str(child.name).begins_with("MainArena")):
            child.queue_free()
    await frames(2)
