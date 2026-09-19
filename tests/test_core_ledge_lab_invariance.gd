extends "res://tests/test_core_ledge_lab_motion.gd"
var trace: Array = []
func tick(lab) -> void:
    await physics_frame
    lab._physics_process(1.0/60.0)
    trace.append(lab.get_snapshot())
func run() -> void:
    var reference: Array = []
    for presentation in ["visible", "hidden", "removed"]:
        trace = []
        var lab = load("res://scenes/combat_lab.tscn").instantiate()
        root.add_child(lab); lab.set_physics_process(false)
        if presentation == "hidden":
            for visual in lab.imported_visuals: visual.hide()
        elif presentation == "removed":
            for visual in lab.imported_visuals: visual.free()
        lab.start_stock_match()
        check(await walk_catch(lab), "stock actual edge catch " + presentation)
        key(KEY_W, true); await tick(lab); key(KEY_W, false)
        for i in 5: await tick(lab)
        check(lab.actors[0].runtime.grounded, "actual climb terrain " + presentation)
        key(KEY_A, true)
        for i in 900:
            await tick(lab)
            if not lab.simulation.result.is_empty(): break
        key(KEY_A, false)
        check(lab.simulation.result.get("winner_id", 0) == 2 and lab.simulation.fighters[1].stocks == 0, "physical three-stock walkoff results " + presentation)
        lab.rematch_lab(); await tick(lab)
        check(lab.simulation.result.is_empty() and lab.simulation.ledge_telemetry(1).anchor_id == "", "rematch remains presentation independent")
        if reference.is_empty(): reference = trace.duplicate(true)
        else: check(trace == reference, "exact input physics resource result traces invariant " + presentation)
        print("LEDGE TRACE %s frames=%d" % [presentation, trace.size()])
        lab.free()
    if failures == 0: print("PASS: ledge lab actual terrain outcomes presenter invariance")
    quit(1 if failures else 0)
