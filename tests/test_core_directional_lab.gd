extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    for slot in range(2):
        for airborne in [false, true]:
            for down in [false, true]:
                lab.reset_lab()
                for i in range(40): await tick(lab)
                var actor = lab.actors[slot]
                var victim = lab.actors[1 - slot]
                var face := 1.0 if slot == 0 else -1.0
                if airborne:
                    actor.position = Vector3(0, 8, 0)
                    actor.runtime.grounded = false
                else: actor.position.x = 0
                victim.position = actor.position + (Vector3(0, -2 if down else 2, 0) if airborne else (Vector3(face * 2, 0, 0) if down else Vector3(0, 2, 0)))
                victim.runtime.grounded = false
                var vertical := (KEY_S if down else KEY_W) if slot == 0 else (KEY_DOWN if down else KEY_UP)
                var horizontal := KEY_D if slot == 0 else KEY_LEFT
                var attack := KEY_F if slot == 0 else KEY_K
                for code in [vertical, horizontal, attack]: key(code, true)
                await tick(lab)
                for code in [vertical, horizontal, attack]: key(code, false)
                var move := ("DOWN STRIKE" if airborne else "LOW SWEEP") if down else ("UP AIR" if airborne else "UPPERCUT")
                var clip := "Kick" if down else "Punch"
                var fighter: Dictionary = lab.simulation.fighters[slot + 1]
                var visual = lab.imported_visuals[slot]
                check(fighter.move_id == move, "physical diagonal prioritizes vertical " + move)
                check(lab.simulation.fighters[2 - slot].percent == 8, "physical target geometry receives exactly 8: " + move)
                var launch := Vector3.DOWN if airborne and down else Vector3.UP
                if down and not airborne:
                    launch = Vector3(face, -.25, 0).normalized()
                    launch.y = .35
                    launch = launch.normalized()
                check(victim.velocity.is_equal_approx(launch * (3.8 + 8 * .065 + 8 * .12)), "source launch " + move)
                check(visual.state.output.clip == clip, "committed directional clip " + move)
                check(is_equal_approx(visual.state.output.fraction, (1.0 / 60.0) / .32), "committed .32 clock on first tick " + move)
                var transition: int = visual.state.transition
                var plays: int = visual.play_count
                for i in range(5): await tick(lab)
                check(visual.state.output.clip == clip and visual.state.transition == transition and visual.play_count == plays, "directional episode never restarts " + move)
                check(is_equal_approx(visual.state.output.fraction, .1 / .32), "committed clock after blend " + move)
                check(is_equal_approx(visual.position.y, 0.0 if airborne else (-.038 if down else -.106)), "source placement scoped to new moves " + move)
    # Explicit preservation gate: SIDE/AIR retain accepted unscaled P3 clock.
    for airborne in [false, true]:
        lab.reset_lab()
        for i in range(40): await tick(lab)
        lab.actors[1].position.x = 10
        if airborne:
            lab.actors[0].position.y = 8
            lab.actors[0].runtime.grounded = false
        key(KEY_F, true)
        await tick(lab)
        key(KEY_F, false)
        for i in range(5): await tick(lab)
        var visual = lab.imported_visuals[0]
        check(lab.simulation.fighters[1].move_id == ("AIR STRIKE" if airborne else "SIDE STRIKE"), "accepted baseline move identity")
        check(visual.state.output.clip == "Punch" and visual.state.output.fraction == -1.0, "SIDE/AIR do not opt into directional retiming")
        check(is_equal_approx(visual.state.output.seconds, 5.0 / 60.0) and is_zero_approx(visual.position.y), "SIDE/AIR source seconds and zero placement unchanged")
    lab.free()
    if failures == 0: print("PASS: directional lab physical keys both slots selection damage launch clips clock placement")
    quit(1 if failures else 0)
