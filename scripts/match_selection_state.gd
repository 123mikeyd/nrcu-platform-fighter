extends RefCounted
# Persistent VS selection state: the frontend (Character Select -> Stage
# Select) accumulates player slots, kinds, fighters, teams, bot difficulty,
# devices and the stage; only the final stage confirmation adapts this state
# into the existing start_match(slots, teams) backend call.
#
# This object is the SCREEN-FACING MIRROR the CSS/SSS edit. It holds NO rule of
# its own (Doc 02 §2 "Ready and actual launch must call the same validation
# authority"): validation_error() and resolved_palette() delegate to the typed
# MatchFlowState authority, so the screen can never disagree with the launch
# gate. Legacy can_ready() is kept for the pre-authority callers/tests only and
# is never the player-facing gate.

const Config = preload("res://scripts/match_config.gd")
const AUTHORITY_PATH := "res://scripts/match_flow_state.gd"

var mode := 0        # 0 = free-for-all, 1 = teams
var stage := "debug"
var slots: Array = []
# Device availability injected by the screen (Doc 03 §10 hotplug refresh): the
# authority must validate against the SAME pad list the bays display. Empty =
# no pads, which is the headless/desktop-keyboard case.
var connected_pads: Array = []

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
    # Legacy pre-authority rule, pinned by tests but NOT the player-facing gate
    # (Doc 01 §2/§3 supersede it: >= 2 active and >= 1 Human in VS, and a 1v1
    # Team A vs Team B match is valid). Use validation_error() for gating.
    if mode == 1:
        return active_count() >= 3 and teams_ok()
    return active_count() >= 2

func set_stage(id: String) -> void:
    stage = id

func to_slots() -> Array:
    return slots.duplicate(true)

# --- device availability ----------------------------------------------------

func set_connected_pads(pads: Array) -> void:
    connected_pads = pads.duplicate()

# --- the ONE validation authority (Doc 02 §2) --------------------------------

func authority():
    # Delegating adapter: this mirror is hydrated into the typed MatchFlowState
    # and validated by it. Lazy load (never a preload) because the authority
    # preloads this script for its own adapters.
    var State = load(AUTHORITY_PATH)
    var flow = State.from_selection_state(self)
    flow.set_connected_pads(connected_pads)
    return flow

func validation_error() -> String:
    # "" = the state may proceed; otherwise ONE player-facing message. This is
    # the same rule set the launch gate runs (MatchFlowState.validate_for_*).
    return str(authority().validate_for_stage_select())

func resolved_palette(slot_index: int) -> int:
    # Doc 04 §14: the resolved duplicate-fighter variant, resolved in
    # MatchFlowState (never re-implemented here or in a screen).
    var ids: Array = []
    for i in slots.size():
        var slot: Dictionary = slots[i]
        var active: bool = str(slot.get("kind", "empty")) != "empty"
        ids.append(str(slot.get("character", "")) if active else "")
    return int(load(AUTHORITY_PATH).resolve_palette_variant(ids, slot_index))
