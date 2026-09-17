extends "res://tests/test_core_recovery_lab_source.gd"
# Characterization of the new integration against untouched imported assets.
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    var reference = MODEL.instantiate()
    root.add_child(reference)
    reference.scale = Vector3.ONE * 1.25
    var player: AnimationPlayer = reference.find_children("*", "AnimationPlayer", true, false)[0]
    var skeleton: Skeleton3D = reference.find_children("*", "Skeleton3D", true, false)[0]
    player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    var originals := {}
    for clip in ["Punch", "Kick"]: originals[clip] = fingerprint(player.get_animation(clip))
    for slot in range(2):
        for airborne in [false, true]:
            for down in [false, true]:
                lab.reset_lab()
                for i in range(40): await tick(lab)
                lab.actors[1 - slot].position.x = 10 if slot == 0 else -10
                if airborne:
                    var jump := KEY_SPACE if slot == 0 else KEY_ENTER
                    key(jump, true)
                    for i in range(12): await tick(lab)
                    key(jump, false)
                    check(not lab.actors[slot].runtime.grounded, "source oracle begins with real physical jump")
                var vertical := (KEY_S if down else KEY_W) if slot == 0 else (KEY_DOWN if down else KEY_UP)
                var horizontal := KEY_D if slot == 0 else KEY_LEFT
                var attack := KEY_F if slot == 0 else KEY_K
                for code in [vertical, horizontal, attack]: key(code, true)
                await tick(lab)
                for code in [vertical, horizontal, attack]: key(code, false)
                var visual = lab.imported_visuals[slot]
                var clip := "Kick" if down else "Punch"
                var animation: Animation = player.get_animation(clip)
                var transition: int = visual.state.transition
                var plays: int = visual.play_count
                for age in range(2, 21):
                    await tick(lab)
                    if age not in [6, 12, 20]: continue
                    check(visual.state.output.clip == clip, "source clip persists through committed cooldown")
                    check(visual.state.transition == transition and visual.play_count == plays, "no repeated playback or transition")
                    player.play(clip, 0)
                    player.seek(animation.length * minf(age / 60.0 / .32, 1.0), true)
                    skeleton.force_update_all_bone_transforms()
                    reference.rotation.y = (1 if slot == 0 else -1) * PI / 2.0
                    var offset := (-.038 if down else -.106) if lab.actors[slot].runtime.grounded else 0.0
                    reference.position = lab.actors[slot].position + Vector3(0, offset, 0)
                    check(is_equal_approx(visual.model.rotation.y, reference.rotation.y), "actual imported facing mirrors source")
                    for bone in range(skeleton.get_bone_count()):
                        check(visual.skeleton.get_bone_pose(bone).is_equal_approx(skeleton.get_bone_pose(bone)), "actual directional skeleton equals source after blend")
                    for bone_name in ["RightHand", "LeftFoot"]:
                        var bone := skeleton.find_bone(bone_name)
                        var expected: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
                        var actual: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(bone).origin
                        check(actual.distance_to(expected) < .002, "both-facing world-space source placement")
                await tick(lab)
                check(lab.simulation.fighters[slot + 1].activation_id == "" and visual.state.output.state != "strike", "ready gate retires episode")
    for clip in originals:
        check(fingerprint(player.get_animation(clip)) == originals[clip], "immutable source keys, duration, step and loop " + clip)
    reference.free()
    lab.free()
    if failures == 0: print("PASS: directional actual source skeleton both facings ground/real jump clock endpoint no restart immutable resources")
    quit(1 if failures else 0)
