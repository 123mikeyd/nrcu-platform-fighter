extends SceneTree

const FighterScript = preload("res://scripts/fighter.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        printerr("FAIL: " + message)

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var turbo = FighterScript.new()
    turbo.character_id = "turbofit"
    root.add_child(turbo)
    turbo.set_physics_process(false)
    var visual = turbo._visual_root.get_node_or_null("TurboFitVisual")
    check(visual != null, "TurboFit uses imported animated mesh")
    check(turbo._visual_root.get_node_or_null("Guitar") == null, "primitive guitar placeholder remains absent")
    if visual:
        check(visual.animation_player != null, "real TurboFit AnimationPlayer")
        var imported_mesh = visual.model.find_children("*", "MeshInstance3D", true, false)[0]
        var material = imported_mesh.get_active_material(0)
        check(material.albedo_texture != null and material.emission_enabled and material.emission_texture == material.albedo_texture and material.emission_energy_multiplier <= 0.35, "dark original texture gets restrained non-flashing readability lift")
        visual.sync_pose(true, Vector3.ZERO, false, false, "", Vector3.RIGHT, 1.0, 0.0)
        check(visual.current_clip == "Idle", "neutral uses supplied Idle")
        visual.sync_pose(true, Vector3(6.0, 0.0, 0.0), false, false, "", Vector3.RIGHT, 1.0, 0.1)
        check(visual.current_clip == "Run", "ground movement uses exact-contract supplied Slow Run, not old retarget")
        visual.sync_pose(false, Vector3(0, 5, 0), false, false, "", Vector3.RIGHT, 1.0, 0.1)
        check(visual.current_clip == "Jump", "airborne state uses supplied Jump")
        visual.sync_pose(true, Vector3.ZERO, false, true, "", Vector3.RIGHT, 1.0, 0.1)
        check(visual.current_clip == "BlockIdle", "shield uses supplied Block Idle")
        visual.sync_pose(true, Vector3.ZERO, true, false, "", Vector3.RIGHT, 1.0, 0.1)
        check(visual.current_clip == "HitReactRight", "hitstun uses supplied reaction")
        visual.sync_pose(true, Vector3.ZERO, false, false, "GUITAR SWING", Vector3.RIGHT, 1.0, 0.1)
        check(visual.current_clip == "MeleeHorizontal", "side guitar attack uses horizontal melee")
        visual.sync_pose(true, Vector3.ZERO, false, false, "GUITAR SWING", Vector3.UP, 1.0, 0.1)
        check(visual.current_clip == "MeleeBackhand", "vertical guitar attack uses backhand melee")
        visual.sync_pose(true, Vector3.ZERO, false, false, "POWER CHORD", Vector3.RIGHT, 1.0, 0.1)
        check(visual.current_clip == "TwoHandCombo", "power chord uses supplied two-hand combo")
        visual.sync_pose(true, Vector3.ZERO, false, false, "", Vector3.RIGHT, -1.0, 0.1)
        check(is_equal_approx(visual.model.rotation.y, -PI / 2.0), "left facing uses yaw, not negative skeleton scale")
    turbo.queue_free()
    await process_frame
    if failures == 0:
        print("PASS TurboFit visual integration")
    quit(1 if failures else 0)
