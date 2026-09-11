extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    if not ResourceLoader.exists("res://assets/doge_man/doge_attacks.glb"):
        push_error("FAIL: attack asset missing")
        quit(1)
        return
    var model = load("res://assets/doge_man/doge_attacks.glb").instantiate()
    root.add_child(model)
    var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
    var timing = JSON.parse_string(FileAccess.get_file_as_string("res://assets/doge_man/attack_timing.json"))
    if not timing is Dictionary:
        push_error("FAIL: missing attack timing manifest")
        quit(1)
        return
    for clip in ["Punch1", "Punch2", "Punch3", "Punch4", "Uppercut"]:
        if not player.has_animation(clip):
            push_error("FAIL: clip missing " + clip)
            quit(1)
            return
        var info: Dictionary = timing.attacks[clip]
        if absf(player.get_animation(clip).length / info.playback_speed - info.duration) > 0.002:
            push_error("FAIL: clip duration does not match combat timing " + clip)
            quit(1)
            return
        if info.impact_time <= 0 or info.impact_time >= info.duration:
            push_error("FAIL: invalid strike event " + clip)
            quit(1)
            return
    var original = load("res://assets/doge_man/doge_movement.glb").instantiate()
    root.add_child(original)
    var old_player: AnimationPlayer = original.find_children("*", "AnimationPlayer", true, false)[0]
    var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
    var old_skeleton: Skeleton3D = original.find_children("*", "Skeleton3D", true, false)[0]
    for clip in ["Idle", "Walk", "Run", "FallStart", "FallLoop", "Launch", "Dive", "Brake", "Landing"]:
        player.play(clip)
        old_player.play(clip)
        for i in range(11):
            var t := old_player.get_animation(clip).length * i / 10.0
            player.seek(t, true)
            old_player.seek(t, true)
            skeleton.force_update_all_bone_transforms()
            old_skeleton.force_update_all_bone_transforms()
            for bone in range(skeleton.get_bone_count()):
                var name := skeleton.get_bone_name(bone)
                if not skeleton.get_bone_pose(bone).is_equal_approx(old_skeleton.get_bone_pose(old_skeleton.find_bone(name))):
                    push_error("FAIL: existing animation changed: " + clip + ":" + name)
                    quit(1)
                    return
    original.queue_free()
    print("PASS: five timed attack clips; all nine prior animations preserved")
    model.queue_free()
    quit(0)
