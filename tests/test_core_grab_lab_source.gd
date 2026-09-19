extends "res://tests/test_core_recovery_lab_source.gd"
func compare(visual, reference, player, skeleton, clip: String, seconds: float, direction: float) -> void:
    skeleton.reset_bone_poses()
    player.play(clip, 0)
    player.seek(maxf(0, seconds), true)
    skeleton.force_update_all_bone_transforms()
    reference.rotation.y = direction * PI / 2
    reference.position = visual.get_parent().position
    check(visual.position == Vector3.ZERO, "magic placement zero, no jitter")
    for bone in range(skeleton.get_bone_count()):
        check(visual.skeleton.get_bone_pose(bone).is_equal_approx(skeleton.get_bone_pose(bone)), "imported source skeleton " + clip + " seconds=" + str(seconds) + " bone=" + skeleton.get_bone_name(bone))
    var bone: int = skeleton.find_bone("RightHand")
    var expected: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone) * Vector3(0,19.50612449645996,0)
    var actual: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(bone) * Vector3(0,19.50612449645996,0)
    check(actual.distance_to(expected) < .002, "world hand source facing/placement")
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.set_process(false)
    var reference = MODEL.instantiate()
    root.add_child(reference)
    reference.scale = Vector3.ONE * 1.25
    var player: AnimationPlayer = reference.find_children("*", "AnimationPlayer", true, false)[0]
    var skeleton: Skeleton3D = reference.find_children("*", "Skeleton3D", true, false)[0]
    player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    var originals := {}
    for clip in ["GrabStart", "GrabLoop", "GrabEnd", "Electrocution"]: originals[clip] = fingerprint(player.get_animation(clip))
    for slot in range(2):
        lab.reset_lab()
        for i in range(40): await tick(lab)
        var direction := KEY_D if slot == 0 else KEY_LEFT
        key(direction, true)
        await tick(lab)
        key(direction, false)
        for i in range(12): await tick(lab)
        lab.actors[slot].position.x = 0
        lab.actors[1-slot].position.x = 1.1 if slot == 0 else -1.1
        var special := KEY_G if slot == 0 else KEY_L
        key(special, true)
        for age in range(1, 130):
            await tick(lab)
            if age not in [1, 6, 12, 21, 22, 23, 37, 96, 97, 109, 110, 129]: continue
            var seconds := age / 60.0
            var clip := "GrabStart"
            if age < 22: seconds = seconds * (13.0/24.0) / .2 if seconds <= .2 else 13.0/24.0 + seconds - .2
            elif age < 97:
                clip = "GrabLoop"
                seconds -= .2 + 4.0/24.0
            else:
                clip = "GrabEnd"
                seconds -= .2 + 4.0/24.0 + 1.25
            compare(lab.imported_visuals[slot], reference, player, skeleton, clip, seconds, 1 if slot == 0 else -1)
            if age >= 22 and age < 97:
                compare(lab.imported_visuals[1-slot], reference, player, skeleton, "Electrocution", seconds, lab.simulation.fighters[2-slot].facing)
        key(special, false)
    # Independent immutable hand oracle includes exact clip endpoints, not core bake.
    var oracle = JSON.parse_string(FileAccess.get_file_as_string("res://assets/teknium/magic_source_samples.json"))
    var samples := 0
    var visual = lab.imported_visuals[0]
    for facing in [1.0, -1.0]:
        for clip in ["GrabStart", "GrabLoop", "GrabEnd"]:
            for point in oracle[clip]:
                var seconds: float = (point.frame - oracle[clip][0].frame) / 24.0
                visual.present({"facing": facing, "grab_pose": {"clip": clip, "seconds": seconds}}, lab.simulation.tick)
                var xyz: Array = point.hands.RightHand
                var expected := Vector3(xyz[0]*facing,xyz[1],xyz[2]*facing)
                var actual: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone("RightHand")) * Vector3(0,19.50612449645996,0) - lab.actors[0].global_position
                check(actual.distance_to(expected) < .002, "immutable hand oracle " + clip + str(point.frame))
                samples += 1
    check(samples == 126, "all 63 immutable grab samples both facings")
    for clip in originals: check(originals[clip] == fingerprint(player.get_animation(clip)), "source resource unchanged " + clip)
    reference.free()
    lab.free()
    if failures == 0: print("PASS: grab lab actual skeleton clocks seams both facings immutable 126 oracle comparisons")
    quit(1 if failures else 0)
