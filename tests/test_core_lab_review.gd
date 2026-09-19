extends SceneTree

const Lab = preload("res://scripts/tools/training_lab.gd")
const Frame = preload("res://scripts/core/input/input_frame.gd")
class ScriptedSource extends "res://scripts/core/input/player_input_source.gd":
    var schedule: Dictionary = {}
    var present := true
    func sample(tick: int):
        var data: Dictionary = schedule.get(tick, {})
        return sample_snapshot(tick, data, {}, Vector2.ZERO, present)

var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        print("FAIL: ", message)

func _initialize() -> void:
    call_deferred("run")

func make_lab():
    var lab = Lab.new()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.set_process(false)
    var source = ScriptedSource.new()
    lab.sources[0] = source
    lab.slot_modes[0] = "Keyboard"
    return lab

func tick(lab) -> void:
    await physics_frame
    lab._simulate_tick()

func test_shield() -> void:
    var lab = make_lab()
    lab.sources[0].schedule = {0: {KEY_SPACE: true, KEY_E: true}, 1: {KEY_SPACE: true}, 2: {KEY_SPACE: true}}
    await tick(lab)
    check(not lab.buffers[0].peek("jump").is_empty(), "current shield must not consume rejected jump")
    check(lab.actors[0].velocity.y <= 0, "shield blocks jump on press frame")
    await tick(lab)
    await tick(lab)
    check(lab.actors[0].velocity.y > 0, "queued jump executes after shield unlock within window")
    check(lab.buffers[0].peek("jump").is_empty(), "accepted jump consumed")
    check(lab.actors[0].runtime.air_jumps_left == 0, "exactly one air jump spent")
    var accepted := 0
    for entry in lab.actors[0].runtime.states.trace:
        if entry.reason == "accepted air jump": accepted += 1
    check(accepted == 1, "one request causes exactly one jump")
    lab.free()

# Record real actor motion until an exhausted air jump queues just before landing.
func pending_recording(lab) -> void:
    lab.spawns[0] = Vector3(-4, 1, 0)
    lab.sources[0].schedule = {1: {KEY_SPACE: true}}
    lab.start_recording()
    for i in range(100):
        if lab.actors[0].velocity.y < 0 and lab.actors[0].position.y < 0.2 and lab.actors[0].runtime.air_jumps_left == 0:
            lab.sources[0].schedule[lab.simulation_tick] = {KEY_SPACE: true}
            await tick(lab)
            check(not lab.buffers[0].peek("jump").is_empty(), "prelanding request genuinely pending with air budget exhausted")
            return
        await tick(lab)
    check(false, "fixture must reach prelanding buffer window")

func motion(lab) -> Array:
    return snapshot_motion(lab.get_snapshot())

func snapshot_motion(snapshot: Dictionary) -> Array:
    var result: Array = []
    for actor in snapshot.actors:
        result.append([actor.position, actor.velocity, actor.locomotion, actor.action,
            actor.status, actor.grounded, actor.air_jumps_left, actor.pending])
    return result

func test_pause_policy() -> void:
    var lab = make_lab()
    await pending_recording(lab)
    var before = motion(lab)
    lab.set_paused(true)
    check(lab.buffers[0].peek("jump").is_empty(), "live pause flushes pending request")
    lab.set_paused(false)
    for i in range(10): await tick(lab)
    lab.stop_recording()
    check(not lab.start_replay(), "recording with external pause flush must be refused")
    check("invalid" in lab.status_message.to_lower(), "invalid recording refusal explains policy")
    lab.free()

    lab = make_lab()
    lab.set_paused(true)
    await pending_recording(lab)
    # Starting paused and normal Resume has no flush; this take remains playable.
    lab.set_paused(false)
    for i in range(10): await tick(lab)
    lab.stop_recording()
    check(lab.start_replay(), "starting a take already paused then Resume is valid")
    var expected: Array = []
    var pending_index := -1
    for i in range(lab.recordings[0].frames.size()):
        await tick(lab)
        expected.append(motion(lab))
        if not lab.buffers[0].peek("jump").is_empty(): pending_index = i
    check(pending_index >= 0, "reference replay includes pending prelanding jump")
    check(lab.start_replay(), "reference take can replay again")
    for i in range(expected.size()):
        await tick(lab)
        if i == pending_index:
            before = motion(lab)
            var clock: int = lab.simulation_tick
            lab._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
            for wait_tick in range(3):
                await physics_frame
                lab._physics_process(1.0 / 60.0)
            check(lab.simulation_tick == clock and motion(lab) == before, "focus pause preserves replay actor and pending request")
            lab.set_paused(false)
        check(motion(lab) == expected[i], "pause/resume replay motion and pending trace equal at %d" % i)
    lab.free()

