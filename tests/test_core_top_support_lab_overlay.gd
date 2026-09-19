extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab); lab.set_physics_process(false)
    lab.select_fighter(1,"turbofit"); lab.set_generated_collision_enabled(true)
    # This fixture characterizes retained legacy head support, not the generated default.
    check(lab.simulation.reset_with_collision_profiles(lab.spawns, {1:lab.simulation.fighters[1].collision_host.builder._profile,2:lab.simulation.fighters[2].collision_host.builder._profile}, "legacy_solid"),"explicit legacy support fixture")
    lab._reset_round_input_and_visuals()
    lab.set_collision_shapes_visible(true)
    await tick(lab)
    for id in [1,2]:
        var published: Dictionary = lab.simulation.top_support_telemetry(id)
        var entry: Dictionary = lab.collision_debug.entries.get("top_support:%d" % id,{})
        check(not entry.is_empty(),"dedicated physical top-support surface")
        if entry.is_empty(): continue
        check(entry.points == PackedVector3Array(published.geometry.world_segment),"only actual published world endpoints, no guessed bounds")
        check(entry.geometry == published.geometry and entry.relation == published.relation,"detached stable category and ephemeral relation")
        check(entry.color not in [lab.collision_debug.FIGHTER_COLOR,lab.collision_debug.TERRAIN_COLOR,Color(1,.3,1),Color(1,.85,.1)],"support distinct from body terrain and both hurtbox phases")
        entry.geometry.height = -900
        check(lab.simulation.top_support_telemetry(id).geometry.height > 0,"consumer detached from authority")
    lab.set_collision_shapes_visible(false)
    check(lab.collision_debug.entries.is_empty(),"OFF clears geometry")
    lab.set_collision_shapes_visible(true)
    lab.simulation.set_enabled(1,false); lab.collision_debug.refresh()
    check(not lab.collision_debug.entries.has("top_support:1"),"disabled participant hidden")
    lab.reset_lab(); lab.collision_debug.refresh()
    check(lab.collision_debug.entries.get("top_support:1",{}).get("relation",{}).is_empty(),"reset no stale relation")
    lab.set_generated_collision_enabled(false)
    check(not lab.collision_debug.entries.has("top_support:1") and not lab.collision_debug.entries.has("top_support:2"),"optout no stale support")
    lab.free()
    if not failures: print("PASS: top support published endpoints detached diagnostics and lifecycle")
    quit(1 if failures else 0)
