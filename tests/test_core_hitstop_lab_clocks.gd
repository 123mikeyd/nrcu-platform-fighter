extends "res://tests/test_core_hitstop_lab_presentation.gd"
func settle(lab) -> void:
    lab.reset_lab()
    for code in [KEY_F, KEY_K, KEY_G, KEY_W, KEY_S, KEY_D, KEY_LEFT, KEY_SPACE]: key(code, false)
    for i in 40: await tick(lab)
func frozen_ticks(lab, count: int) -> void:
    var before := [pose(lab.imported_visuals[0]), pose(lab.imported_visuals[1])]
    for i in count:
        await tick(lab)
        for slot in 2: check(pose(lab.imported_visuals[slot]) == before[slot], "committed source skeleton remains fixed on skipped tick")
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.set_hitstop_enabled(true)
    # Characterization of unchanged match policies through real lab presentation.
    await settle(lab)
    key(KEY_F, true)
    await tick(lab)
    key(KEY_F, false)
    lab.set_paused(true)
    var world: int = lab.simulation.tick
    var before := pose(lab.imported_visuals[0])
    for i in 3: await tick(lab)
    check(lab.simulation.tick == world and lab.simulation.hitstop_telemetry(1).remaining_ticks == 4, "host pause consumes no hitstop")
    lab.step_once()
    await tick(lab)
    check(lab.simulation.tick == world + 1 and lab.simulation.hitstop_telemetry(1).remaining_ticks == 3 and pose(lab.imported_visuals[0]) == before, "step consumes exactly one stop not one animation tick")
    lab.set_paused(false)
    await tick(lab) # Existing resume suppresses the first physical sample.
    key(KEY_SPACE, true)
    await tick(lab)
    key(KEY_SPACE, false)
    check(not lab.simulation.fighters[1].buffer.debug_pending().is_empty(), "physical jump edge queued while stopped")
    await tick(lab)
    check(not lab.simulation.fighters[1].buffer.debug_pending().is_empty(), "queued edge survives all stop ticks")
    await tick(lab)
    check(lab.actors[0].runtime.states.locomotion == "jump_startup", "queued jump accepted once on resume")
    # Recovery and directional sources use committed shifted deadlines, never
    # world elapsed since an unshifted activation timestamp.
    for move in ["recovery", "sweep"]:
        await settle(lab)
        lab.actors[1].position.x = 0.1
        key(KEY_W if move == "recovery" else KEY_S, true)
        key(KEY_G if move == "recovery" else KEY_F, true)
        await tick(lab)
        key(KEY_W, false); key(KEY_S, false); key(KEY_G, false); key(KEY_F, false)
        check(lab.simulation.hitstop_telemetry(1).remaining_ticks == 4, "real %s contact enables stop" % move)
        var seconds: float = lab.imported_visuals[0].state.output.seconds
        await frozen_ticks(lab, 4)
        await tick(lab)
        check(is_equal_approx(lab.imported_visuals[0].state.output.seconds, seconds + 1.0/60), "%s source resumes by one actor tick" % move)
    # Force actual fighter impact pauses owner/victim, not every world shot.
    await settle(lab)
    key(KEY_D, true); key(KEY_G, true)
    await tick(lab)
    key(KEY_D, false); key(KEY_G, false)
    var contact := false
    for i in 60:
        if lab.simulation.hitstop_telemetry(1).remaining_ticks > 0:
            contact = true
            break
        await tick(lab)
    check(contact and lab.simulation.fighters[2].percent > 0, "actual force projectile impact")
    var force_age: int = lab.simulation.fighters[1].force.age
    lab.simulation.projectiles.append({"source": 1, "activation_id": "independent-clock-fixture", "facing": 1.0, "position": Vector3(8, 4, 0), "spawn_tick": -1, "ttl": 96})
    await frozen_ticks(lab, 4)
    check(lab.simulation.fighters[1].force.age == force_age, "force source age frozen")
    check(lab.projectile_visuals["independent-clock-fixture"].global_position == Vector3(9,4,0), "independent shot mesh advances throughout fighter hitstop")
    # Trades use shared committed hits, not first-presenter-wins.
    await settle(lab)
    key(KEY_LEFT, true); await tick(lab); key(KEY_LEFT, false)
    for i in 12: await tick(lab)
    lab.actors[0].position.x = -0.5; lab.actors[1].position.x = 0.5
    key(KEY_F, true); key(KEY_K, true)
    await tick(lab)
    key(KEY_F, false); key(KEY_K, false)
    check(lab.simulation.fighters[1].percent == 8 and lab.simulation.fighters[2].percent == 8, "physical shared-snapshot trade")
    await frozen_ticks(lab, 4)
    lab.free()
    if failures == 0: print("PASS: hitstop lab pause step queued input recovery strike force trades and independent projectiles")
    quit(1 if failures else 0)
