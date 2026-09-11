extends SceneTree

const FighterScript = preload("res://scripts/fighter.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        printerr("FAIL: " + message)

func has_property(object: Object, property_name: String) -> bool:
    return object.get_property_list().any(func(info: Dictionary): return info.name == property_name)

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var turbo = FighterScript.new()
    turbo.character_id = "turbofit"
    root.add_child(turbo)
    turbo.set_physics_process(false)
    turbo.global_position = Vector3.ZERO
    if not turbo.has_method("_tick_sound_orb") or not has_property(turbo, "sound_orb_time") or not has_property(turbo, "_sound_orb_visual"):
        check(false, "RED: TurboFit Sound Orb lifecycle missing")
        turbo.queue_free()
        await process_frame
        quit(1)
        return

    var airborne_target = FighterScript.new()
    airborne_target.character_id = "teknium"
    root.add_child(airborne_target)
    airborne_target.set_physics_process(false)
    airborne_target.global_position = Vector3(0.5, 0.5, 0.0)
    airborne_target.damage_percent = 37.0

    var far_target = FighterScript.new()
    far_target.character_id = "teknium"
    root.add_child(far_target)
    far_target.set_physics_process(false)
    far_target.global_position = Vector3(2.2, 1.0, 0.0)
    far_target.damage_percent = 21.0

    turbo.start_special(Vector2.DOWN)
    check(turbo.last_move == "SOUND ORB", "down special starts Sound Orb")
    check(turbo.sound_orb_time > 0.0, "Sound Orb has an active utility window")
    check(turbo._sound_orb_visual != null and turbo._sound_orb_visual.visible, "full orb visual is visible")
    if turbo._sound_orb_visual:
        var shell = turbo._sound_orb_visual.get_node_or_null("SphereShell")
        check(shell != null and shell.mesh is SphereMesh, "Sound Orb uses a sphere shell, not a ground circle")
        if shell and shell.mesh is SphereMesh:
            check(is_equal_approx(shell.mesh.height, shell.mesh.radius * 2.0), "sound sphere has equal vertical and horizontal diameter")
            check(shell.mesh.radius <= 1.2, "Sound Orb hugs TurboFit instead of dominating nearby space")
        check(turbo._sound_orb_visual.get_node_or_null("WaveRingX") != null and turbo._sound_orb_visual.get_node_or_null("WaveRingY") != null and turbo._sound_orb_visual.get_node_or_null("WaveRingZ") != null, "three-dimensional sound-wave rings surround TurboFit")
    check(airborne_target.damage_percent == 37.0, "Sound Orb deals zero damage")
    check(airborne_target.velocity.length() > 0.0 and airborne_target.velocity.x > 0.0 and airborne_target.velocity.y > 0.0, "airborne enemy is pushed radially away")
    check(far_target.damage_percent == 21.0 and far_target.velocity == Vector3.ZERO, "enemy outside orb is untouched")
    var first_push: Vector3 = airborne_target.velocity
    turbo._tick_sound_orb(0.05)
    check(airborne_target.velocity.is_equal_approx(first_push), "each enemy is pushed only once per orb")

    var hostile_projectile = ProjectileScript.new()
    hostile_projectile.source = airborne_target
    hostile_projectile.direction = -1.0
    root.add_child(hostile_projectile)
    hostile_projectile.set_physics_process(false)
    hostile_projectile.global_position = Vector3(0.8, 1.0, 0.0)
    turbo._tick_sound_orb(0.05)
    check(hostile_projectile.source == turbo, "Sound Orb reflects hostile projectiles back to TurboFit's ownership")
    check(hostile_projectile.direction == 1.0 and not hostile_projectile.is_queued_for_deletion(), "reflected projectile reverses away instead of being destroyed")

    turbo._tick_sound_orb(turbo.SOUND_ORB_DURATION)
    check(turbo.sound_orb_time == 0.0 and not turbo._sound_orb_visual.visible, "Sound Orb expires and hides cleanly")
    turbo.reset_fighter(Vector3.ZERO, true)
    check(turbo.sound_orb_time == 0.0, "reset clears Sound Orb state")

    for node in [hostile_projectile, far_target, airborne_target, turbo]:
        if is_instance_valid(node):
            node.queue_free()
    await process_frame
    if failures == 0:
        print("PASS TurboFit Sound Orb utility")
    quit(1 if failures else 0)
