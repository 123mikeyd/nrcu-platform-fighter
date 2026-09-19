extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.select_fighter(0, "turbofit")
    lab.select_fighter(1, "turbofit")
    for slot in range(2):
        var attack := KEY_F if slot == 0 else KEY_K
        var special := KEY_G if slot == 0 else KEY_L
        var up := KEY_W if slot == 0 else KEY_UP
        var down := KEY_S if slot == 0 else KEY_DOWN
        var side := KEY_D if slot == 0 else KEY_LEFT
        for route in [[0,attack,"MeleeHorizontal"],[up,attack,"MeleeBackhand"],[down,attack,"GoalkeeperKick"],[0,special,"TwoHandCombo"],[side,special,"TwoHandCombo"],[down,special,"BlockIdle"],[up,special,"Jump"]]:
            lab.reset_lab()
            lab.actors[1-slot].position.x = 8 if slot == 0 else -8
            for i in range(40): await tick(lab)
            if route[0]: key(route[0],true)
            key(route[1],true)
            await tick(lab)
            var visual = lab.imported_visuals[slot]
            check(visual.output.clip == route[2], "physical route supplies committed Turbo request " + str(route))
            var committed: Dictionary = lab.simulation.kit_telemetry(slot+1)
            if route[1] == attack:
                check(is_equal_approx(visual.output.elapsed,committed.presentation.elapsed), "basic committed elapsed")
            else:
                check(is_equal_approx(visual.output.elapsed,committed.presentation.age), "special committed phase age")
            if route[0]: key(route[0],false)
            key(route[1],false)
            await tick(lab)
            lab.set_paused(true)
            var before: Dictionary = visual.output.duplicate(true)
            var bone: Transform3D = visual.skeleton.get_bone_pose(0)
            for i in range(4): lab._sync_visuals()
            check(visual.output == before and visual.skeleton.get_bone_pose(0).is_equal_approx(bone), "paused source clock and bones do not creep")
            lab.step_once()
            await tick(lab)
            check(is_equal_approx(visual.output.elapsed - before.elapsed, 1.0/60), "paused Step advances committed Turbo pose exactly one tick")
            lab.simulation.cancel_action(slot+1, "test")
            lab._sync_visuals()
            check(visual.output.identity != before.identity, "synchronous cancellation retires pose while paused")
            lab.set_paused(false)
    lab.free()
    if not failures: print("PASS: Turbo physical basic special requests and paused committed pose cleanup")
    quit(1 if failures else 0)
