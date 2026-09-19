extends "res://tests/test_core_combat_lab.gd"
# Characterization of the existing Match ownership guarantee through the new lab.
func scenario(lab) -> Array:
    lab.reset_lab()
    for i in range(40): await tick(lab)
    key(KEY_D, true)
    key(KEY_F, true)
    key(KEY_LEFT, true)
    key(KEY_K, true)
    await tick(lab)
    check(lab.simulation.fighters[1].percent == 8 and lab.simulation.fighters[2].percent == 8, "both physical frames sampled before match resolves trade")
    for code in [KEY_D, KEY_F, KEY_LEFT, KEY_K]: key(code, false)
    var trace: Array = [lab.get_snapshot()]
    for i in range(30):
        await tick(lab)
        trace.append(lab.get_snapshot())
    return trace
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    var visible_trace := await scenario(lab)
    for visual in lab.imported_visuals: visual.free()
    var invisible_trace := await scenario(lab)
    check(visible_trace == invisible_trace, "removing both real Teknium presenters leaves exact gameplay trace unchanged")
    # Shortcuts enter the same lifecycle as UI and never tick outside physics.
    var event := InputEventKey.new()
    event.physical_keycode = KEY_F1
    event.pressed = true
    lab._unhandled_key_input(event)
    check(lab.paused, "F1 shortcut pauses")
    event.physical_keycode = KEY_F2
    lab._unhandled_key_input(event)
    var before: int = lab.simulation.tick
    await tick(lab)
    await tick(lab)
    check(lab.simulation.tick == before + 1, "F2 shortcut steps once")
    event.physical_keycode = KEY_F3
    lab._unhandled_key_input(event)
    check(lab.simulation.tick == 0, "F3 shortcut resets")
    lab.free()
    if failures == 0: print("PASS: combat lab trades, visual-removal invariance, shortcuts")
    quit(1 if failures else 0)
