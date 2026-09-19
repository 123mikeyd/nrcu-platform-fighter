extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.start_stock_match()
    for victim in [1, 2, 0]:
        lab.rematch_lab()
        for i in range(40): await tick(lab)
        lab.actors[0].position.x = 0
        lab.actors[1].position.x = 1.1
        key(KEY_G, true)
        for i in range(30): await tick(lab)
        key(KEY_G, false)
        check(lab.simulation.fighters[2].caught_by == 1 and not lab.grab_visuals.is_empty(), "real physical grab has arcs")
        # Translate the whole live relation, preserving its separation. Only
        # the selected endpoint crosses a side bound; 0 is mutual bottom KO.
        var offset := Vector3(-16.5, 0, 0) if victim == 1 else Vector3(15.5, 0, 0)
        if victim == 0: offset = Vector3(0, -10, 0)
        for actor in lab.actors: actor.position += offset
        await tick(lab)
        for id in [1, 2]:
            var expected: int = 2 if victim == 0 or victim == id else 3
            check(lab.simulation.fighters[id].stocks == expected and lab.simulation.fighters[id].caught_by == 0 and lab.simulation.fighters[id].grab == null, "grab endpoints released by KO")
        check(lab.grab_visuals.is_empty(), "KO reconciles all arcs away")
        for visual in lab.imported_visuals:
            check(visual.animation_player.assigned_animation not in ["GrabStart", "GrabLoop", "Electrocution"], "no stale grab pose after KO")
    lab.rematch_lab()
    for i in range(40): await tick(lab)
    key(KEY_A, true)
    key(KEY_G, true)
    for i in range(15): await tick(lab)
    key(KEY_A, false)
    key(KEY_G, false)
    check(lab.simulation.projectiles.size() == 1 and lab.projectile_visuals.size() == 1, "physical force emits live shot")
    var mesh = lab.projectile_visuals.values()[0]
    lab.actors[0].position.x = -17
    await tick(lab)
    check(lab.simulation.projectiles.is_empty() and lab.projectile_visuals.is_empty() and not is_instance_valid(mesh), "source KO expires shot and render mesh on committed tick")
    lab.free()
    if failures == 0: print("PASS: stock lab physical grab/projectile KO cleanup reconciles presentation")
    quit(1 if failures else 0)
