extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    for facing in [1, -1]:
        lab.reset_lab()
        for i in range(40): await tick(lab)
        var slot := 0 if facing == 1 else 1
        var direction := KEY_D if facing == 1 else KEY_LEFT
        var special := KEY_G if facing == 1 else KEY_L
        var victim := 2 if facing == 1 else 1
        key(direction, true)
        key(special, true)
        await tick(lab)
        var f: Dictionary = lab.simulation.fighters[slot + 1]
        var visual = lab.imported_visuals[slot]
        check(f.force != null, "physical horizontal G/L accepts FORCE PUSH")
        check(visual.state.output.clip == "ForcePush", "force overrides movement lock, never Punch")
        var plays: int = visual.play_count
        var transition: int = visual.state.transition
        key(direction, false)
        key(special, false)
        for age in range(1, 60):
            if age > 1: await tick(lab)
            if f.force == null: break
            check(visual.state.output.clip == "ForcePush", "force remains selected")
            check(is_equal_approx(visual.state.output.seconds, f.force.source_time(f.force.age / 60.0)), "exact authoritative source clock")
            check(visual.position == Vector3.ZERO, "zero magic placement, no floor blend")
            check(visual.play_count == plays and visual.state.transition == transition, "same activation does not restart")
            if age < 15:
                check(lab.simulation.projectiles.is_empty() and lab.simulation.fighters[victim].percent == 0, "no startup projectile or damage")
            if age == 15:
                check(lab.simulation.projectiles.size() == 1 and lab.simulation.fighters[victim].percent == 0, "event emits without spawn damage")
                var sk: Skeleton3D = visual.skeleton
                var hand: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand")) * Vector3(0, 19.50612449645996, 0)
                check(hand.distance_to(lab.simulation.ability_events[0].position) < .002, "actual visual hand matches baked world spawn both facings")
        lab.set_paused(true)
        var before: int = lab.simulation.tick
        await tick(lab)
        check(lab.simulation.tick == before, "pause freezes force clock")
        lab.step_once()
        await tick(lab)
        check(lab.simulation.tick == before + 1, "step commits one force tick")
        lab.set_paused(false)
    var policy = load("res://scripts/core/presentation/presentation_state.gd").new()
    check(policy.sample({"force_id": "f", "force_source_time": .5, "status": "hitstun"}, 0).clip == "Hit", "Hit outranks ForcePush")
    lab.free()
    if failures == 0: print("PASS: FORCE PUSH physical G/L, exact source clock and both-facing skeleton emission")
    quit(1 if failures else 0)
