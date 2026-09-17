extends "res://tests/test_core_combat_lab.gd"

func tick(lab) -> void:
    await physics_frame
    Input.flush_buffered_events()
    lab._physics_process(1.0 / 60.0)

func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.set_paused(true)
    check(lab.set_generated_collision_enabled(true), "generated mode installed")
    for i in 30:
        lab.step_once(); await tick(lab)
    key(KEY_K, true)
    lab.step_once(); await tick(lab)
    key(KEY_K, false)
    for i in 9:
        lab.step_once(); await tick(lab)
    var view = lab.imported_visuals[1]
    check(view.canonical.output.get("clip", "") == "SwingPunchV1", "actual P2 swing prerequisite")
    check(view.animation_player.assigned_animation == "SwingPunchV1", "derived clip actually assigned")
    var library = view.canonical._libraries[""]
    var generation: int = lab.simulation.generation
    key(KEY_F5, true); Input.flush_buffered_events()
    key(KEY_F5, false); Input.flush_buffered_events()
    check(not lab.generated_collision_enabled, "real F5 mode exit")
    check(lab.simulation.generation == generation + 1, "mode exit exactly one match reset")
    check(lab.paused and lab.simulation.tick == 0, "pause and reset clock preserved")
    check(not view.canonical.active and view.canonical.output.is_empty(), "canonical state retired")
    check(view.animation_player.get_animation_library("") == library, "original library restored")
    check(not view.animation_player.has_animation("SwingPunchV1"), "private derived animation retired")
    check(view.animation_player.assigned_animation != "SwingPunchV1", "no stale assigned derived key after mode exit")
    for i in 30:
        lab.step_once(); await tick(lab)
    check(view.state.output.get("clip", "") == "Idle", "legacy resumes idle")
    check(lab.set_generated_collision_enabled(true), "reenable succeeds")
    for i in 30:
        lab.step_once(); await tick(lab)
    key(KEY_K, true)
    lab.step_once(); await tick(lab)
    key(KEY_K, false)
    for i in 9:
        lab.step_once(); await tick(lab)
    check(view.canonical.output.get("clip", "") == "SwingPunchV1", "reenabled swing valid")
    lab.reset_lab()
    check(view.canonical.output.get("clip", "") != "SwingPunchV1", "paused reset cancels derived episode")
    lab.free()
    if not failures: print("PASS: actual F5 mid-swing mode exit and reenable")
    quit(1 if failures else 0)
