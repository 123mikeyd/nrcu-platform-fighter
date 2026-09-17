extends "res://tests/test_core_turbo_lab_invariance.gd"
func scenario(lab) -> Array:
    lab.enter_sandbox()
    var trace := []
    for i in range(40): await tick(lab)
    key(KEY_G,true)
    for i in range(32):
        await tick(lab)
        trace.append(normalized(lab.get_snapshot()))
    key(KEY_G,false)
    check(lab.simulation.fighters[2].percent == 4 and lab.simulation.status_telemetry(2).frozen,"invariance real bolt freeze prerequisite")
    key(KEY_F,true)
    for i in range(13):
        await tick(lab)
        trace.append(normalized(lab.get_snapshot()))
    key(KEY_F,false)
    check(lab.simulation.fighters[2].percent == 12 and not lab.simulation.status_telemetry(2).frozen,"invariance actual shatter")
    for i in range(80):
        await tick(lab)
        trace.append(normalized(lab.get_snapshot()))
    lab.start_stock_match()
    for stock in range(3):
        for i in range(40): await tick(lab)
        key(KEY_A,true)
        key(KEY_S,true) # no ledge catch; physical walkoff, not injected KO
        var before: int = lab.simulation.fighters[1].stocks
        var lost := false
        for i in range(240):
            await tick(lab)
            trace.append(normalized(lab.get_snapshot()))
            if lab.simulation.fighters[1].stocks < before:
                lost = true
                break
        key(KEY_A,false)
        key(KEY_S,false)
        check(lost,"physical walkoff reaches real blast and spends stock")
    check(lab.simulation.result.get("winner_id",0)==2,"real stock result without renderer authority")
    var end_tick: int = lab.simulation.tick
    lab.step_once()
    await tick(lab)
    check(lab.simulation.tick == end_tick,"results stop world even manual step")
    lab.rematch_lab()
    check(lab.simulation.result.is_empty() and lab.simulation.fighters[1].stocks == 3,"rematch resets result stock")
    trace.append(normalized(lab.get_snapshot()))
    return trace
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    for opponent in ["teknium","turbofit","ice_mage"]:
        lab.select_fighter(0,"ice_mage")
        lab.select_fighter(1,opponent)
        var first := await scenario(lab)
        for v in lab.imported_visuals: v.hide()
        var hidden := await scenario(lab)
        check(first == hidden,"hidden mixed/duplicate exact Ice trace " + opponent)
        for v in lab.imported_visuals: v.free()
        var absent := await scenario(lab)
        check(first == absent,"deleted mixed/duplicate exact Ice trace " + opponent)
        print("TRACE ",opponent," snapshots=",first.size())
        lab.select_fighter(0,"teknium")
        lab.select_fighter(0,"ice_mage")
        lab.select_fighter(1,"turbofit" if opponent == "teknium" else "teknium")
        lab.select_fighter(1,opponent)
    lab.free()
    if not failures: print("PASS: visible hidden deleted Ice freeze shatter physical stock outcomes all pairings")
    quit(1 if failures else 0)
