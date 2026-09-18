class_name MatchResult
extends RefCounted
# MatchResult — the explicit, IMMUTABLE match-result snapshot (Doc 06 §4).
#
# Owned by the MATCH LAYER: built at match resolution, before any reset/rematch
# mutation, and handed to Results as plain data. Every value is copied out of the
# live fighters here, so no later mutation of a fighter (reset, rematch, teardown)
# can change the snapshot, and no Results/Story surface ever asks a live fighter
# to infer placement (Doc 06 §4 "Results does not derive match truth").
#
# TIE RULE (Doc 06 §2, verbatim example):
#   batch 0: P3 + P4 eliminated together
#   batch 1: P2 eliminated
#   P1 survives
#   -> P1 1ST, P2 2ND, P3 3RD, P4 3RD
#   "Do not invent unique placement via player index for a real simultaneous
#    elimination."
#   "Final batch removes every survivor: DRAW."
# The rule implemented here is standard competition ranking over the batch
# sequence: placement = 1 + (number of entries that survived LONGER), where
# "longer" means surviving at all, or a strictly LATER elimination_batch. That
# reproduces the doc's worked example exactly (P3/P4 share 3RD, not 2ND/3RD) and
# keeps placements deterministic with no invented ordering: entries in the same
# batch always share a rank, and the tie group is never broken by player index.
# A DRAW is the doc's final-batch case: when the deciding batch removes every
# survivor the outcome is DRAW and every member of that batch shares 1ST.
#
# TEAM RANKING (Doc 06 §3, Doc 01 §3/§12): the player-facing outcome is
# TEAM-ranked. Teams are ranked by survival (a team with a survivor outranks a
# team with none, otherwise the team whose members lasted to a later batch
# outranks) and members SHARE their team's rank: `placement` and `team_placement`
# carry the same shared team rank, so winning teammates are never ranked against
# each other. `is_winner` marks EVERY member of the winning team, including a
# member eliminated before match end (Doc 06 §3: they are part of the hero
# identity). In FFA every player is its own group, so team_placement mirrors
# placement and team_id stays NO_TEAM.
#
# Field set (Doc 06 §4 / Doc 02 §4), one entry per participating station:
#   player_index, fighter_id, fighter_name, palette_index (resolved presentation
#   variant), team_id, stocks_remaining, damage_percent, eliminated,
#   elimination_batch, placement, team_placement, is_winner.
# `damage_percent` is the value at resolution: the game rule resets a fighter's
# damage when it loses its last stock, so an eliminated entry carries 0 and
# Results shows `OUT` with no damage field instead (Doc 06 §4 — never display
# meaningless reset/current damage).
#
# Batch input: a list of batches, each an array of player_index, in observation
# order; batch identity is the index in that list. A FLAT array of player_index
# is also accepted (historical shape): with no tick to share, every element is
# its own batch, which is exactly what separately observed, non-simultaneous
# eliminations are.
#
# Sentinels: winning_team == NO_TEAM (-1) for FFA and draws;
# elimination_batch == NO_BATCH (-1) only for an elimination nobody observed and
# no resolution folded in (defensive/fixture paths) — it ranks below every real
# batch and ties with the other unobserved entries instead of inventing an order.

const OUTCOME_WIN := "WIN"
const OUTCOME_DRAW := "DRAW"
const NO_TEAM := -1
const NO_BATCH := -1
const NO_PLACEMENT := 0

# Own path: factories construct through the resource path so this script never
# depends on its own class_name being registered in the global class cache
# before it can build a result (headless test runs do not re-scan the project).
const SELF_PATH := "res://scripts/match_result.gd"

var outcome := OUTCOME_WIN
var team_mode := false
var winning_team := NO_TEAM
var entries: Array = []

# --- building ---------------------------------------------------------------

static func _blank() -> RefCounted:
    return (load(SELF_PATH) as GDScript).new()

static func resolve(fighters: Array, teams_enabled: bool, elimination_batches: Array) -> RefCounted:
    # `fighters` are the live match fighters at resolution time; every value is
    # copied out here, so later reset/rematch mutation cannot change the
    # snapshot.
    var result := _blank()
    result.team_mode = teams_enabled
    result.entries = _snapshot_entries(fighters, _batch_map(_normalize_batches(elimination_batches)))
    _rank(result.entries, teams_enabled, result)
    return result

