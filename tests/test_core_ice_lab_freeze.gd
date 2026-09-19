extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    for victim in ["teknium","turbofit","ice_mage"]:
        lab.select_fighter(0,"ice_mage")
        lab.select_fighter(1,victim)
        lab.reset_lab()
        for i in range(40): await tick(lab)
        key(KEY_G,true)
        var landed := false
        for i in range(30):
            await tick(lab)
            if lab.simulation.status_telemetry(2).frozen:
                landed = true
                break
        key(KEY_G,false)
        check(landed and lab.simulation.fighters[2].percent == 4, "real parsed bolt freezes " + victim)
        if not landed: continue
        check(lab.actors[1].runtime.states.status == "frozen", "actual committed finite status")
        if victim == "ice_mage":
            var visual = lab.imported_visuals[1]
            check(visual.output.identity == "frozen", "finite freeze wins Ice presentation priority")
            var pose: Array = []
            for b in range(visual.skeleton.get_bone_count()): pose.append(visual.skeleton.get_bone_pose(b))
            for i in range(5): await tick(lab)
            for b in range(pose.size()): check(pose[b].is_equal_approx(visual.skeleton.get_bone_pose(b)), "frozen full skeleton remains stationary across real ticks")
        var initial: Dictionary = lab.simulation.status_telemetry(2)
        key(KEY_F1,true)
        Input.flush_buffered_events()
        await process_frame
        key(KEY_F1,false)
        check(lab.paused,"parsed F1 pauses")
        for i in range(3): await tick(lab)
        check(lab.simulation.status_telemetry(2) == initial,"paused finite clock")
        key(KEY_F2,true)
        await process_frame
        await tick(lab)
        key(KEY_F2,false)
        check(is_equal_approx(initial.freeze_remaining-lab.simulation.status_telemetry(2).freeze_remaining,1.0/60),"parsed step decrements finite clock once")
        lab.set_paused(false)
        var thawed := false
        for i in range(65):
            await tick(lab)
            if not lab.simulation.status_telemetry(2).frozen:
                thawed = true
                check(lab.simulation.status_telemetry(2).freeze_immunity == 1.0,"natural thaw full immunity")
                break
        check(thawed,"natural thaw observed")
        # Recast after source's separate 1.6s budget, while immunity remains.
        while lab.simulation.kit_telemetry(1).cast_cooldown > 0: await tick(lab)
        key(KEY_G,true)
        for i in range(20): await tick(lab)
        key(KEY_G,false)
        check(lab.simulation.fighters[2].percent == 8 and not lab.simulation.status_telemetry(2).frozen,"immunity blocks refreeze not damage")
        # New round: bolt then positive physical IceStrike shatters before thaw.
        lab.reset_lab()
        for i in range(40): await tick(lab)
        key(KEY_G,true)
        for i in range(32): await tick(lab)
        key(KEY_G,false)
        check(lab.simulation.status_telemetry(2).frozen,"shatter prerequisite frozen")
        key(KEY_F,true)
        for i in range(13): await tick(lab)
        key(KEY_F,false)
        check(lab.simulation.fighters[2].percent == 12,"positive physical basic shatter damage")
        check(not lab.simulation.status_telemetry(2).frozen and lab.simulation.status_telemetry(2).freeze_immunity > .9,"shatter clears finite freeze grants immunity")
    lab.free()
    if not failures: print("PASS: parsed Ice freeze all opponents natural thaw immunity shatter and clocks")
    quit(1 if failures else 0)
