extends "res://tests/test_core_top_support_lab_invariance.gd"
func air_route(lab) -> Array:
    lab.reset_lab()
    lab.simulation.reset({1:Vector3(0,3,0),2:Vector3.ZERO})
    var trace := []; var crossed := false
    key(KEY_SPACE,false); Input.flush_buffered_events(); await tick(lab)
    key(KEY_SPACE,true); Input.flush_buffered_events(); await tick(lab)
    key(KEY_SPACE,false); Input.flush_buffered_events()
    check(lab.actors[0].velocity.y > 0,"real parsed airjump accepted")
    for i in 125:
        await tick(lab)
        var actor = lab.actors[0]
        var support: Dictionary = lab.simulation.top_support_telemetry(1)
        check(support.relation.is_empty() and support.geometry.is_empty(),"no default head relation or geometry")
        if actor.velocity.y < 0 and actor.position.y > .3 and actor.position.y < 1.9:
            crossed = true
            check(not actor.runtime.grounded,"descending through opponent is not a floor")
            check(lab.imported_visuals[0].canonical.output.clip != "Idle","no canonical head Idle during crossing")
            check(absf(actor.velocity.x) < .001,"no head slip injection")
        if is_instance_valid(lab.collision_debug):
            check(not lab.collision_debug.entries.has("top_support:1"),"no orange geometry during descent")
        trace.append([lab.actors[0].telemetry(),lab.actors[1].telemetry(),lab.simulation.collision_telemetry(1).pose_request.rendering_request])
    check(crossed,"actual descending body-height crossing prerequisite")
    return trace
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab); lab.set_physics_process(false)
    lab.select_fighter(1,"turbofit"); lab.set_generated_collision_enabled(true)
    var off: Array = await air_route(lab)
    lab.set_collision_shapes_visible(true)
    check(await air_route(lab) == off,"ON exact parsed air crossing and canonical pose equality")
    lab.collision_debug.free()
    check(await air_route(lab) == off,"REMOVED exact parsed crossing and pose equality")
    lab.free()
    if not failures: print("PASS: jostle lab OFF ON REMOVED no head Idle or slip")
    quit(1 if failures else 0)
