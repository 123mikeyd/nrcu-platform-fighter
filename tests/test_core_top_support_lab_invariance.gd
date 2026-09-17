extends "res://tests/test_core_stock_lab_invariance.gd"
func support_route(lab) -> Array:
    lab.reset_lab()
    lab.simulation.reset({1:Vector3(0,3,0),2:Vector3.ZERO})
    var trace := []; var acquired := false; var released := false
    # Reset gates held input until a released sample reaches the source.
    key(KEY_SPACE,false); Input.flush_buffered_events()
    await tick(lab)
    key(KEY_SPACE,true); Input.flush_buffered_events()
    await tick(lab); key(KEY_SPACE,false)
    check(lab.actors[0].velocity.y > 0,"real parsed airjump accepted")
    for i in 125:
        await tick(lab)
        var frame := []
        for id in [1,2]:
            var actor = lab.actors[id-1]
            var support: Dictionary = lab.simulation.top_support_telemetry(id)
            var relation: Dictionary = support.relation.duplicate(true)
            relation.erase("generation") # reset identity intentionally differs
            frame.append([actor.telemetry(),support.geometry,relation])
        trace.append(frame)
        if is_instance_valid(lab.collision_debug) and lab.collision_debug.visible:
            var entry: Dictionary = lab.collision_debug.entries.get("top_support:1",{})
            check(entry.get("relation",{}) == lab.simulation.top_support_telemetry(1).relation,"rendered relation follows acquisition and release same sync")
            check(entry.get("geometry",{}) == lab.simulation.top_support_telemetry(1).geometry,"live rendered surface follows actual published geometry")
        if not lab.simulation.top_support_telemetry(1).relation.is_empty(): acquired = true
        elif acquired: released = true
    check(acquired and released,"real support then finite-slip release prerequisites")
    return trace
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab); lab.set_physics_process(false)
    lab.select_fighter(1,"turbofit"); lab.set_generated_collision_enabled(true)
    # This fixture characterizes retained legacy head support, not the generated default.
    check(lab.simulation.reset_with_collision_profiles(lab.spawns, {1:lab.simulation.fighters[1].collision_host.builder._profile,2:lab.simulation.fighters[2].collision_host.builder._profile}, "legacy_solid"),"explicit legacy support fixture")
    lab._reset_round_input_and_visuals()
    var off: Array = await support_route(lab)
    lab.set_collision_shapes_visible(true)
    check(await support_route(lab) == off,"ON exact parsed jump/support/release trace equality")
    lab.collision_debug.free()
    check(await support_route(lab) == off,"REMOVED exact parsed jump/support/release trace equality")
    lab.free()
    if not failures: print("PASS: top-support OFF ON REMOVED parsed jump acquisition slip reset traces")
    quit(1 if failures else 0)