static func from_entries(new_outcome: String, new_team_mode: bool, new_winning_team: int, new_entries: Array) -> RefCounted:
    # Explicit construction (tests, offline fixtures, evidence tooling): the
    # caller owns every field, including rank. No inference happens here either,
    # and keys the caller added that are not part of the field set are kept
    # as-is (the legacy `elimination_order` fixture key is simply ignored).
    var result := _blank()
    result.outcome = new_outcome
    result.team_mode = new_team_mode
    result.winning_team = new_winning_team
    for raw in new_entries:
        var entry: Dictionary = raw.duplicate(true)
        entry["player_index"] = int(entry.get("player_index", 0))
        entry["fighter_id"] = str(entry.get("fighter_id", ""))
        entry["fighter_name"] = str(entry.get("fighter_name", ""))
        entry["palette_index"] = int(entry.get("palette_index", 0))
        entry["team_id"] = int(entry.get("team_id", NO_TEAM))
        entry["stocks_remaining"] = int(entry.get("stocks_remaining", 0))
        entry["damage_percent"] = int(entry.get("damage_percent", 0))
        entry["eliminated"] = bool(entry.get("eliminated", int(entry["stocks_remaining"]) <= 0))
        entry["elimination_batch"] = int(entry.get("elimination_batch", NO_BATCH))
        entry["placement"] = int(entry.get("placement", NO_PLACEMENT))
        entry["team_placement"] = int(entry.get("team_placement", int(entry["placement"])))
        entry["is_winner"] = bool(entry.get("is_winner", false))
        result.entries.append(entry)
    return result

static func _normalize_batches(source: Array) -> Array:
    var out: Array = []
    for raw in source:
        if raw is Array:
            var batch: Array = []
            for value in raw:
                batch.append(int(value))
            out.append(batch)
        else:
            out.append([int(raw)])
    return out

static func _batch_map(batches: Array) -> Dictionary:
    # player_index -> batch index. The FIRST observation wins: one elimination
    # belongs to exactly one batch, whichever tick observed it first.
    var out: Dictionary = {}
    for index in batches.size():
        for value in batches[index]:
            var player_index := int(value)
            if not out.has(player_index):
                out[player_index] = index
    return out

static func _snapshot_entries(fighters: Array, batch_of: Dictionary) -> Array:
    var entries: Array = []
    for fighter in fighters:
        var player_index := int(fighter.player_index)
        var stocks := int(fighter.stocks)
        entries.append({
            "player_index": player_index,
            "fighter_id": str(fighter.character_id),
            "fighter_name": str(fighter.fighter_name),
            "palette_index": 0,
            "team_id": int(fighter.team_id),
            "stocks_remaining": stocks,
            "damage_percent": roundi(float(fighter.damage_percent)),
            "eliminated": stocks <= 0,
            "elimination_batch": int(batch_of.get(player_index, NO_BATCH)),
            "placement": NO_PLACEMENT,
            "team_placement": NO_PLACEMENT,
            "is_winner": false,
        })
    # Player order first: it is the station order the palette variants are
    # resolved in, and it makes the snapshot deterministic for any caller order.
    entries.sort_custom(func(a, b): return int(a["player_index"]) < int(b["player_index"]))
    _assign_palette_variants(entries)
    return entries

static func _assign_palette_variants(entries: Array) -> void:
    # Resolved presentation variant, derived from the ONE rule the CSS, the
    # launch snapshot and match start already share (MatchFlowState
    # .resolve_palette_variant / main.gd palette_counts): the occurrence count of
    # this fighter among the participating stations BEFORE it, in station order.
    # First occurrence keeps variant 0, each duplicate gets the next one, so a
    # Result row can never disagree with what the player saw.
    var variants: Dictionary = {}
    for entry in entries:
        var fighter_id := str(entry["fighter_id"])
        var variant := int(variants.get(fighter_id, 0))
        entry["palette_index"] = variant
        variants[fighter_id] = variant + 1

static func _rank(entries: Array, teams_enabled: bool, result: RefCounted) -> void:
    var survivors := 0
    for entry in entries:
        if not bool(entry["eliminated"]):
            survivors += 1
    result.outcome = OUTCOME_WIN if survivors > 0 else OUTCOME_DRAW
    if teams_enabled:
        _rank_teams(entries)
    else:
        for entry in entries:
            entry["placement"] = _rank_of(entry, entries)
            entry["team_placement"] = int(entry["placement"])
    entries.sort_custom(_standings_order)
    if result.outcome != OUTCOME_WIN:
        return
    if teams_enabled:
        _crown_winning_team(entries, result)
    for entry in entries:
        if teams_enabled:
            # Every member of the winning team, eliminated or not (Doc 06 §3).
            entry["is_winner"] = result.winning_team != NO_TEAM and int(entry["team_id"]) == int(result.winning_team)
        else:
            # The survivor(s) of a WIN. Co-survivors share 1ST (batches decide,
            # player index never does), and on a DRAW nobody is a winner.
            entry["is_winner"] = not bool(entry["eliminated"]) and int(entry["placement"]) == 1

