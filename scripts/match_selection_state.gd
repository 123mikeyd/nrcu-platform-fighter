extends RefCounted
# Persistent VS selection state: the frontend (Character Select -> Stage
# Select) accumulates player slots, kinds, fighters, teams, bot difficulty,
# devices and the stage; only the final stage confirmation adapts this state
# into the existing start_match(slots, teams) backend call.

const Config = preload("res://scripts/match_config.gd")

var mode := 0        # 0 = free-for-all, 1 = teams
var stage := "debug"
var slots: Array = []

func _init() -> void:
    slots = Config.default_slots()

func active_count() -> int:
    var n := 0
    for slot in slots:
        if slot.get("kind", "empty") != "empty":
            n += 1
    return n

func teams_ok() -> bool:
    var sides: Array = []
    for slot in slots:
        if slot.get("kind", "empty") == "empty":
            continue
        if slot.get("team", -1) not in sides:
            sides.append(slot.get("team", -1))
    return sides.size() >= 2

func can_ready() -> bool:
    # Mirrors match_config.validate: two fighters in FFA, three plus both
    # teams represented in team mode.
    if mode == 1:
        return active_count() >= 3 and teams_ok()
    return active_count() >= 2

func set_stage(id: String) -> void:
    stage = id

func to_slots() -> Array:
    return slots.duplicate(true)
