extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        print("FAIL: ", message)
func _init() -> void:
    call_deferred("run")
func run() -> void:
    var path := "res://scripts/core/presentation/presentation_state.gd"
    check(ResourceLoader.exists(path), "pure presentation decision seam exists")
    if failures:
        quit(1)
        return
    var state = load(path).new()
    var pose: Dictionary = state.sample({"locomotion": "walk", "grounded": true}, 0)
    check(pose.clip == "Walk", "explicit walk state chooses Walk")
    pose = state.sample({"locomotion": "walk", "grounded": true}, 1)
    check(is_equal_approx(pose.seconds, 1.0 / 60), "same state advances source clock without restart")
    check(state.sample({"locomotion": "walk"}, 1) == pose, "duplicate committed tick is idempotent")
    for pair in [["idle", "Idle"], ["run", "Run"], ["initial_dash", "Run"], ["turn", "Walk"], ["brake", "Walk"]]:
        state.reset()
        check(state.sample({"locomotion": pair[0]}, 0).clip == pair[1], "explicit map: " + pair[0])
    state.reset()
    state.sample({"locomotion": "landing", "grounded": true}, 0)
    check(state.sample({"locomotion": "idle", "grounded": true}, 1).state == "landing", "short landing state gets one bounded visual beat")
    check(state.sample({"locomotion": "run", "grounded": true}, 2).state == "run", "movement interrupts landing fallback immediately to avoid sliding pose")
    # Hidden jump events must not start a new selected Hit episode.
    for initial_locomotion in ["falling", "rising"]:
        state.reset()
        var hit := {"locomotion": initial_locomotion, "status": "hitstun", "hit_id": 7, "air_jumps_left": 1}
        state.sample(hit, 0)
        var before: Dictionary = state.sample(hit, 1)
        hit.locomotion = "rising"
        if initial_locomotion == "rising": hit.air_jumps_left = 0
        pose = state.sample(hit, 2)
        var label: String = "persistent Hit over " + initial_locomotion
        check(pose.clip == "Hit" and pose.state == "hit", label + " keeps priority")
        check(is_equal_approx(pose.seconds, 2.0 / 60), label + " preserves clock")
        check(pose.transition == before.transition, label + " preserves transition")
        check(is_equal_approx(pose.blend, before.blend), label + " preserves completed blend")
        hit.hit_id = 8
        pose = state.sample(hit, 3)
        check(is_zero_approx(pose.seconds) and pose.transition == before.transition + 1, label + " changed hit_id restarts")
        check(is_zero_approx(pose.blend), label + " changed hit_id starts fresh blend")
        # Repeat during an in-progress Hit-entry blend, not just a completed one.
        state.reset()
        state.sample({"locomotion": "idle"}, 0)
        hit.locomotion = initial_locomotion
        hit.air_jumps_left = 1
        before = state.sample(hit, 1)
        hit.locomotion = "rising"
        if initial_locomotion == "rising": hit.air_jumps_left = 0
        pose = state.sample(hit, 2)
        check(pose.transition == before.transition and is_equal_approx(pose.seconds, 1.0 / 60), label + " entry blend keeps clock and transition")
        check(is_equal_approx(pose.blend, (1.0 / 60) / 0.03), label + " entry blend advances instead of resetting")
    state.reset()
    state.sample({"locomotion": "jump_startup", "air_jumps_left": 1}, 0)
    pose = state.sample({"locomotion": "rising", "air_jumps_left": 1}, 1)
    check(is_equal_approx(pose.seconds, 1.0 / 60), "normal startup to rise preserves Jump clock")
    var jump_transition: int = pose.transition
    pose = state.sample({"locomotion": "rising", "air_jumps_left": 0}, 2)
    check(pose.clip == "Jump" and is_zero_approx(pose.seconds) and pose.transition == jump_transition + 1 and pose.blend == 1.0, "normal air jump restarts with immediate pose")
    if failures == 0: print("PASS: core presentation decision contract")
    quit(1 if failures else 0)
