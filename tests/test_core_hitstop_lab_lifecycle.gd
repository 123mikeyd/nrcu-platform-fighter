extends "res://tests/test_core_hitstop_lab_clocks.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.set_hitstop_enabled(true)
    await settle(lab)
    lab.actors[0].position.x = 0
    lab.actors[1].position.x = 1.1
    key(KEY_G, true)
    await tick(lab)
    key(KEY_G, false)
    for i in 25: await tick(lab)
    check(lab.simulation.fighters[2].caught_by == 1, "real grab relation established")
    var grab = lab.simulation.fighters[1].grab
    var elapsed: float = grab.elapsed
    # A pause fixture isolates joint/source-clock policy; actual direct hits
    # cancel a grab, so do not fake an impossible surviving incoming contact.
    lab.simulation.fighters[1].hitstop_left = 4
    await frozen_ticks(lab, 4)
    check(grab.elapsed == elapsed and lab.simulation.hitstop_telemetry(2).stopped_this_tick, "grab owner/victim share stop and committed source age")
    await tick(lab)
    check(is_equal_approx(grab.elapsed, elapsed + 1.0/60), "grab source resumes by one tick")
    for i in 80:
        await tick(lab)
        for id in [1,2]: check(lab.simulation.hitstop_telemetry(id).remaining_ticks == 0, "electric periodic percent never creates stop")
    check(lab.simulation.fighters[2].percent == 10, "five unchanged electric ordinals")
    await settle(lab)
    key(KEY_F, true); await tick(lab); key(KEY_F, false)
    lab.reset_lab()
    for data in lab.get_snapshot().actors:
        check(data.hitstop_remaining_ticks == 0 and not data.hitstop_stopped_this_tick and data.simulation_tick == 0, "reset clears stop and actor presentation clock")
    check(lab.simulation.hitstop_profile != null, "sandbox reset retains explicit opt in")
    lab.start_stock_match()
    for i in 40: await tick(lab)
    lab.actors[0].position.x = -0.5; lab.actors[1].position.x = 0.5
    key(KEY_F, true); await tick(lab); key(KEY_F, false)
    check(lab.simulation.hitstop_telemetry(1).remaining_ticks == 4, "stock direct contact")
    lab.actors[0].position.x = -17
    await tick(lab)
    check(lab.simulation.fighters[1].stocks == 2, "KO processed during stop")
    check(lab.get_snapshot().actors[0].hitstop_remaining_ticks == 0 and not lab.get_snapshot().actors[0].hitstop_stopped_this_tick, "KO clears stopped diagnostics")
    lab.rematch_lab()
    check(lab.simulation.hitstop_profile != null, "rematch retains copied profile")
    for slot in 2:
        check(lab.imported_visuals[slot].state.last_tick == 0, "rematch resets presentation origin")
        check(lab.get_snapshot().actors[slot].hitstop_remaining_ticks == 0, "rematch clears pause")
    lab.free()
    if failures == 0: print("PASS: hitstop lab grab clocks electric exclusion reset KO rematch")
    quit(1 if failures else 0)
