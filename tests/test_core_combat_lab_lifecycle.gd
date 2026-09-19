extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    if not lab.has_method("reset_lab"):
        check(false, "combat lifecycle reset/pause/step exists")
        lab.free()
        quit(1)
        return
    for i in range(40): await tick(lab)
    key(KEY_LEFT, true)
    key(KEY_K, true)
    await tick(lab)
    check(lab.simulation.fighters[1].percent == 8.0, "queued physical K damages P1 independently")
    check(lab.simulation.fighters[2].percent == 0.0, "K cannot activate P1")
    key(KEY_LEFT, false)
    lab.reset_lab()
    check(lab.simulation.tick == 0 and lab.simulation.fighters[1].percent == 0, "reset clears clock and percent")
    for id in [1, 2]:
        var f: Dictionary = lab.simulation.fighters[id]
        check(f.ready_tick == 0 and f.activation_id == "" and f.buffer.debug_pending().is_empty(), "reset clears cooldown identity buffer")
        check(f.actor.velocity == Vector3.ZERO and f.actor.runtime.states.status == "normal", "reset clears launch and stun")
    await tick(lab)
    check(lab.simulation.fighters[2].activation_id == "", "held K suppressed across reset")
    key(KEY_K, false)
    await tick(lab)
    lab.set_paused(true)
    var before: int = lab.simulation.tick
    await tick(lab)
    check(lab.simulation.tick == before, "pause stops match")
    lab.step_once()
    check(lab.simulation.tick == before, "step waits for physics")
    await tick(lab)
    await tick(lab)
    check(lab.simulation.tick == before + 1, "step advances exactly once")
    lab.set_paused(false)
    lab._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
    check(lab.paused, "focus loss pauses")
    # Resume clears buffers: queue only afterwards so disconnect must flush it.
    lab.set_paused(false)
    var frame = load("res://scripts/core/input/input_frame.gd").new()
    frame.pressed.attack = true
    lab.simulation.fighters[1].buffer.advance(frame)
    check(not lab.simulation.fighters[1].buffer.debug_pending().is_empty(), "attack is pending immediately before disconnect")
    lab.sources[0].device = 42
    await tick(lab)
    check(not lab.simulation.fighters[1].enabled and lab.simulation.fighters[1].buffer.debug_pending().is_empty(), "disconnect excludes and flushes source")
    check(lab.simulation.fighters[2].enabled, "disconnect does not disable other source")
    lab.sources[0].device = -1
    lab.reset_lab()
    check(lab.simulation.fighters[1].enabled, "reset reenables scenario")
    lab.free()
    if failures == 0: print("PASS: combat lab lifecycle and independent physical K")
    quit(1 if failures else 0)
