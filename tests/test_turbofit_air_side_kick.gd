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
    var v = f.get_node("VisualRoot/TurboFitVisual")
    check(v.animation_player.has_animation("AirSideKick"), "approved 36-51 AirSideKick installed")
    for aim in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT]:
        f.reset_fighter(Vector3(0, 3, 0), true)
        f.basic_attack(aim, true)
        check(f.turbofit_attack_clip == "AirSideKick", "ONLY airborne neutral/horizontal basic selects side kick")
    if not v.animation_player.has_animation("AirSideKick") or f.turbofit_attack_clip != "AirSideKick":
        f.queue_free()
        await process_frame
        quit(1)
        return
    var target = F.new()
    target.character_id = "teknium"
    root.add_child(target)
    target.set_physics_process(false)
    target.position = Vector3(1.2, 3, 0)
    var origin: Vector3 = f.position
    var timing: Dictionary = f.turbofit_attack_timings.AirSideKick
    check(is_equal_approx(float(timing.duration), 0.5), "exact 15 intervals at 30 FPS, no retiming")
    check(is_equal_approx(v.animation_player.get_animation("AirSideKick").length, 0.5), "inclusive 36-51 source duration")
    f._tick_character_move(F.AIR_KICK_ACTIVE_START - 0.001)
    f._query_air_side_kick()
    check(target.damage_percent == 0, "no damage before sampled extension")
    f._tick_character_move(0.001)
    f._update_move_visuals()
    f._query_air_side_kick()
    check(target.damage_percent == 14, "side kick hits forward at sampled extension")
    check(is_equal_approx(v.animation_player.current_animation_position, F.AIR_KICK_ACTIVE_START), "pose clock and hit clock agree")
    f._tick_character_move(0.1)
    f._query_air_side_kick()
    check(target.damage_percent == 14, "one hit only")
    check(f.position == origin, "animation never translates controller")
    f.reset_fighter(origin, true)
    f.basic_attack(Vector2.LEFT, true)
    f.facing = 1
    f._tick_character_move(0.01)
    f._update_move_visuals()
    check(f.facing == -1 and is_equal_approx(v.model.rotation.y, -PI/2), "attack-facing lock uses yaw, no mirrored skeleton")
    check(f.get_node("VisualRoot").scale == Vector3.ONE, "positive skeleton scale")
    check(f.get_node_or_null("VisualRoot/Guitar") == null, "no guitar prop")
    for aim in [Vector2.UP, Vector2.DOWN, Vector2(1, -1), Vector2(-1, 1)]:
        f.reset_fighter(origin, true)
        f.basic_attack(aim, true)
        f._update_move_visuals()
        if aim.y < 0:
            check(f.turbofit_attack_clip.is_empty() and v.current_clip == "MeleeBackhand", "aerial up retains fallback, including diagonals")
        else:
            check(f.turbofit_attack_clip == "AirDownKick" and v.current_clip == "AirDownKick", "aerial down uses newly approved down kick, not side kick")
    for aim in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT]:
        f.reset_fighter(Vector3.ZERO, true)
        f.basic_attack(aim, false)
        f._update_move_visuals()
        check(f.turbofit_attack_clip.is_empty() and v.current_clip == "MeleeHorizontal", "grounded F unchanged")
    f.reset_fighter(Vector3.ZERO, true)
    f.basic_attack(Vector2.DOWN, false)
    check(f.turbofit_attack_clip == "GoalkeeperKick", "grounded down kick unchanged")
    for cancellation in ["hit", "stock", "reset", "disabled"]:
        f.reset_fighter(origin, true)
        target.damage_percent = 0
        f.basic_attack(Vector2.RIGHT, true)
        match cancellation:
            "hit": f.receive_hit(1, Vector3.UP, 1)
            "stock": f.lose_stock()
            "reset": f.reset_fighter(origin, true)
            "disabled": f.controls_enabled = false
        f._tick_character_move(1)
        check(f.turbofit_attack_clip.is_empty() and target.damage_percent == 0, cancellation + " cancels pending side kick")
    f.queue_free()
    target.queue_free()
    await process_frame
    if failures == 0: print("PASS TurboFit airborne side-kick routing, exact duration, impact clock, once-only hit, facing, controller travel and lifecycle")
    quit(1 if failures else 0)
