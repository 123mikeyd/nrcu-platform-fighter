extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    if lab.get("projectile_visuals") == null:
        check(false, "lab reconciles stable-ID projectile visuals")
        lab.free()
        quit(1)
        return
    var traces: Array = []
    for mode in range(3):
        lab.reset_lab()
        for i in range(40): await tick(lab)
        if mode == 1:
            for visual in lab.imported_visuals: visual.hide()
        if mode == 2:
            for visual in lab.imported_visuals: visual.free()
        key(KEY_D, true)
        key(KEY_G, true)
        var trace: Array = []
        var saw_projectile := false
        for age in range(1, 115):
            await tick(lab)
            key(KEY_D, false)
            key(KEY_G, false)
            var shots: Array = lab.simulation.projectiles
            check(lab.projectile_visuals.size() == shots.size(), "visual count equals authoritative live shots")
            for shot in shots:
                saw_projectile = true
                var mesh = lab.projectile_visuals[shot.activation_id]
                check(mesh is MeshInstance3D and not mesh is CollisionObject3D, "projectile is visual-only mesh")
                check(mesh.global_position.distance_to(shot.position) < .000001, "exact x/y/z world position")
                if mode == 1: mesh.hide()
                if mode == 2: mesh.free()
            var physical_shots: Array = []
            for shot in shots:
                physical_shots.append([shot.source, shot.facing, shot.position, shot.ttl])
            trace.append([lab.get_snapshot().actors, physical_shots])
        check(saw_projectile and lab.projectile_visuals.is_empty(), "projectile created then consumed or expired")
        traces.append(trace)
    check(traces[0] == traces[1] and traces[0] == traces[2], "hidden/deleted all render nodes preserve exact physics")
    # Isolated long-range shot survives until TTL; reset removes it immediately.
    lab.reset_lab()
    lab.actors[1].position.x = -8
    for i in range(40): await tick(lab)
    key(KEY_D, true)
    key(KEY_G, true)
    for i in range(15): await tick(lab)
    key(KEY_D, false)
    key(KEY_G, false)
    check(lab.projectile_visuals.size() == 1, "long-range emitted shot visible")
    lab.set_paused(true)
    var shot_before: Array = lab.simulation.projectiles.duplicate(true)
    for i in range(3): await tick(lab)
    check(lab.simulation.projectiles == shot_before, "pause preserves projectile TTL and position")
    lab.step_once()
    await tick(lab)
    check(lab.simulation.projectiles[0].ttl == shot_before[0].ttl - 1, "step advances projectile once")
    lab.reset_lab()
    check(lab.projectile_visuals.is_empty() and lab.simulation.projectiles.is_empty(), "reset clears visuals and shots")
    lab.set_paused(false)
    lab.actors[1].position.x = -8
    for i in range(40): await tick(lab)
    key(KEY_D, true)
    key(KEY_G, true)
    for i in range(15): await tick(lab)
    key(KEY_D, false)
    key(KEY_G, false)
    var id: String = lab.simulation.projectiles[0].activation_id
    var visual = lab.projectile_visuals[id]
    for i in range(95):
        await tick(lab)
        check(lab.projectile_visuals.get(id) == visual, "stable ID retains mesh through all travel ticks")
    check(lab.simulation.projectiles[0].ttl == 1, "TTL shot survives last travel")
    await tick(lab)
    check(lab.simulation.projectiles.is_empty() and lab.projectile_visuals.is_empty() and not is_instance_valid(visual), "TTL expiry removes mesh on committed tick")
    lab.free()
    if failures == 0: print("PASS: projectile reconciliation, full position, lifecycle and render-independent physics")
    quit(1 if failures else 0)
