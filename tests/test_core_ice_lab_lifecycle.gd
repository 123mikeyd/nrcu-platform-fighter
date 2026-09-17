extends "res://tests/test_core_combat_lab.gd"
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.select_fighter(0,"ice_mage")
    lab.select_fighter(1,"turbofit")
    # More separation than immediate bolt impact; Orb sees live shot before ray contact.
    lab.actors[0].position.x = -3
    lab.actors[1].position.x = 3
    for i in range(40): await tick(lab)
    key(KEY_G,true)
    for i in range(12): await tick(lab)
    key(KEY_G,false)
    var shots: Array = lab.simulation.projectile_telemetry()
    check(shots.size()==1,"physical cast emits reflection prerequisite")
    var identity: String = shots[0].activation_id if not shots.is_empty() else ""
    key(KEY_DOWN,true)
    key(KEY_L,true)
    await tick(lab)
    key(KEY_DOWN,false)
    key(KEY_L,false)
    var reflected := false
    for i in range(40):
        await tick(lab)
        shots = lab.simulation.projectile_telemetry()
        if not shots.is_empty() and shots[0].source == 2:
            reflected = true
            check(shots[0].activation_id == identity and shots[0].facing == -1,"reflection retains identity changes owner/facing")
            check(lab.projectile_visuals[identity].get_meta("source")==2,"debug mesh mirrors reflected owner")
            break
    check(reflected,"actual parsed Turbo Orb reflects Frost Bolt")
    for i in range(40): await tick(lab)
    check(lab.simulation.fighters[1].percent==4 and lab.simulation.fighters[2].percent==0,"reflected source receives bolt not defender")
    # Real Ice hit creates actor-local stop; all bone and host clocks remain held.
    lab.select_fighter(1,"ice_mage")
    lab.set_hitstop_enabled(true)
    lab.reset_lab()
    for i in range(40): await tick(lab)
    key(KEY_F,true)
    for i in range(12): await tick(lab)
    key(KEY_F,false)
    check(lab.simulation.fighters[2].percent == 8,"actual Ice basic creates damage hitstop")
    var visual = lab.imported_visuals[0]
    var pose: Array = []
    for b in range(visual.skeleton.get_bone_count()): pose.append(visual.skeleton.get_bone_pose(b))
    var before: Dictionary = visual.output.duplicate(true)
    var accepted_tick: int = lab.actors[0].runtime.tick
    for i in range(4):
        await tick(lab)
        check(lab.actors[0].runtime.tick==accepted_tick and visual.output==before,"real hitstop holds source clock and output")
        for b in range(pose.size()): check(pose[b].is_equal_approx(visual.skeleton.get_bone_pose(b)),"all bones held by committed actor clock")
    await tick(lab)
    check(lab.actors[0].runtime.tick == accepted_tick+1,"actual stop resumes once")
    # Effective finite shield must remain a fallback even with nonempty idle host data.
    lab.set_defense_enabled(true)
    for i in range(40): await tick(lab)
    key(KEY_O,true)
    await tick(lab)
    check(lab.imported_visuals[1].output.identity == "shield","physical Ice P2 shield not erased by idle host presentation")
    key(KEY_O,false)
    lab.free()
    if not failures: print("PASS: real Frost reflection mesh ownership Ice damage hitstop full skeleton and shield")
    quit(1 if failures else 0)