func test_rebind_replay_policy() -> void:
    var lab = make_lab()
    await pending_recording(lab)
    for i in range(12): await tick(lab)
    lab.stop_recording()
    var ground_jump := false
    for entry in lab.actors[0].runtime.states.trace:
        if entry.reason == "accepted ground jump": ground_jump = true
    check(ground_jump, "rebind fixture lands and executes buffered ground jump")
    var expected: Array = []
    var pending_index := -1
    check(lab.start_replay(), "rebind reference take replays")
    for i in range(lab.recordings[0].frames.size()):
        await tick(lab)
        expected.append(motion(lab))
        if not lab.buffers[0].peek("jump").is_empty(): pending_index = i
    check(pending_index >= 0, "rebind reference has a pending prelanding jump")
    check(lab.start_replay(), "same take replays for successful rebind")
    for i in range(expected.size()):
        await tick(lab)
        if i == pending_index:
            lab.set_paused(true)
            var before = motion(lab)
            var clock: int = lab.simulation_tick
            check(not lab.buffers[0].peek("jump").is_empty(), "jump is pending before paused rebind")
            check(KEY_F12 not in lab.sources[0].bindings.values(), "rebind target key is unused")
            check(lab.rebind_key(0, "jump", KEY_F12), "paused replay jump rebind succeeds")
            check(lab.sources[0].bindings.jump == KEY_F12, "successful rebind updates live binding")
            check(lab.paused and lab.replaying, "successful rebind keeps playback paused and active")
            check(lab.simulation_tick == clock and motion(lab) == before, "successful rebind preserves replay motion and full pending requests")
            lab.set_paused(false)
        check(motion(lab) == expected[i], "rebind/resume replay trajectory and full pending requests equal reference at %d" % i)
    lab.free()

func test_disconnect_policy() -> void:
    var lab = make_lab()
    await pending_recording(lab)
    for i in range(12): await tick(lab)
    lab.stop_recording()
    var ground_jump := false
    for entry in lab.actors[0].runtime.states.trace:
        if entry.reason == "accepted ground jump": ground_jump = true
    check(ground_jump, "meaningful take lands and executes buffered ground jump")
    var recorded_trace: Array = lab.trace.duplicate(true)
    lab.slot_modes[0] = "Pad"
    lab.sources[0].device = 8
    var expected: Array = []
    check(lab.start_replay(), "buffered take replays with connected hardware")
    lab.sources[0]._on_joy_connection_changed(8, true)
    for i in range(lab.recordings[0].frames.size()):
        await tick(lab)
        expected.append(motion(lab))
        check(motion(lab) == snapshot_motion(recorded_trace[i]), "recorded live motion matches connected replay at %d" % i)
    check(lab.start_replay(), "same take replays with disconnected hardware")
    lab.sources[0]._on_joy_connection_changed(8, false)
    for i in range(expected.size()):
        await tick(lab)
        check(motion(lab) == expected[i], "hardware-independent replay motion/state/pending at %d" % i)
    lab.free()

    lab = make_lab()
    await pending_recording(lab)
    lab.slot_modes[0] = "Pad"
    lab.sources[0].device = 8
    lab.sources[0].present = false
    await tick(lab)
    check(lab.buffers[0].peek("jump").is_empty(), "recording-time disconnect flushes pending jump")
    lab.stop_recording()
    check(not lab.start_replay(), "recording-time disconnect flush invalidates take")
    check("disconnect" in lab.status_message.to_lower(), "invalid take names disconnect cause")
    lab.free()

func run() -> void:
    await test_shield()
    if failures == 0: print("PASS: current shield retains jump, unlock consumes exactly once")
    await test_pause_policy()
    if failures == 0: print("PASS: live pause invalidates take; paused-start Resume and focus-paused replay preserve trajectory")
    await test_rebind_replay_policy()
    if failures == 0: print("PASS: successful paused replay rebind preserves trajectory and full pending requests")
    await test_disconnect_policy()
    if failures == 0: print("PASS: prelanding live/replay traces match across hardware states; disconnect flush invalidates take")
    if failures == 0: print("PASS: integrated lab review regressions")
    quit(1 if failures else 0)
