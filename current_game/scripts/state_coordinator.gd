extends RefCounted
## Adapted from Quarker 09970e27 scripts/core/fighter/state_coordinator.gd.
## Arbitration only: never owns clocks, input edges, velocity, resources or poses.
## Current v3 self-cast restraint precedes hitstun; retain that ordering explicitly.
const LOCOMOTION := ["idle", "run", "rising", "falling"]
const ACTION := ["neutral", "movement_lock", "landing_lock"]
const STATUS := ["normal", "disabled", "hitstun", "casting", "caught", "frozen"]
var locomotion := "idle"
var action := "neutral"
var status := "normal"
var transition_reason := "reset"
var trace: Array[Dictionary] = []
var action_owner := "input"
var scripted_axis := false

func reset() -> void:
    locomotion = "idle"
    action = "neutral"
    status = "normal"
    action_owner = "input"
    scripted_axis = false
    transition_reason = "reset"
    trace.clear()

func transition(layer: String, target: String, reason: String) -> bool:
    var legal: Array = LOCOMOTION if layer == "locomotion" else ACTION if layer == "action" else STATUS if layer == "status" else []
    if target not in legal: return false
    if layer != "status" and status != "normal": return false
    if layer == "action" and action == "landing_lock" and target == "movement_lock": return false
    var previous: String = get(layer)
    if previous == target: return true
    # v3 has instantaneous jumps/launches and no dash/startup/landing state clock.
    # Every observed contact/velocity transition among these four states is legal.
    set(layer, target)
    transition_reason = reason
    trace.append({"layer": layer, "from": previous, "to": target, "reason": reason})
    if trace.size() > 32: trace.pop_front()
    return true

func reconcile(actor) -> void:
    var next_status := "normal"
    if not actor.controls_enabled: next_status = "disabled"
    elif actor.freeze_remaining > 0: next_status = "frozen"
    elif is_instance_valid(actor.caught_by): next_status = "caught"
    elif actor.teknium_magic and actor.teknium_magic.phase != "idle": next_status = "casting"
    elif actor.hitstun > 0: next_status = "hitstun"
    transition("status", next_status, "current v3 control priority")
    if status != "normal": return
    action_owner = "counter" if actor.doge_counter and actor.doge_counter.phase != "idle" else "special" if actor.teknium_specials and actor.teknium_specials.phase != "idle" else "input"
    if actor.ggb_combat_review and actor.ggb_combat_review.committed(): action_owner = "special"
    if actor.air_doge and actor.air_doge.active(): action_owner = "special"
    scripted_axis = (actor.mephisto_moves != null and not actor.mephisto_moves.move.is_empty()) or (actor.doge_ground_rush != null and actor.doge_ground_rush.phase != "idle")
    var next_action := "landing_lock" if actor.landing_lag > 0 else "movement_lock" if actor.charging or actor.shielding or scripted_axis or action_owner != "input" else "neutral"
    # Explicit release reconciles an expired landing lock before a new action.
    if action != next_action: transition("action", "neutral", "reconcile release")
    transition("action", next_action, "current v3 action ownership")
    var next_motion := "rising" if actor.velocity.y > 0 else "falling"
    if actor.is_grounded() and actor.velocity.y <= 0:
        next_motion = "run" if not is_zero_approx(actor.velocity.x) else "idle"
    transition("locomotion", next_motion, "current contact and velocity")

func control_lane() -> String:
    return status if status != "normal" else action_owner

func movement_allowed() -> bool:
    return status == "normal" and action == "neutral"

func intent_axis(axis: float) -> float:
    return 0.0 if scripted_axis else axis
