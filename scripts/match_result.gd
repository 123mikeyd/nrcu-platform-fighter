class_name MatchResult
extends RefCounted
# MatchResult — the explicit, immutable match-result snapshot (Doc 06 §3).
#
# Owned by the MATCH LAYER: built at match resolution, before any
# reset/rematch mutation, and handed to Results as plain data. Results sorts
# and displays `placement` — it never infers ranking from stocks/damage and
# never resolves a fighter model from its display name.
#
# Placement policy lives HERE, not in Results (Doc 06 §4):
#   survivors first (player_index order), then eliminated players by
#   elimination order — later elimination = better placement, so
#   [1ST survivor, 2ND last eliminated, 3RD previous, 4TH first eliminated].
#   Eliminations nobody observed (test fixtures / defensive paths) rank below
#   every observed one and are ordered by player_index: a deterministic tie
#   policy owned by match resolution, never invented by the screen.
# Team mode (Doc 06 §5): the outcome names the winning TEAM; every member of
# that team carries is_winner, while placements stay individual.
#
# Sentinels: winning_team == NO_TEAM (-1) for FFA and draws;
# elimination_order == NO_ORDER (-1) for unobserved eliminations (doc: null).

const OUTCOME_WIN := "WIN"
const OUTCOME_DRAW := "DRAW"
const NO_TEAM := -1
const NO_ORDER := -1

# Own path: factories construct through the resource path so this script never
# depends on its own class_name being registered in the global class cache
# before it can build a result (headless test runs do not re-scan the project).
const SELF_PATH := "res://scripts/match_result.gd"

var outcome := OUTCOME_WIN
var team_mode := false
var winning_team := NO_TEAM
var entries: Array = []

# --- building --------------------------------------------------------------

static func _blank() -> RefCounted:
    return (load(SELF_PATH) as GDScript).new()

static func resolve(fighters: Array, teams_enabled: bool, elimination_order: Array) -> RefCounted:
    # `fighters` are the live match fighters at resolution time; every value is
    # copied out here, so later reset/rematch mutation cannot change the
    # snapshot. `elimination_order` lists player_index values in the order the
    # match observed eliminations.
    var observed: Dictionary = {}
    for i in elimination_order.size():
        observed[int(elimination_order[i])] = i
    var survivors: Array = []
    var eliminated: Array = []
    for fighter in fighters:
        var stocks := int(fighter.stocks)
        var entry := {
            "player_index": int(fighter.player_index),
            "fighter_id": str(fighter.character_id),
            "fighter_name": str(fighter.fighter_name),
            "team_id": int(fighter.team_id),
            "placement": 0,
            "stocks_remaining": stocks,
            "damage_percent": roundi(float(fighter.damage_percent)),
            "eliminated": stocks <= 0,
            "elimination_order": int(observed.get(int(fighter.player_index), NO_ORDER)),
            "is_winner": false,
        }
        if stocks > 0:
            survivors.append(entry)
        else:
            eliminated.append(entry)
    survivors.sort_custom(func(a, b): return int(a["player_index"]) < int(b["player_index"]))
    eliminated.sort_custom(_eliminated_ranks_higher)
    var result := _blank()
    result.team_mode = teams_enabled
    result.outcome = OUTCOME_WIN if not survivors.is_empty() else OUTCOME_DRAW
    if result.outcome == OUTCOME_WIN and teams_enabled:
        result.winning_team = int(survivors[0]["team_id"])
    var place := 1
    for entry in survivors:
        entry["placement"] = place
        place += 1
    for entry in eliminated:
        entry["placement"] = place
        place += 1
    for entry in survivors:
        if teams_enabled:
            entry["is_winner"] = result.winning_team != NO_TEAM and int(entry["team_id"]) == result.winning_team
        else:
            entry["is_winner"] = int(entry["placement"]) == 1
    for entry in eliminated:
        entry["is_winner"] = teams_enabled and result.winning_team != NO_TEAM and int(entry["team_id"]) == result.winning_team
    result.entries = survivors + eliminated
    return result

static func from_entries(new_outcome: String, new_team_mode: bool, new_winning_team: int, new_entries: Array) -> RefCounted:
    # Explicit construction (tests, offline fixtures): the caller owns every
    # field, including placement. No inference happens here either.
    var result := _blank()
    result.outcome = new_outcome
    result.team_mode = new_team_mode
    result.winning_team = new_winning_team
    for raw in new_entries:
        var entry: Dictionary = raw.duplicate(true)
        entry["player_index"] = int(entry.get("player_index", 0))
        entry["fighter_id"] = str(entry.get("fighter_id", ""))
        entry["fighter_name"] = str(entry.get("fighter_name", ""))
        entry["team_id"] = int(entry.get("team_id", NO_TEAM))
        entry["placement"] = int(entry.get("placement", 0))
        entry["stocks_remaining"] = int(entry.get("stocks_remaining", 0))
        entry["damage_percent"] = int(entry.get("damage_percent", 0))
        entry["eliminated"] = bool(entry.get("eliminated", int(entry["stocks_remaining"]) <= 0))
        entry["elimination_order"] = int(entry.get("elimination_order", NO_ORDER))
        entry["is_winner"] = bool(entry.get("is_winner", false))
        result.entries.append(entry)
    return result

static func _eliminated_ranks_higher(a: Dictionary, b: Dictionary) -> bool:
    var oa: int = int(a["elimination_order"])
    var ob: int = int(b["elimination_order"])
    if (oa == NO_ORDER) != (ob == NO_ORDER):
        return oa != NO_ORDER          # observed eliminations rank above unobserved
    if oa != ob:
        return oa > ob                 # later elimination = better placement
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
    # FFA: the survivor. Team mode: the winning team's standing members, or
    # every member of the winning team when none of them survived.
    var standing: Array = []
    var members: Array = []
    for entry in entries:
        if not bool(entry["is_winner"]):
            continue
        members.append(entry)
        if not bool(entry["eliminated"]):
            standing.append(entry)
    return standing if not standing.is_empty() else members
