extends "res://tests/test_core_combat_lab.gd"
func pose(visual) -> Array:
    var result: Array = [visual.position, visual.model.transform, visual.state.output.duplicate(true), visual.animation_player.current_animation_position, visual.play_count]
    for bone in visual.skeleton.get_bone_count(): result.append(visual.skeleton.get_bone_pose(bone))
    return result
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.set_hitstop_enabled(true)
    for i in 40: await tick(lab)
    key(KEY_F, true)
    await tick(lab)
    key(KEY_F, false)
    check(lab.simulation.fighters[2].percent == 8, "real direct strike commits")
    var impact: Array = [pose(lab.imported_visuals[0]), pose(lab.imported_visuals[1])]
    var positions: Array = [lab.actors[0].position, lab.actors[1].position]
    var clock: int = lab.simulation.tick
    for stopped in 4:
        await tick(lab)
        for slot in 2:
            check(pose(lab.imported_visuals[slot]) == impact[slot], "all bones, blend, placement and source time freeze symmetrically tick %d" % stopped)
            check(lab.actors[slot].position == positions[slot], "body stays fixed")
            var data: Dictionary = lab.get_snapshot().actors[slot]
            check(data.get("hitstop_remaining_ticks", -1) == 3 - stopped, "actual future remaining diagnostic")
            check(data.get("hitstop_stopped_this_tick", false), "last skipped tick remains stopped at zero remaining")
            check(lab.imported_visuals[slot].state.last_tick == lab.simulation.hitstop_telemetry(slot + 1).simulation_tick, "presenter uses committed actor clock")
    check(lab.simulation.tick == clock + 4, "world clock keeps advancing")
    await tick(lab)
    check(pose(lab.imported_visuals[0]) != impact[0], "source and blend resume on next actor tick")
    lab.free()
    if failures == 0: print("PASS: real hitstop lab skeleton blend placement clocks and diagnostics")
    quit(1 if failures else 0)
