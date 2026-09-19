extends "res://tests/test_core_overlay_focus.gd"
# Independent UI/lifecycle review: do not replace or retune the AI source.
func run() -> void:
    root.content_scale_size = Vector2i.ZERO
    root.size = Vector2i(960, 540)
    root.gui_embed_subwindows = true
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    var p1_source = lab.sources[0]
    var bindings: Dictionary = p1_source.bindings.duplicate(true)
    check(lab.set_p2_repo_ai(true), "AI review prerequisite enabled")
    var profiles: Dictionary = lab.active_collision_profiles.duplicate(true)
    for mode in ["grounded_jostle", "legacy_solid"]:
        check(lab.set_comparison_interaction(mode), "comparison arm installs")
        for difficulty in ["easy", "normal", "hard"]:
            var generation: int = lab.simulation.generation
            check(lab.set_ai_difficulty(difficulty), "difficulty installs")
            check(lab.simulation.generation > generation and lab.repo_inputs.ai.sequence == 0, "difficulty fully resets before next sample")
            lab.start_stock_match()
            check(lab.active_collision_profiles == profiles, "stock start retains identical anatomical profiles")
            for i in 3:
                lab.actors[1].position = Vector3(0, -9, 0)
                await physics_frame
                lab._physics_process(1.0 / 60)
            check(not lab.simulation.result.is_empty(), "three real KOs reach result in both arms")
            lab.rematch_lab()
            check(lab.simulation.result.is_empty() and lab.simulation.fighters[2].stocks == 3, "rematch restores stocks and clears result")
            check(lab.repo_inputs.enabled and lab.repo_inputs.ai.difficulty == difficulty and lab.repo_inputs.ai.sequence == 0, "rematch preserves real source difficulty and clears sequence")
            check(lab.simulation.fighter_interaction_mode == mode and lab.active_collision_profiles == profiles, "rematch preserves arm and exact profile identities")
            check(lab.sources[0] == p1_source and lab.sources[0].bindings == bindings, "P1 source instance and physical bindings remain unchanged")
    lab.enter_sandbox()
    await process_frame
    await process_frame
    for control in [lab.p2_input_button, lab.ai_difficulty_button, lab.comparison_button]:
        lab.set_paused(false)
        await click(control)
        check(control.get_popup().visible and lab.paused, "each actual menu opens and pauses")
        var frozen_tick: int = lab.simulation.tick
        var frozen_sequence: int = lab.repo_inputs.ai.sequence
        for i in 3:
            await physics_frame
            lab._physics_process(1.0 / 60)
        check(lab.simulation.tick == frozen_tick and lab.repo_inputs.ai.sequence == frozen_sequence, "open menu freezes both clocks")
        await key(KEY_ESCAPE)
        check(not control.get_popup().visible and is_instance_valid(lab) and lab.is_inside_tree(), "Escape cancels menu without leaving combat")
        check(root.gui_get_focus_owner() != control, "cancel releases gameplay key focus")
        lab.set_paused(false)
        await physics_frame
        lab._physics_process(1.0 / 60)
        check(lab.simulation.tick == frozen_tick + 1, "menu resume commits one tick without stuck physics")
        lab._physics_process(1.0 / 60)
        check(lab.simulation.tick == frozen_tick + 1, "second same-frame call cannot simulate twice")
    check(lab.set_p2_repo_ai(false), "human control restored")
    check(lab.sources[0] == p1_source and lab.sources[0].bindings == bindings, "P1 preserved on ownership exit")
    lab.free()
    if failures == 0: print("PASS: independent AI UI both-arm stock profiles source ownership and menu cancellation")
    quit(1 if failures else 0)
