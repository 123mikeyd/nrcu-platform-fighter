extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var f = F.new()
    f.character_id = "turbofit"
    root.add_child(f)
    f.set_physics_process(false)
    var target = F.new()
    target.player_index = 3
    root.add_child(target)
    target.set_physics_process(false)
    var v = f.get_node("VisualRoot/TurboFitVisual")
    var body: CollisionShape3D
    for node in target.get_children():
        if node is CollisionShape3D: body = node
    check(is_equal_approx(body.shape.radius, 0.55) and is_equal_approx(body.shape.height, 1.8) and is_equal_approx(body.position.y, 0.9), "hurtbody contract actual capsule")
    for facing in [1, -1]:
        for time in [0.1666666667, 0.1833333333, 0.2]:
            f.reset_fighter(Vector3(0, 3, 0), true)
            f.basic_attack(Vector2(facing, 0), true)
            f.turbofit_attack_elapsed = time
            var volume: Dictionary = v.air_side_kick_volume(time, 0.5, facing)
            var center: Vector3 = volume.center
            target.reset_fighter(center - Vector3(0, 0.9, 0), true)
            f._query_air_side_kick()
            f._query_air_side_kick()
            check(target.damage_percent == 14, "once-only contact at active sample both yaw facings")
            check(is_equal_approx(v.animation_player.current_animation_position, time), "no idle/renderer-dependent pose delay")
            check(f._air_kick_targets.size() == 1, "target latch per activation")
    for mode in ["startup", "recovery", "above", "depth", "boundary_out", "boundary_in", "shield", "hit", "stock", "reset", "disabled"]:
        f.reset_fighter(Vector3(0, 3, 0), true)
        f.basic_attack(Vector2.RIGHT, true)
        f.turbofit_attack_elapsed = F.AIR_KICK_ACTIVE_START
        var volume: Dictionary = v.air_side_kick_volume(f.turbofit_attack_elapsed, 0.5, 1)
        target.reset_fighter(volume.center - Vector3(0, 0.9, 0), true)
        match mode:
            "startup": f.turbofit_attack_elapsed = F.AIR_KICK_ACTIVE_START - 0.001
            "recovery": f.turbofit_attack_elapsed = F.AIR_KICK_ACTIVE_END + 0.001
            "above": target.position.y += 2.0
            "depth": target.position.z += 1.5
            "boundary_out": target.position.x += 0.55 + F.AIR_KICK_RADIUS + 0.002
            "boundary_in": target.position.x += 0.55 + F.AIR_KICK_RADIUS - 0.002
            "shield": target.shielding = true
            "hit": f.receive_hit(1, Vector3.UP, 1)
            "stock": f.lose_stock()
            "reset": f.reset_fighter(Vector3(0, 3, 0), true)
            "disabled": f.controls_enabled = false
        f._query_air_side_kick()
        var expected := 4.9 if mode == "shield" else (14.0 if mode == "boundary_in" else 0.0)
        check(is_equal_approx(target.damage_percent, expected), mode + " geometry/lifecycle guard")
    var second = F.new()
    second.character_id = "ggb"
    root.add_child(second)
    second.set_physics_process(false)
    f.reset_fighter(Vector3(0, 3, 0), true)
    f.basic_attack(Vector2.RIGHT, true)
    f.turbofit_attack_elapsed = F.AIR_KICK_ACTIVE_START
    var multi: Dictionary = v.air_side_kick_volume(f.turbofit_attack_elapsed, 0.5, 1)
    target.reset_fighter(multi.center - Vector3(0, 0.9, 0), true)
    second.reset_fighter(target.position, true)
    f._query_air_side_kick()
    f._query_air_side_kick()
    check(target.damage_percent == 14 and second.damage_percent == 14 and f._air_kick_targets.size() == 2, "each opponent once, not one opponent per attack")
    f.receive_hit(1, Vector3.UP, 1)
    check(f._air_kick_targets.is_empty(), "interruption clears contacted targets")
    second.queue_free()
    # Transform the real collider, not an invented feet-centered body.
    f.reset_fighter(Vector3(0, 3, 0), true)
    f.basic_attack(Vector2.RIGHT, true)
    f.turbofit_attack_elapsed = F.AIR_KICK_ACTIVE_START
    var volume: Dictionary = v.air_side_kick_volume(f.turbofit_attack_elapsed, 0.5, 1)
    target.reset_fighter(Vector3(5, 3, 0), true)
    body.position = target.to_local(volume.center)
    body.rotation.z = PI / 2
    body.scale = Vector3.ONE * 0.75
    f._query_air_side_kick()
    check(target.damage_percent == 14, "translated rotated scaled capsule is queried at actual world transform")
    var before: Dictionary = v.air_side_kick_volume(F.AIR_KICK_ACTIVE_START, 0.5, 1)
    v.scale *= 1.5
    var after: Dictionary = v.air_side_kick_volume(F.AIR_KICK_ACTIVE_START, 0.5, 1)
    check((after.center - f.global_position).distance_to((before.center - f.global_position) * 1.5) < 0.0001 and is_equal_approx(after.scale_factor, 1.5), "foot world position and compact radius follow visual scaling")
    f.queue_free()
    target.queue_free()
    await process_frame
    if failures == 0: print("PASS AirSideKick compact sphere/capsule geometry, active boundaries, recovery/above/depth misses, once-only, yaw/scale, shield and lifecycle")
    quit(1 if failures else 0)
