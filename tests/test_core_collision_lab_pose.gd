extends "res://tests/test_core_combat_lab.gd"
const Sampler = preload("res://scripts/core/collision/committed_pose_sampler.gd")
func tick(lab) -> void:
    await physics_frame
    # parse_input_event queues keys. Catch-up physics frames can precede the
    # next render/input flush, swallowing a one-tick press/release in this test.
    # Deliver queued physical input before real source sampling, not fake frames.
    Input.flush_buffered_events()
    lab._physics_process(1.0 / 60.0)
func compare_pose(lab, slot: int, sampler) -> void:
    var record: Dictionary = lab.simulation.collision_telemetry(slot+1)
    check(record.get("ok",false),"valid canonical match pose")
    if not record.get("ok",false): return
    var request: Dictionary = record.pose_request.rendering_request
    var visual = lab.imported_visuals[slot]
    var expected: Dictionary = sampler.sample(request.clip,request.source_seconds,request.time_policy)
    check(visual.canonical.output == request,"presenter consumed exact request, no second clock")
    for bone in visual.skeleton.get_bone_count():
        var actual: Transform3D = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(bone)
        var wanted: Transform3D = lab.actors[slot].global_transform * request.modelplacement * expected[visual.skeleton.get_bone_name(bone)]
        check(actual.is_equal_approx(wanted),"actual bone matches canonical " + visual.skeleton.get_bone_name(bone))
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab); lab.set_physics_process(false)
    lab.select_fighter(1,"turbofit")
    lab.set_generated_collision_enabled(true)
    check(lab.imported_visuals[0].has_method("present_canonical") and lab.imported_visuals[1].has_method("present_canonical"),"both presenters accept canonical match request")
    if not lab.imported_visuals[0].has_method("present_canonical") or not lab.imported_visuals[1].has_method("present_canonical"):
        lab.free(); quit(1); return
    check(not lab.imported_visuals[0].model.visible,"invalid reset pose explicitly hidden until commit")
    var samplers := []
    for path in ["teknium","turbofit"]:
        var sampler = Sampler.new()
        var skeleton_path := "Teknium_Master_Armature/Skeleton3D" if path == "teknium" else "TurboFit_Master_Rig/Skeleton3D"
        check(sampler.configure(load("res://assets/%s/%s_animations.glb" % [path,path]),NodePath(skeleton_path),NodePath("AnimationPlayer")) == OK,"independent source sampler")
        samplers.append(sampler)
    for facing in [-1.0,1.0]:
        lab.spawns = {1:Vector3(-4,15,0),2:Vector3(4,15,0)}
        lab.reset_lab()
        for id in [1,2]: lab.simulation.fighters[id].facing = facing
        for i in 5:
            await tick(lab)
            for slot in 2: compare_pose(lab,slot,samplers[slot])
        check(not lab.actors[1].runtime.grounded,"air attack launch prerequisite")
        key(KEY_K,true); await tick(lab)
        check(Input.is_physical_key_pressed(KEY_K),"queued physical attack delivered before sample")
        check(lab.simulation.kit_telemetry(2).basic.clip == "AirSideKick","real air attack committed on input tick")
        key(KEY_K,false)
        for i in 12:
            await tick(lab)
            for slot in 2: compare_pose(lab,slot,samplers[slot])
        check(lab.simulation.collision_telemetry(2).pose_request.clip == "AirSideKick","real physical attack canonical clip")
        lab.set_paused(true)
        var before: Dictionary = lab.imported_visuals[1].canonical.output.duplicate(true)
        for i in 4: await tick(lab)
        check(before == lab.imported_visuals[1].canonical.output,"pause holds request")
        lab.step_once(); await tick(lab)
        check(before != lab.imported_visuals[1].canonical.output,"step advances committed source")
        compare_pose(lab,1,samplers[1])
        lab.set_paused(false)
    # A genuine active hand hit changes post-contact pose on the impact tick.
    lab.spawns = {1:Vector3(0,30,0),2:Vector3(1.1,30,0)}
    lab.reset_lab(); lab.set_hitstop_enabled(true)
    await tick(lab) # Reset intentionally suppresses every action in the first sample.
    key(KEY_D,true); key(KEY_F,true); await tick(lab); key(KEY_F,false); key(KEY_D,false)
    check(not lab.simulation.fighters[1].activation_id.is_empty(),"real physical input accepted")
    check(lab.simulation.fighters[2].percent == 0,"source startup cannot hit")
    var impact_age := -1
    for age in range(1,12): # Punch active acceptance-relative ages 9..11.
        await tick(lab)
        if lab.simulation.fighters[2].percent > 0:
            impact_age = age
            break
    check(impact_age >= 9 and impact_age <= 11,"real input reaches source hand window")
    check(not lab.simulation.events.is_empty() and lab.simulation.events[0].contact_evidence.has("attack_shape"),"independent real hand contact evidence")
    var post: Dictionary = lab.simulation.collision_telemetry(2)
    check(lab.simulation.fighters[2].percent > 0,"real hit prerequisite")
    check(post.pose_request.clip == "HitReactRight" and post.contact_snapshot.pose_request.clip != "HitReactRight","posthit render is not precontact witness")
    compare_pose(lab,1,samplers[1])
    var held: Dictionary = lab.imported_visuals[1].canonical.output.duplicate(true)
    for i in 3:
        await tick(lab); compare_pose(lab,1,samplers[1])
        check(held == lab.imported_visuals[1].canonical.output,"real hitstop holds exact request")
    lab.simulation.set_frozen(2,true)
    await tick(lab)
    check(lab.actors[1].telemetry().status == "frozen","effective frozen status prerequisite")
    var frozen_request: Dictionary = lab.imported_visuals[1].canonical.output.duplicate(true)
    for i in 3:
        await tick(lab); compare_pose(lab,1,samplers[1])
        check(frozen_request == lab.imported_visuals[1].canonical.output,"frozen status keeps canonical bones")
    lab.simulation.set_frozen(2,false)
    lab.simulation.set_enabled(2,false); lab._sync_visuals()
    check(not lab.imported_visuals[1].model.visible,"synchronous disabled invalid sample hides model")
    lab.simulation.set_enabled(2,true); await tick(lab)
    compare_pose(lab,1,samplers[1])
    check(lab.imported_visuals[1].model.visible,"reenabled fresh pose visible")
    lab.spawns = {1:Vector3(-4,.1,0),2:Vector3(4,.1,0)}
    lab.reset_lab()
    for i in 40: await tick(lab)
    check(lab.actors[0].runtime.grounded and lab.actors[1].runtime.grounded,"grounded pose prerequisite")
    key(KEY_E,true); key(KEY_O,true)
    Input.flush_buffered_events()
    await tick(lab)
    for slot in 2: compare_pose(lab,slot,samplers[slot])
    check(lab.imported_visuals[0].canonical.output.clip == "Block" and lab.imported_visuals[1].canonical.output.clip == "BlockIdle","actual physical defense visual bones")
    key(KEY_E,false); key(KEY_O,false)
    lab.set_generated_collision_enabled(false)
    await tick(lab)
    for visual in lab.imported_visuals:
        check(not visual.canonical.active and visual.model.visible,"optout restores legacy renderer")
        check(visual.scale.is_equal_approx(Vector3.ONE*1.25),"legacy scale restored")
    lab.free()
    if not failures: print("PASS: actual imported bones canonical both facings attack pause step posthit hitstop optout")
    quit(1 if failures else 0)
