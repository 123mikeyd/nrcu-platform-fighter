extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.select_fighter(0, "ice_mage")
    lab.select_fighter(1, "ice_mage")
    for slot in range(2):
        var attack := KEY_F if slot == 0 else KEY_K
        var special := KEY_G if slot == 0 else KEY_L
        var up := KEY_W if slot == 0 else KEY_UP
        var down := KEY_S if slot == 0 else KEY_DOWN
        var side := KEY_D if slot == 0 else KEY_LEFT
        for air in [false, true]:
            for route in [[0,attack,"IceStrike"],[side,attack,"IceStrike"],[up,attack,"IceStrike"],[down,attack,"IceStrike"],[0,special,"IceCast"],[side,special,"IceCast"],[down,special,"IceCast"],[up,special,"IceCast"]]:
                lab.reset_lab()
                lab.actors[1-slot].position.x = 10 if slot == 0 else -10
                for i in range(40): await tick(lab)
                if air:
                    var jump := KEY_SPACE if slot == 0 else KEY_ENTER
                    key(jump,true)
                    for i in range(8): await tick(lab)
                    key(jump,false)
                    check(not lab.actors[slot].runtime.grounded, "real jump establishes air prerequisite")
                if route[0]: key(route[0],true)
                key(route[1],true)
                await tick(lab)
                var visual = lab.imported_visuals[slot]
                check(visual.output.clip == route[2], "physical Ice route presents actual clip " + str(route))
                var committed: Dictionary = lab.simulation.kit_telemetry(slot+1)
                check(is_equal_approx(visual.output.elapsed,committed.presentation.elapsed), "raw committed source elapsed")
                if route[0]: key(route[0],false)
                key(route[1],false)
                await tick(lab)
                lab.set_paused(true)
                var before: Dictionary = visual.output.duplicate(true)
                var bones: Array = []
                for bone in range(visual.skeleton.get_bone_count()): bones.append(visual.skeleton.get_bone_pose(bone))
                for i in range(4): lab._sync_visuals()
                check(visual.output == before, "paused source clock does not creep")
                for bone in range(bones.size()): check(bones[bone].is_equal_approx(visual.skeleton.get_bone_pose(bone)), "paused complete skeleton")
                key(KEY_F2,true)
                await process_frame
                await tick(lab)
                key(KEY_F2,false)
                check(is_equal_approx(visual.output.elapsed - before.elapsed, 1.0/60), "parsed F2 consumes exactly one committed actor pose tick")
                lab.set_paused(false)
                if route[1] == special and route[0] == up:
                    for i in range(32): await tick(lab)
                    check(lab.simulation.projectile_telemetry().is_empty(), "Frost Rise never emits extra bolt")
                    check(lab.actors[slot].runtime.recovery_spent and visual.output.clip != "IceCast", "recovery resource spent and .5 presentation ends before .65 action tail")
                lab.simulation.cancel_action(slot+1, "test")
                lab._sync_visuals()
                check(visual.output.identity != before.identity, "synchronous cancellation retires committed episode")
    lab.free()
    if not failures: print("PASS: Ice both-slot ground air directions recovery committed source clocks and parsed F2")
    quit(1 if failures else 0)
