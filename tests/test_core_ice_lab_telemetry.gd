extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.select_fighter(0,"ice_mage")
    lab.actors[1].position.x = 9
    for i in range(40): await tick(lab)
    key(KEY_S,true)
    key(KEY_G,true)
    for i in range(12): await tick(lab)
    key(KEY_G,false)
    key(KEY_S,false)
    var shots: Array = lab.simulation.projectile_telemetry()
    check(shots.size() == 1, "parsed down special emits same real bolt")
    if not shots.is_empty():
        var shot: Dictionary = shots[0]
        check(shot.kind == "frost_bolt", "actual generic frost telemetry")
        var visual = lab.projectile_visuals[shot.activation_id]
        check(visual.name == "DebugFrostBolt", "un-authored frost geometry explicitly labeled")
        check(visual.global_position == shot.position and visual.get_meta("committed") == shot, "mesh mirrors exact authoritative snapshot")
        lab.set_paused(true)
        var at: Vector3 = visual.global_position
        for i in range(3): lab._sync_visuals()
        check(visual.global_position == at, "paused projectile mesh clock")
        lab.step_once()
        await tick(lab)
        check(visual.global_position != at, "manual step advances world projectile mesh")
    var data: Dictionary = lab.get_snapshot().actors[0]
    check(data.kit.get("kit_id","") == "ice_mage", "Ice detached kit telemetry not mislabeled Teknium")
    check(data.has("freeze"), "all-kit finite freeze and immunity telemetry")
    if data.kit.has("cast_cooldown"):
        check(data.kit.cast_cooldown > 1, "independent cast budget visible")
        data.kit.cast_cooldown = 999
        check(lab.simulation.kit_telemetry(1).cast_cooldown < 2, "detached diagnostic cannot mutate kit")
    lab._process(0)
    check("cast budget" in lab.telemetry_label.text and "freeze" in lab.telemetry_label.text, "visible source budgets and finite freeze diagnostics")
    lab.reset_lab()
    check(lab.projectile_visuals.is_empty(), "reset clears detached debug meshes")
    lab.free()
    if not failures: print("PASS: Ice generic frost debug FX and detached kit/status diagnostics")
    quit(1 if failures else 0)
