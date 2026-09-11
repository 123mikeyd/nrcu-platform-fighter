extends SceneTree
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var path := "res://assets/doge_man/doge_torpedo.glb"
    if not ResourceLoader.exists(path):
        push_error("FAIL: Doge animated asset missing")
        quit(1)
        return
    var model = load(path).instantiate()
    root.add_child(model)
    var players = model.find_children("*", "AnimationPlayer", true, false)
    if players.size() != 1:
        push_error("FAIL: expected one AnimationPlayer")
        quit(1)
        return
    for clip in ["Launch", "Dive", "Brake", "Landing", "Idle"]:
        if not players[0].has_animation(clip):
            push_error("FAIL: missing clip " + clip)
            quit(1)
            return
    var skeletons = model.find_children("*", "Skeleton3D", true, false)
    if skeletons.size() != 1 or skeletons[0].get_bone_count() != 24:
        push_error("FAIL: expected preserved 24-bone skeleton")
        quit(1)
        return
    var skeleton: Skeleton3D = skeletons[0]
    var hips := skeleton.find_bone("Hips")
    var player: AnimationPlayer = players[0]
    for clip in ["Launch", "Dive", "Brake", "Landing"]:
        player.play(clip)
        var initial := Vector3.ZERO
        for i in range(11):
            player.seek(player.get_animation(clip).length * i / 10.0, true)
            skeleton.force_update_all_bone_transforms()
            var pose := skeleton.get_bone_global_pose(hips).origin
            if i == 0:
                initial = pose
            if absf(pose.x - initial.x) > 0.001 or absf(pose.z - initial.z) > 0.001:
                push_error("FAIL: clip contains horizontal root travel: " + clip)
                quit(1)
                return
    print("PASS: imported Doge mesh, five clips, 24 bones, no horizontal root travel")
    model.queue_free()
    quit(0)
