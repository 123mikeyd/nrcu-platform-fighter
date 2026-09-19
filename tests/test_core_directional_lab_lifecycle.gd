extends "res://tests/test_core_combat_lab.gd"
# Existing lifecycle policy exercised through physical keys, not new gameplay.
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    for airborne in [false, true]:
        for down in [false, true]:
            lab.reset_lab()
            for i in range(40): await tick(lab)
            lab.actors[1].position.x = 10
            if airborne:
                lab.actors[0].position.y = 8
                lab.actors[0].runtime.grounded = false
            var vertical := KEY_S if down else KEY_W
            key(vertical, true)
            key(KEY_F, true)
            await tick(lab)
            key(vertical, false)
            key(KEY_F, false)
            var visual = lab.imported_visuals[0]
            var fighter: Dictionary = lab.simulation.fighters[1]
            var id: String = fighter.activation_id
            lab.set_paused(true)
            var frozen: Dictionary = visual.state.output.duplicate(true)
            var before: int = lab.simulation.tick
            for i in range(3): await tick(lab)
            check(lab.simulation.tick == before and visual.state.output == frozen, "pause preserves directional source clock")
            lab.step_once()
            await tick(lab)
            check(lab.simulation.tick == before + 1 and is_equal_approx(visual.state.output.fraction, (2.0 / 60.0) / .32), "step advances one committed directional tick")
            lab.set_paused(false)
            var transition: int = visual.state.transition
            if airborne:
                lab.actors[0].position.y = .01
                lab.actors[0].runtime.velocity.y = -1
            for i in range(5): await tick(lab)
            check(fighter.activation_id == id and visual.state.transition == transition, "landing/locomotion cannot restart accepted episode")
            check(is_equal_approx(visual.state.output.fraction, (7.0 / 60.0) / .32), "continuous committed source clock")
            check(is_equal_approx(visual.position.y, -.038 if down else -.106), "ground placement after actual landing")
            # Real incoming physical K side strike interrupts the existing episode.
            lab.actors[1].position = lab.actors[0].position + Vector3(1.5, 0, 0)
            lab.actors[1].runtime.velocity = Vector3.ZERO
            key(KEY_LEFT, true)
            key(KEY_K, true)
            await tick(lab)
            key(KEY_LEFT, false)
            key(KEY_K, false)
            check(fighter.percent == 8 and fighter.activation_id == "", "incoming real strike cancels directional episode")
            check(visual.state.output.clip == "Hit", "incoming Hit outranks Punch/Kick")
            lab.reset_lab()
            check(fighter.percent == 0 and fighter.activation_id == "" and visual.state.output.state != "strike", "reset clears hit and directional presentation")
            for i in range(40): await tick(lab)
            key(vertical, true)
            key(KEY_F, true)
            await tick(lab)
            check(visual.state.output.state == "strike", "fresh edge accepts after reset")
            lab.reset_lab()
            check(visual.state.output.state != "strike", "reset interrupts live directional pose")
            for i in range(25): await tick(lab)
            check(fighter.activation_id == "", "held key across reset cannot retrigger")
            key(vertical, false)
            key(KEY_F, false)
    lab.free()
    if failures == 0: print("PASS: directional lab pause step landing continuity real incoming hit reset held suppression")
    quit(1 if failures else 0)
