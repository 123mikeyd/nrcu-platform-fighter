extends "res://tests/test_core_ledge_lab_motion.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab); lab.set_physics_process(false)
    lab.set_ledges_enabled(true)
    check(await walk_catch(lab), "keyboard catch before interruption")
    for i in 31: await tick(lab)
    # Isolate incoming contact beside real ledge; actual K selection/resolution.
    lab.actors[1].position = Vector3(-13.65,-1.5,0)
    lab.actors[1].runtime.reconcile_contact(false, Vector3.ZERO)
    key(KEY_RIGHT, true); key(KEY_K, true); await tick(lab)
    key(KEY_RIGHT, false); key(KEY_K, false)
    check(lab.simulation.fighters[1].percent == 8 and lab.simulation.ledge_telemetry(1).anchor_id == "", "incoming physical K releases expired protected hang")
    check(lab.actors[0].velocity.length() > 1 and lab.actors[0].runtime.hitstun_left > 0, "release preserves incoming launch")
    lab.reset_lab()
    for i in 40: await tick(lab)
    key(KEY_W, true); key(KEY_G, true); await tick(lab)
    key(KEY_W, false); key(KEY_G, false)
    check(lab.simulation.fighters[1].recovery != null, "physical W+G accepts recovery")
    # Falling recovery fixture uses real runtime and actual platform clearance.
    lab.actors[0].position = Vector3(-13,-1,0)
    lab.actors[0].runtime.reconcile_contact(false, Vector3(1,-1,0))
    lab.actors[0].velocity = Vector3(1,-1,0)
    var ready = lab.simulation.fighters[1].ready_tick
    key(KEY_D, true); await tick(lab); key(KEY_D, false)
    check(lab.simulation.ledge_telemetry(1).anchor_id != "", "falling recovery catches actual lab edge")
    check(lab.simulation.fighters[1].recovery == null and not lab.actors[0].runtime.recovery_motion and not lab.actors[0].runtime.recovery_spent, "catch cancels recovery and restores one permission")
    check(lab.simulation.fighters[1].ready_tick == ready, "catch does not refresh ability cooldown")
    var entry: Dictionary = lab.simulation.ledge_telemetry(1)
    var actor_tick: int = lab.simulation.hitstop_telemetry(1).simulation_tick
    # Targeted finite-stop fixture; real damage-triggered stop covered by neighbors.
    lab.simulation.fighters[1].hitstop_left = 3
    key(KEY_SPACE, true)
    for i in 3:
        await tick(lab)
        check(lab.simulation.ledge_telemetry(1).protected_until == entry.protected_until+i+1, "stop shifts ledge local deadline")
        check(lab.simulation.hitstop_telemetry(1).simulation_tick == actor_tick, "stop holds actor clock")
        check(lab.simulation.ledge_telemetry(1).anchor_id != "", "queued jump does not depart during stop")
    key(KEY_SPACE, false); await tick(lab)
    check(lab.simulation.ledge_telemetry(1).anchor_id == "" and lab.actors[0].velocity == Vector3(-4,10,0), "buffered physical jump departs once after stop")
    lab.start_stock_match()
    check(await walk_catch(lab), "stock keyboard catch")
    key(KEY_S, true); await tick(lab)
    for i in 120:
        await tick(lab)
        if lab.simulation.fighters[1].stocks == 2: break
    check(lab.simulation.fighters[1].stocks == 2 and lab.simulation.ledge_telemetry(1).anchor_id == "", "real fall produces KO and ledge life cleanup")
    check(lab.simulation.fighters[1].buffer.debug_pending().is_empty(), "KO clears held-source semantic history")
    key(KEY_S, false)
    lab.rematch_lab()
    check(lab.simulation.fighters[1].stocks == 3 and lab.simulation.ledge_telemetry(1).anchor_id == "", "rematch clears occupancy and restores stocks")
    lab.free()
    if failures == 0: print("PASS: ledge lab interruption recovery local hitstop KO rematch")
    quit(1 if failures else 0)
