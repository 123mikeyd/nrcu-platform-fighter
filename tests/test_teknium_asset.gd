extends SceneTree

func _initialize() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> bool:
    if not value:
        push_error("FAIL: " + message)
        quit(1)
    return value

func run() -> void:
    var path := "res://assets/teknium/teknium_animations.glb"
    if not check(ResourceLoader.exists(path), "Teknium textured animation asset missing"): return
    var model = load(path).instantiate()
    root.add_child(model)
    var players = model.find_children("*", "AnimationPlayer", true, false)
    var skeletons = model.find_children("*", "Skeleton3D", true, false)
    var meshes = model.find_children("*", "MeshInstance3D", true, false)
    if not check(players.size() == 1 and skeletons.size() == 1 and meshes.size() == 1, "one master mesh/rig/player only"): return
    if not check(skeletons[0].get_bone_count() == 24, "original 24-bone Teknium rig"): return
    var player: AnimationPlayer = players[0]
    for clip in ["Idle", "Walk", "Run", "Projectile", "RaiseWall", "MageSpell", "Block", "Punch", "Kick", "Hit"]:
        if not check(player.has_animation(clip), "missing Teknium clip " + clip): return
    var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/teknium/manifest.json"))
    if not check(manifest.get("orange_lens_pixels", 0) > 0, "orange lens derivative treatment recorded"): return
    for clip in manifest.clips:
        if not check(absf(player.get_animation(clip).length - float(manifest.clips[clip].seconds)) < 0.002, "exact source duration " + clip): return
    var material = meshes[0].get_active_material(0)
    if not check(material.albedo_texture != null and material.albedo_texture.get_size() == Vector2(4096, 4096), "original packed 4096 texture"): return
    var skeleton: Skeleton3D = skeletons[0]
    player.play("Run")
    player.seek(0.0, true)
    var poses: Array = []
    for i in skeleton.get_bone_count(): poses.append(skeleton.get_bone_pose_rotation(i))
    player.seek(player.get_animation("Run").length * 0.45, true)
    var changed := 0
    for i in skeleton.get_bone_count():
        if poses[i].angle_to(skeleton.get_bone_pose_rotation(i)) > 0.03: changed += 1
    if not check(changed >= 4, "Run actually animates multiple bones"): return
    print("PASS: Teknium master mesh, texture, 24 bones, ten clips and moving Run")
    model.queue_free()
    quit(0)