static func _ranks_better(a: Dictionary, b: Dictionary) -> bool:
    # a ranks STRICTLY better than b. Survival first, then the elimination batch
    # (a later batch = a better placement), and never a tie-breaker by player
    # index: two entries the match could not separate share their rank.
    var a_out := bool(a["eliminated"])
    var b_out := bool(b["eliminated"])
    if a_out != b_out:
        return not a_out
    if a_out:
        return int(a["elimination_batch"]) > int(b["elimination_batch"])
    return false

static func _rank_of(entry: Dictionary, entries: Array) -> int:
    # Competition ranking: 1 + the entries that survived longer, so a batch of
    # simultaneous eliminations shares the best rank of the group (Doc 06 §2).
    var better := 0
    for other in entries:
        if int(other["player_index"]) == int(entry["player_index"]):
            continue
        if _ranks_better(other, entry):
            better += 1
    return better + 1

static func _team_ranks_better(a: Dictionary, b: Dictionary) -> bool:
    var a_survives := bool(a["survives"])
    var b_survives := bool(b["survives"])
    if a_survives != b_survives:
        return a_survives
    return int(a["best_batch"]) > int(b["best_batch"])

static func _rank_teams(entries: Array) -> void:
    # Team mode is TEAM-ranked: a team's rank is the rank of its whole group, so
    # members share it (Doc 06 §3). `best_batch` is the latest batch any of its
    # members was eliminated in: the team that lasted longer ranks higher.
    var teams: Dictionary = {}
    var order: Array = []
    for entry in entries:
        var team_id := int(entry["team_id"])
        if not teams.has(team_id):
            order.append(team_id)
            teams[team_id] = {"survives": false, "best_batch": NO_BATCH}
        var record: Dictionary = teams[team_id]
        if bool(entry["eliminated"]):
            record["best_batch"] = maxi(int(record["best_batch"]), int(entry["elimination_batch"]))
        else:
            record["survives"] = true
    for team_id in order:
        var better := 0
        for other in order:
            if other == team_id:
                continue
            if _team_ranks_better(teams[other], teams[team_id]):
                better += 1
        var place := better + 1
        for entry in entries:
            if int(entry["team_id"]) == team_id:
                entry["placement"] = place
                entry["team_placement"] = place

static func _crown_winning_team(entries: Array, result: RefCounted) -> void:
    result.winning_team = NO_TEAM
    for entry in entries:
        if int(entry["team_placement"]) == 1:
            result.winning_team = int(entry["team_id"])
            return

static func _standings_order(a: Dictionary, b: Dictionary) -> bool:
    # Deterministic standings order: rank first, then player order inside a
    # shared rank. A tie group is only ever ORDERED (never re-ranked).
    if int(a["placement"]) != int(b["placement"]):
        return int(a["placement"]) < int(b["placement"])
    return int(a["player_index"]) < int(b["player_index"])

# --- reads -----------------------------------------------------------------

func entry_for_player(player_index: int) -> Dictionary:
    for entry in entries:
        if int(entry["player_index"]) == player_index:
            return entry
    return {}

func winner_entry() -> Dictionary:
    # The FFA winner (team results use `winning_entries`). Empty on a draw.
    if team_mode or outcome != OUTCOME_WIN:
        return {}
    for entry in entries:
        if bool(entry["is_winner"]):
            return entry
    return {}

func winning_entries() -> Array:
    # The hero group. FFA: the survivor. Team mode: EVERY member of the winning
    # team — a teammate eliminated before match end is still part of the hero
    # identity (Doc 06 §3/§7), so no member is dropped for being OUT.
    var out: Array = []
    for entry in entries:
        if bool(entry["is_winner"]):
            out.append(entry)
    return out

func team_standings() -> Array:
    # Rank-ordered team groups for the team view (Doc 01 §12 "1ST · TEAM A /
    # member rows"): [{team_id, placement, entries}] with the members in
    # standings order. FFA never needs it — there every player is its own group.
    var out: Array = []
    for entry in entries:
        var team_id := int(entry["team_id"])
        var group: Dictionary = {}
        var found := false
        for existing in out:
            if int(existing["team_id"]) == team_id:
                group = existing
                found = true
                break
        if not found:
            group = {"team_id": team_id, "placement": int(entry["team_placement"]), "entries": []}
            out.append(group)
        group["entries"].append(entry)
    out.sort_custom(func(a, b):
        if int(a["placement"]) != int(b["placement"]):
            return int(a["placement"]) < int(b["placement"])
        return int(a["entries"][0]["player_index"]) < int(b["entries"][0]["player_index"]))
    return out
