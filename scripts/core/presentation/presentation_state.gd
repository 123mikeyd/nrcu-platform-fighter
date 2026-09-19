extends RefCounted
## Detached committed telemetry -> pose request. No node, input or wall clock.
const DT := 1.0 / 60.0
const MAP := {"idle": "Idle", "walk": "Walk", "run": "Run", "initial_dash": "Run", "turn": "Walk", "brake": "Walk", "jump_startup": "Jump", "rising": "Jump", "falling": "Jump", "fast_fall": "Jump", "landing": "Jump"}
const LAND_SECONDS := 0.1
var last_tick := -1
var seconds := 0.0
var clip := ""
var previous_locomotion := ""
var previous_jumps := -1
var land_left := 0.0
var output: Dictionary = {}
var blend_elapsed := 0.06
var blend_seconds := 0.06
var transition := 0
var previous_strike := ""
var previous_recovery := ""
var previous_hit = null
func reset() -> void:
    last_tick = -1
    seconds = 0.0
    clip = ""
    previous_locomotion = ""
    previous_jumps = -1
    land_left = 0.0
    output = {}
    blend_elapsed = 0.06
    transition = 0
    previous_hit = null
    previous_strike = ""
    previous_recovery = ""
func sample(snapshot: Dictionary, tick: int) -> Dictionary:
    if tick == last_tick: return output.duplicate(true)
    if tick < last_tick: reset()
    var elapsed := maxi(0, tick - last_tick) * DT if last_tick >= 0 else 0.0
    if not output.is_empty() and (snapshot.get("frozen", false) or snapshot.get("hitstop", false) or snapshot.get("status", "") == "frozen"):
        last_tick = tick
        return output.duplicate(true)
    var locomotion := str(snapshot.get("locomotion", "idle"))
    var jumps := int(snapshot.get("air_jumps_left", previous_jumps))
    var new_jump := (locomotion == "jump_startup" and previous_locomotion != locomotion) or (locomotion == "rising" and (previous_locomotion not in ["rising", "jump_startup"] or (jumps < previous_jumps and jumps >= 0)))
    if locomotion == "landing" and previous_locomotion != "landing": land_left = LAND_SECONDS
    else: land_left = maxf(0.0, land_left - elapsed)
    if locomotion not in ["landing", "idle"]: land_left = 0.0
    var selected_state := locomotion
    if land_left > 0: selected_state = "landing"
    elif locomotion == "landing": selected_state = "idle"
    var selected: String = MAP.get(selected_state, "Idle")
    var hit = snapshot.get("hit_id", null)
    var recovery := str(snapshot.get("recovery_id", ""))
    if snapshot.get("status", "") == "hitstun" or snapshot.get("hit", false):
        selected_state = "hit"
        selected = "Hit"
    elif not recovery.is_empty():
        selected_state = "recovery"
        selected = "RaiseWall"
    elif snapshot.get("action", "") in ["movement_lock", "block"]:
        selected_state = "block"
        selected = "Block"
    elif snapshot.get("action", "") == "recovery":
        selected_state = "recovery"
        selected = "Jump"
    # Optional committed activation identity; absent in all P3 callers.
    var strike := str(snapshot.get("strike_id", ""))
    if not strike.is_empty() and selected_state not in ["hit", "block", "recovery"]:
        selected_state = "strike"
        selected = "Kick" if snapshot.get("strike_move", "") in ["LOW SWEEP", "DOWN STRIKE"] else "Punch"
    var force := str(snapshot.get("force_id", ""))
    if not force.is_empty() and selected_state != "hit" and recovery.is_empty():
        selected_state = "force"
        selected = "ForcePush"
    var restart: bool = (selected_state == "strike" and strike != previous_strike) or (new_jump and selected_state in ["jump_startup", "rising"]) or (selected == "Hit" and hit != previous_hit)
    restart = restart or (selected == "RaiseWall" and recovery != previous_recovery)
    var changed: bool = output.get("state", "") != selected_state or restart
    if changed:
        transition += 1
        blend_seconds = 0.03 if selected_state == "hit" else 0.06
        if selected_state in ["jump_startup", "rising"] and (new_jump or previous_locomotion == "jump_startup"): blend_seconds = 0.0
        blend_elapsed = 0.0 if not output.is_empty() else 0.06
    else: blend_elapsed += elapsed
    seconds = seconds + elapsed if selected == clip and not restart else 0.0
    if selected == "ForcePush":
        seconds = float(snapshot.get("force_source_time", 0.0))
        blend_seconds = 0.0 # Exact authored magic pose, never locomotion floor blending.
    previous_strike = strike
    previous_recovery = recovery
    previous_hit = hit
    clip = selected
    var fraction := -1.0
    var strike_offset := 0.0
    if selected_state == "strike" and snapshot.get("strike_move", "") in ["UPPERCUT", "UP AIR", "LOW SWEEP", "DOWN STRIKE"]:
        seconds = maxf(0.0, float(snapshot.get("strike_elapsed", 0.0)))
        fraction = clampf(seconds / 0.32, 0.0, 1.0)
        strike_offset = -0.038 if selected == "Kick" else -0.106
    var cap := 1.0
    var fallback := ""
    match selected_state:
        "rising":
            cap = 0.65
            fallback = "TEMP: rise holds Jump 65% if source outruns ascent"
        "falling", "fast_fall":
            fraction = 1.0
            fallback = "TEMP: fall holds approved Jump endpoint"
        "landing":
            fraction = 0.0
            fallback = "TEMP: landing holds Jump opening pose for 0.10s"
        "turn", "brake": fallback = "TEMP: Walk substitutes for turn/brake"
        "recovery":
            if selected == "RaiseWall":
                # Legacy sync_pose scales the WHOLE RaiseWall to .65s, not
                # its .38s gameplay contact window. Seek the imported source.
                seconds = maxf(0.0, float(snapshot.get("recovery_elapsed", 0.0)))
                fraction = clampf(seconds / 0.65, 0.0, 1.0)
            else:
                fraction = 0.65
                fallback = "TEMP: recovery holds Jump 65%; no committed recovery identity"
    last_tick = tick
    previous_locomotion = locomotion
    previous_jumps = jumps
    output = {"strike_offset": strike_offset, "transition": transition, "blend": clampf(blend_elapsed / blend_seconds, 0.0, 1.0) if blend_seconds > 0 else 1.0, "clip": clip, "state": selected_state, "seconds": seconds, "fraction": fraction, "cap": cap, "loop": clip in ["Idle", "Walk", "Run", "Block"], "fallback": fallback}
    return output.duplicate(true)
