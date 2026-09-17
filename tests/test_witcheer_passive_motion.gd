extends SceneTree
# Regression: ordinary air/shield must not reset and pause Run frame zero.
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    print(("PASS: " if ok else "FAIL: ") + message)
    if not ok: failures += 1
func pose(skeleton: Skeleton3D) -> Array:
    var result: Array = []
    for i in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose_rotation(i))
    return result
func run():
    root.unfocusable = true
    var fighter = load("res://scripts/fighter.gd").new()
    fighter.character_id = "witcheer"
    root.add_child(fighter)
    fighter.set_physics_process(false)
    var visual = fighter.get_node("VisualRoot/WitcheerVisual")
    var player: AnimationPlayer = visual.animation_player
    var skeleton: Skeleton3D = visual.model.find_children("*", "Skeleton3D", true, false)[0]
    for facing in [-1.0, 1.0]:
        for state in [["rise", false, Vector3(0,6,0), false], ["fall", false, Vector3(0,-6,0), false], ["shield", true, Vector3.ZERO, true], ["air shield", false, Vector3(0,-2,0), true]]:
            visual.sync_pose(state[1], state[2], false, state[3], facing)
            player.advance(0.0)
            var first := pose(skeleton)
            var time := player.current_animation_position
            for tick in 30:
                visual.sync_pose(state[1], state[2], false, state[3], facing)
                player.advance(1.0/60.0)
                if tick == 14: first = pose(skeleton)
            var change := 0.0
            for i in skeleton.get_bone_count():
                var q: Quaternion = skeleton.get_bone_pose_rotation(i)
                change = maxf(change, (Vector3(first[i].x, first[i].y, first[i].z) - Vector3(q.x,q.y,q.z)).length())
            var label := str(state[0]) + " facing " + str(facing)
            check(player.is_playing() and player.assigned_animation != "Run", label + " uses moving passive pose, not held Run")
            check(absf(fposmod(player.current_animation_position-time,3.0)-0.325)<0.002, label + " gentle 0.65x clock advances across repeated sync and wrap")
            # Detect real skeletal change, not an artistic minimum angular speed:
            # the approved idle slows naturally near its sway turnaround.
            check(change > 0.001, label + " actual skeleton moves")
            check(is_equal_approx(visual.model.rotation.y, facing * PI/2) and visual.scale.x > 0, label + " yaw facing")
            check(fighter.witcheer_clip.is_empty() and fighter.attack_cooldown == 0 and not fighter.witcheer_absorbing and not fighter.recovery_spent and not visual.accent.visible, label + " no gameplay payload")
    fighter.queue_free()
    await process_frame
    print("PASSIVE MOTION failures=", failures)
    quit(1 if failures else 0)
