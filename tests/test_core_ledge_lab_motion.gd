extends "res://tests/test_core_combat_lab.gd"
func walk_catch(lab) -> bool:
    for i in 40: await tick(lab)
    key(KEY_A, true)
    for i in 240:
        await tick(lab)
        if lab.actors[0].position.x < -12.0: break
    key(KEY_A, false); key(KEY_D, true)
    for i in 40:
        await tick(lab)
        if lab.simulation.ledge_telemetry(1).anchor_id != "":
            key(KEY_D, false)
            print("KEYBOARD CATCH tick=%d position=%s" % [lab.simulation.tick, lab.actors[0].position])
            return true
    key(KEY_D, false)
    print("MISSED CATCH %s %s" % [lab.actors[0].position, lab.actors[0].velocity])
    return false
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab); lab.set_physics_process(false)
    lab.set_ledges_enabled(true)
    for exit_key in [KEY_W, KEY_SPACE, KEY_S]:
        lab.reset_lab()
        var caught: bool = await walk_catch(lab)
        check(caught, "real keyboard approach/fall/reverse catches actual left platform")
        if not caught: continue
        check(lab.actors[0].position.is_equal_approx(Vector3(-12.65,-1.5,0)), "authoritative hang foot pose")
        check(lab.get_snapshot().actors[0].ledge.protected, "first catch grants policy protection")
        var status = lab.actors[0].runtime.states.status
        lab.set_paused(true)
        var before: Dictionary = lab.get_snapshot()
        for i in 5: await tick(lab)
        check(lab.get_snapshot() == before, "pause holds authoritative ledge clocks")
        lab.step_once(); await tick(lab)
        check(lab.simulation.tick == before.tick+1 and lab.actors[0].runtime.states.status == status, "step commits one tick without fake ledge status")
        lab.set_paused(false)
        await tick(lab)
        key(exit_key, true); await tick(lab); key(exit_key, false)
        check(lab.simulation.ledge_telemetry(1).anchor_id == "", "physical exit releases anchor")
        if exit_key == KEY_W:
            check(lab.actors[0].position.is_equal_approx(Vector3(-11.3,.06,0)), "climb applies real clear elbow path")
            for i in 5: await tick(lab)
            check(lab.actors[0].runtime.grounded, "climb returns to actual platform collision")
        else:
            check(lab.actors[0].velocity == (Vector3(-4,10,0) if exit_key == KEY_SPACE else Vector3(0,-2,0)), "jump/drop authored velocity")
        check(not lab.simulation.ledge_telemetry(1).protected, "departures remove protection")
    lab.free()
    if failures == 0: print("PASS: ledge lab physical keyboard catch exits clocks platform")
    quit(1 if failures else 0)
