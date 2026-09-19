extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    check(lab.has_method("set_ledges_enabled"), "explicit ledges round-boundary configuration exists")
    if not lab.has_method("set_ledges_enabled"):
        lab.free(); quit(1); return
    check(lab.simulation.ledge_policy == null, "fresh sandbox preserves compatibility")
    var sim = lab.simulation
    var source = lab.sources[0]
    lab.set_ledges_enabled(true)
    check(lab.simulation.ledge_anchors.size() == 2, "installs factory's two actual stage edges")
    check(lab.simulation.ledge_anchors[0].edge == Vector3(-12,0,0) and lab.simulation.ledge_anchors[1].edge == Vector3(12,0,0), "anchors are terrain edges not blast bounds")
    for i in 40: await tick(lab)
    key(KEY_F, true)
    lab.set_ledges_enabled(false)
    await tick(lab)
    check(lab.simulation.fighters[2].percent == 0 and lab.simulation.fighters[1].buffer.debug_pending().is_empty(), "toggle round reset suppresses held attacks")
    key(KEY_F, false)
    lab.start_stock_match()
    check(lab.simulation.ledge_policy != null and lab.simulation.defense_profile != null and lab.simulation.hitstop_profile != null, "stock defaults enable all three optional policies")
    lab.set_ledges_enabled(false)
    lab.rematch_lab()
    check(lab.simulation.ledge_policy == null, "rematch preserves explicit stock choice")
    lab.enter_sandbox()
    check(lab.simulation.ledge_policy == null, "sandbox remembers its off choice")
    lab.set_ledges_enabled(true)
    lab.start_stock_match(); lab.set_ledges_enabled(false); lab.enter_sandbox()
    check(lab.simulation.ledge_policy != null, "stock choice does not overwrite sandbox choice")
    check(lab.simulation == sim and lab.sources[0] == source, "no new tick/input owner")
    lab.free()
    if failures == 0: print("PASS: ledge lab configuration lifecycle")
    quit(1 if failures else 0)
