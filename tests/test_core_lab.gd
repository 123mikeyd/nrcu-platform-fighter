extends SceneTree

var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        print("FAIL: ", message)

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    check(ResourceLoader.exists("res://scenes/training_lab.tscn"), "standalone movement lab exists")
    if failures:
        quit(1)
        return
    var packed = load("res://scenes/training_lab.tscn")
    var lab = packed.instantiate()
    root.add_child(lab)
    await process_frame
    lab.set_physics_process(false)
    check(lab.actors.size() == 2, "two independently owned movement actors")
    check(lab.actors[0].profile.resource_path == "res://data/characters/teknium_movement.tres", "lab uses editable pilot movement resource")
    check(lab.buffers.size() == 2, "each slot owns a separate input buffer")
    check(get_nodes_in_group("core_pass_through").size() >= 1, "lab includes a real pass-through platform")
    check(get_nodes_in_group("core_ledge_markers").size() == 4, "authored ledge marker placeholders are explicit")
    lab.set_paused(true)
    var before: int = lab.simulation_tick
    lab._physics_process(1.0 / 60.0)
    check(lab.simulation_tick == before, "paused lab does not advance gameplay")
    lab.step_once()
    check(lab.simulation_tick == before, "single-step waits for a real physics tick")
    await physics_frame
    lab._physics_process(1.0 / 60.0)
    check(lab.simulation_tick == before + 1, "single-step advances exactly one tick")
    check(lab.actors[0].runtime.tick == before + 1, "actor clock advances with lab clock")
    lab.start_recording()
    for i in range(2):
        lab.step_once()
        await physics_frame
        lab._physics_process(1.0 / 60.0)
    lab.stop_recording()
    check(lab.recordings[0].frames.size() == 2, "recording contains one input frame per simulated tick")
    check(lab.start_replay(), "recorded movement can be replayed")
    check(lab.replaying, "replay mode is visible")
    for i in range(3):
        lab.step_once()
        await physics_frame
        lab._physics_process(1.0 / 60.0)
    check(not lab.replaying, "replay ends with neutral/reset input rather than looping")
    lab.reset_lab()
    check(lab.simulation_tick == 0, "reset resets gameplay clock")
    check(lab.buffers[0].debug_pending().is_empty(), "reset removes queued actions")
    check(not lab.recording and not lab.replaying, "reset exits recording/playback")
    check(lab.get_snapshot().has("actors"), "telemetry is available without visual inspection")
    check(lab.rebind_key(0, "jump", KEY_J), "lab exposes key rebinding")
    check(lab.sources[0].bindings.jump == KEY_J, "new physical key reaches input source")
    check(not lab.rebind_key(0, "jump", KEY_A), "conflicting movement/action key is rejected")
    check(not lab.rebind_key(9, "jump", KEY_J), "invalid player slot rejected")
    check(lab.paused, "editing bindings pauses gameplay")
    lab.set_slot_mode(0, "Pad", 8)
    lab.set_slot_mode(1, "Pad", 8)
    check(lab.slot_modes[1] != "Pad", "one physical controller cannot own both slots")
    lab.actors[0].reset_at(lab.spawns[0])
    var frame = load("res://scripts/core/input/input_frame.gd").new()
    frame.pressed.jump = true
    lab.buffers[0].advance(frame)
    await physics_frame
    lab._simulate_tick()
    check(lab.actors[0].velocity.y <= 0, "disconnect flushes buffered jump before it can execute")
    lab.set_paused(false)
    lab._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
    check(lab.paused, "focus loss pauses the lab and clears transient inputs")
    lab.queue_free()
    await process_frame
    if failures == 0: print("PASS: core lab lifecycle, pause, recording and reset")
    quit(1 if failures else 0)
