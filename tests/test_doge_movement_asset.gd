extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var path := "res://assets/doge_man/doge_movement.glb"
    if not ResourceLoader.exists(path):
        push_error("FAIL: movement asset missing")
        quit(1)
        return
    var model = load(path).instantiate()
    root.add_child(model)
    var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
    var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
    var clips := ["Launch", "Dive", "Brake", "Landing", "Idle", "Walk", "Run", "FallStart", "FallLoop"]
    for clip in clips:
        if not player.has_animation(clip):
            push_error("FAIL: missing " + clip)
            quit(1)
            return
        player.play(clip)
        var initial := Vector3.ZERO
        for i in range(11):
            player.seek(player.get_animation(clip).length * i / 10.0, true)
            skeleton.force_update_all_bone_transforms()
            var pos := skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
            if i == 0: initial = pos
            if absf(pos.x - initial.x) > 0.001 or absf(pos.z - initial.z) > 0.001 or (clip in ["FallStart", "FallLoop"] and absf(pos.y - initial.y) > 0.001):
                push_error("FAIL: imported root travel " + clip)
                quit(1)
                return
    if absf(player.get_animation("FallStart").length - 0.75) > 0.002:
        push_error("FAIL: FallStart must preserve frame1-19 span at24FPS")
        quit(1)
        return
    var original = load("res://assets/doge_man/doge_torpedo.glb").instantiate()
    root.add_child(original)
    var old_player: AnimationPlayer = original.find_children("*", "AnimationPlayer", true, false)[0]
    var old_skeleton: Skeleton3D = original.find_children("*", "Skeleton3D", true, false)[0]
    for clip in ["Launch", "Dive", "Brake", "Landing"]:
        player.play(clip)
        old_player.play(clip)
        for i in range(11):
            var t := player.get_animation(clip).length * i / 10.0
            player.seek(t, true)
            old_player.seek(t, true)
            skeleton.force_update_all_bone_transforms()
            old_skeleton.force_update_all_bone_transforms()
            for bone in range(skeleton.get_bone_count()):
                var name := skeleton.get_bone_name(bone)
                if not skeleton.get_bone_pose(bone).is_equal_approx(old_skeleton.get_bone_pose(old_skeleton.find_bone(name))):
                    push_error("FAIL: approved torpedo pose changed " + clip + ":" + name)
                    quit(1)
                    return
    original.queue_free()
    print("PASS: nine clips, FallStart 1-19, no root travel, approved torpedo poses unchanged")
    model.queue_free()
    quit(0)
