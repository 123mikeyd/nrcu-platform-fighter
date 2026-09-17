extends "res://tests/test_core_grab_lab_lifecycle.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    # Whiff: no retry, no percent, ending still plays then retires.
    lab.actors[1].position.x = 8
    for i in range(40): await tick(lab)
    key(KEY_G, true)
    for age in range(1, 56):
        await tick(lab)
        if age == 22:
            check(lab.simulation.fighters[1].grab.phase == "ending", "whiff enters ending")
            check(lab.imported_visuals[0].animation_player.assigned_animation == "GrabEnd", "whiff source ending")
        check(lab.grab_visuals.is_empty(), "whiff never shows arcs")
    key(KEY_G, false)
    check(lab.simulation.fighters[1].grab == null and lab.simulation.fighters[2].percent == 0, "finite whiff with no damage")
    await capture(lab)
    # A third real actor/source strike hits an already-held caster. All actors
    # still advance exactly once per physics frame through the real Match.
    var third = lab.Actor.new()
    third.profile = lab.Pilot
    lab.add_child(third)
    lab.simulation.register_actor(3, third)
    third.position = Vector3(-1.1, .02, 0)
    for i in range(20): await tick(lab)
    key(KEY_K, true)
    await physics_frame
    var frames := {1: lab.sources[0].sample(lab.simulation.tick), 2: lab.sources[1].sample(lab.simulation.tick)}
    frames[3] = frames[2]
    lab.simulation.simulate(frames)
    lab._sync_visuals()
    key(KEY_K, false)
    check(lab.simulation.fighters[1].percent == 8, "incoming physical K real strike damages held caster")
    check(lab.simulation.fighters[1].grab == null and lab.simulation.fighters[2].caught_by == 0, "incoming hit breaks matching relation")
    check(lab.imported_visuals[0].animation_player.assigned_animation == "Hit", "incoming hit restores Hit immediately")
    check(lab.imported_visuals[1].animation_player.assigned_animation != "Electrocution" and lab.grab_visuals.is_empty(), "incoming hit clears victim and arcs")
    third.free()
    await capture(lab)
    var arc: Node = lab.grab_visuals.values()[0]
    var weak_arc: WeakRef = weakref(arc)
    current_scene = lab
    lab.back_to_movement()
    await process_frame
    await process_frame
    check(weak_arc.get_ref() == null, "navigation destroys live hold arcs")
    if current_scene != null: current_scene.free()
    if is_instance_valid(lab): lab.free()
    if failures == 0: print("PASS: grab lab whiff physical incoming strike relation break navigation")
    quit(1 if failures else 0)
