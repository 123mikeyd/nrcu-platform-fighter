extends RefCounted
## One arbitration point: status > action > locomotion.
const LOCOMOTION := ["idle", "walk", "initial_dash", "run", "brake", "turn", "jump_startup", "rising", "falling", "fast_fall", "landing"]
const GROUND := ["idle", "walk", "initial_dash", "run", "brake", "turn"]
const AIR := ["rising", "falling", "fast_fall"]
const ACTION := ["neutral", "movement_lock", "landing_lock"]
const STATUS := ["normal", "disabled", "hitstun", "caught", "frozen"]
var locomotion: String = "idle"
var action: String = "neutral"
var status: String = "normal"
var transition_reason: String = "reset"
var trace: Array[Dictionary] = []
func reset() -> void:
	locomotion = "idle"
	action = "neutral"
	status = "normal"
	transition_reason = "reset"
	trace.clear()
func transition(layer: String, target: String, reason: String) -> bool:
	var legal: Array = LOCOMOTION if layer == "locomotion" else ACTION if layer == "action" else STATUS if layer == "status" else []
	if target not in legal: return false
	if layer != "status" and status != "normal": return false
	if layer == "action" and action == "landing_lock" and target == "movement_lock": return false
	var previous: String = get(layer)
	if previous == target: return true
	if layer == "locomotion":
		var allowed := false
		if previous in GROUND: allowed = target in GROUND or target in ["jump_startup", "falling"]
		elif previous == "jump_startup": allowed = target in ["rising", "falling"]
		elif previous in AIR: allowed = target in AIR or target == "landing"
		elif previous == "landing": allowed = target in GROUND or target in ["jump_startup", "falling"]
		if not allowed: return false
	set(layer, target)
	transition_reason = reason
	trace.append({"layer": layer, "from": previous, "to": target, "reason": reason})
	if trace.size() > 32: trace.pop_front()
	return true
func movement_allowed() -> bool:
	return status == "normal" and action == "neutral"
