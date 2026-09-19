extends "res://tests/test_core_combat_lab.gd"
const MODEL = preload("res://assets/teknium/teknium_animations.glb")
func fingerprint(animation: Animation) -> int:
    var values: Array = [animation.length, animation.loop_mode, animation.step]
    for track in range(animation.get_track_count()):
        values.append([animation.track_get_path(track), animation.track_get_type(track), animation.track_get_interpolation_type(track)])
        for k in range(animation.track_get_key_count(track)):
            values.append([animation.track_get_key_time(track, k), animation.track_get_key_value(track, k), animation.track_get_key_transition(track, k)])
    return hash(values)
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
    var animation: Animation = player.get_animation("RaiseWall")
    var original := fingerprint(animation)
    for slot in range(2):
        lab.reset_lab()
        for i in range(40): await tick(lab)
        var up := KEY_W if slot == 0 else KEY_UP
        var special := KEY_G if slot == 0 else KEY_L
        var direction := KEY_D if slot == 0 else KEY_LEFT
        key(up, true)
        key(direction, true)
        key(special, true)
        await tick(lab)
        for code in [up, direction, special]: key(code, false)
        var visual = lab.imported_visuals[slot]
        for age in range(2, 24):
            await tick(lab)
            if age not in [6, 12, 23]: continue
            player.play("RaiseWall", 0)
            player.seek(animation.length * age / 39.0, true)
            skeleton.force_update_all_bone_transforms()
            reference.rotation.y = (1 if slot == 0 else -1) * PI / 2.0
            reference.position = lab.actors[slot].position
            check(is_equal_approx(visual.model.rotation.y, reference.rotation.y), "real recovery model faces both keyboard directions")
            for bone in range(skeleton.get_bone_count()):
                check(visual.skeleton.get_bone_pose(bone).is_equal_approx(skeleton.get_bone_pose(bone)), "actual recovery skeleton matches unchanged source sample after blend")
            var hand := skeleton.find_bone("RightHand")
            var expected: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin
            var actual: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(hand).origin
            check(actual.distance_to(expected) < .002, "both-facing world-space skeleton uses original RaiseWall source")
        check(fingerprint(animation) == original, "presentation never mutates source clip keys, loop mode or duration")
    reference.free()
    # Early physical terrain contact: contact lifetime ends, identity does not.
    lab.reset_lab()
    for i in range(40): await tick(lab)
    key(KEY_W, true)
    key(KEY_G, true)
    await tick(lab)
    key(KEY_W, false)
    key(KEY_G, false)
    var visual = lab.imported_visuals[0]
    var transition: int = visual.state.transition
    var id: String = lab.simulation.fighters[1].activation_id
    lab.actors[0].position.y = .01
    lab.actors[0].runtime.velocity.y = -1
    for i in range(3): await tick(lab)
    check(lab.actors[0].runtime.grounded and lab.simulation.fighters[1].recovery == null, "actual terrain collision terminates contact early")
    check(visual.state.output.clip == "RaiseWall" and visual.state.transition == transition and lab.simulation.fighters[1].activation_id == id, "landing retains one continuous cooldown presentation episode")
    check(is_equal_approx(visual.state.output.fraction, 4.0 / 39.0), "landing cannot restart source clock")
    lab.free()
    if failures == 0: print("PASS: recovery lab unchanged RaiseWall actual skeleton both facings and early terrain episode continuity")
    quit(1 if failures else 0)
