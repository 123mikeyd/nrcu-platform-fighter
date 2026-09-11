extends SceneTree

const EXPECTED_CLIPS := ["Idle", "Run", "Walk", "GoalkeeperKick", "AirSideKick", "FallLoop", "Landing", "Jump", "BlockIdle", "MeleeBackhand", "MeleeHorizontal", "HitReactRight", "TwoHandCombo"]

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var path := "res://assets/turbofit/turbofit_animations.glb"
    if not ResourceLoader.exists(path):
        push_error("FAIL: TurboFit animation asset missing")
        quit(1)
        return
    var model = load(path).instantiate()
    root.add_child(model)
    var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
    var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
    var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
    if players.size() != 1 or skeletons.size() != 1 or meshes.is_empty():
        push_error("FAIL: TurboFit asset needs one animation player, one skeleton, and a mesh")
        quit(1)
        return
    var player: AnimationPlayer = players[0]
    if player.has_animation("KneeAttack"):
        push_error("FAIL: user-rejected KneeAttack must not be installed")
        quit(1)
        return
    for clip in EXPECTED_CLIPS:
        if not player.has_animation(clip):
            push_error("FAIL: TurboFit clip missing: " + clip)
            quit(1)
            return
    if skeletons[0].get_bone_count() != 33:
        push_error("FAIL: TurboFit 33-bone animation contract changed")
        quit(1)
        return
    var material = meshes[0].get_active_material(0)
    if material == null or material.albedo_texture == null:
        push_error("FAIL: TurboFit original 4096 base-color texture missing")
        quit(1)
        return
    var texture_size: Vector2i = material.albedo_texture.get_size()
    if texture_size != Vector2i(4096, 4096):
        push_error("FAIL: TurboFit base-color texture dimensions changed")
        quit(1)
        return
    var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/turbofit/new_motion_manifest.json"))
    var skeleton: Skeleton3D = skeletons[0]
    var hips := -1
    for i in skeleton.get_bone_count():
        if skeleton.get_bone_name(i).ends_with("Hips"): hips = i
    if hips < 0:
        push_error("FAIL: missing hips")
        quit(1)
        return
    for clip in manifest.clips:
        if absf(player.get_animation(clip).length - float(manifest.clips[clip].duration_seconds)) > 0.002:
            push_error("FAIL: source duration mismatch " + clip)
            quit(1)
            return
        player.play(clip)
        var initial := Vector3.ZERO
        for sample in range(21):
            player.seek(player.get_animation(clip).length * sample / 20.0, true)
            skeleton.force_update_all_bone_transforms()
            var pos := skeleton.global_transform * skeleton.get_bone_global_pose(hips).origin
            if sample == 0: initial = pos
            if absf(pos.x - initial.x) > 0.001 or absf(pos.z - initial.z) > 0.001 or (clip in ["FallLoop", "AirSideKick"] and absf(pos.y - initial.y) > 0.001):
                push_error("FAIL: root travel in " + clip + " sample " + str(sample) + " initial " + str(initial) + " now " + str(pos))
                quit(1)
                return
    if int(manifest.clips.GoalkeeperKick.source_frames[0]) != 40 or int(manifest.clips.GoalkeeperKick.source_frames[1]) != 99 or int(manifest.clips.GoalkeeperKick.output_frames) != 60:
        push_error("FAIL: approved kick must preserve 40-99 inclusive")
        quit(1)
        return
    if int(manifest.clips.AirSideKick.source_frames[0]) != 36 or int(manifest.clips.AirSideKick.source_frames[1]) != 51 or int(manifest.clips.AirSideKick.output_frames) != 16:
        push_error("FAIL: mid-air side kick must preserve 36-51 inclusive")
        quit(1)
        return
    print("PASS: TurboFit 4096 texture, 33-bone rig, 13 clips, exact 40-99 goalkeeper and 36-51 air side kick, six in-place added clips; rejected knee absent")
    model.queue_free()
    quit(0)
