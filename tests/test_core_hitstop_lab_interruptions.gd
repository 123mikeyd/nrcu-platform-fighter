extends "res://tests/test_core_hitstop_lab_presentation.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.set_hitstop_enabled(true)
    for i in 40: await tick(lab)
    lab.actors[1].position.x = 0.1
    key(KEY_W, true); key(KEY_G, true)
    await tick(lab)
    key(KEY_W, false); key(KEY_G, false)
    check(lab.imported_visuals[0].state.output.clip == "RaiseWall", "real recovery is presented")
    await tick(lab)
    var clock: int = lab.simulation.hitstop_telemetry(1).simulation_tick
    lab.simulation.set_enabled(1, false)
    lab._sync_visuals()
    check(lab.imported_visuals[0].state.output.clip != "RaiseWall", "synchronous disable retires episode without an actor advancement")
    check(lab.simulation.hitstop_telemetry(1).simulation_tick == clock, "presentation cancellation cannot advance actor time")
    lab.free()
    if failures == 0: print("PASS: hitstop lab synchronous lifecycle reconciliation at unchanged actor tick")
    quit(1 if failures else 0)
