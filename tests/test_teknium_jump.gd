extends SceneTree
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> bool:
    if not ok:
        push_error("FAIL: " + message)
        quit(1)
    return ok
func run() -> void:
    var fighter = load("res://scripts/fighter.gd").new()
    fighter.character_id = "teknium"
    root.add_child(fighter)
    fighter.set_physics_process(false)
    var v = fighter.get_node("VisualRoot/TekniumVisual")
    if not check(v.animation_player.has_animation("Jump"), "approved Teknium jump installed"): return
    var a: Animation = v.animation_player.get_animation("Jump")
    if not check(absf(a.length - 43.0/30.0) < 0.0001 and a.loop_mode == Animation.LOOP_NONE, "source15-58 original clock, nonloop"): return
    if not check(fighter.try_jump() and v.current_clip == "Jump", "successful jump routes approved clip immediately"): return
    fighter._update_move_visuals(0.4)
    if not check(absf(v.animation_player.current_animation_position - 0.4) < 0.001, "jump source clock advances once"): return
    if not check(fighter.try_jump() and v.animation_player.current_animation_position < 0.001, "double jump restarts same clip"): return
    if not check(not fighter.try_jump(), "third jump remains denied"): return
    fighter._update_move_visuals(0.3)
    if not check(absf(v.animation_player.current_animation_position - 0.3) < 0.001, "denied jump does not restart"): return
    fighter.velocity.y = -3
    fighter._update_move_visuals(3.0)
    if not check(v.current_clip == "Jump" and absf(v.animation_player.current_animation_position - a.length) < 0.001, "fall holds last approved pose without looping"): return
    v.sync_pose(true, Vector3.ZERO, false, false, "", 1, 0)
    if not check(v.current_clip == "Idle", "ground contact restores idle"): return
    fighter.reset_air_resources()
    fighter.try_jump()
    fighter._update_move_visuals(0.2)
    fighter.basic_attack(Vector2.RIGHT, true)
    fighter._update_move_visuals()
    if not check(v.current_clip == "Punch", "air attack priority over jump"): return
    fighter.attack_cooldown = 0
    fighter._update_move_visuals(0.1)
    if not check(v.current_clip == "Jump" and v.jump_elapsed > 0.29, "attack recovery resumes episode, no restart"): return
    fighter.receive_hit(3, Vector3.UP, 2)
    if not check(v.current_clip == "Hit", "hit interrupts jump"): return
    fighter.hitstun = 0
    fighter._update_move_visuals()
    var clock: float = v.jump_elapsed
    fighter.freeze_remaining = 0.5
    fighter._update_move_visuals(0.2)
    if not check(v.jump_elapsed == clock and not v.animation_player.is_playing() and not fighter.try_jump(), "freeze locks pose, clock and jump input"): return
    fighter._thaw()
    fighter._update_move_visuals(0.1)
    if not check(v.current_clip == "Jump" and absf(v.jump_elapsed - clock - 0.1) < 0.001, "thaw resumes clock"): return
    fighter.lose_stock()
    if not check(not v.jump_active and v.current_clip == "Idle", "stock loss clears jump episode"): return
    fighter.reset_fighter(Vector3.ZERO, true)
    fighter.try_jump()
    fighter.controls_enabled = false
    fighter._update_move_visuals()
    if not check(not v.jump_active and v.current_clip == "Idle", "setup/winner stops jump"): return
    fighter.controls_enabled = true
    fighter.reset_fighter(Vector3.ZERO, true)
    # Enter actual airborne presentation before directly seeking source samples;
    # reset_fighter intentionally selects the now floor-corrected Idle placement.
    if not check(fighter.try_jump() and is_zero_approx(v.position.y), "source probe uses unchanged airborne origin"): return
    v.model.rotation.y = 0
    var sk: Skeleton3D = v.model.find_children("*", "Skeleton3D", true, false)[0]
    var samples = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/teknium_jump_source_samples.json"))
    var max_error := 0.0
    var worst := ""
    var hip_first := Vector3.ZERO
    v.animation_player.play("Jump", 0)
    for row in samples.samples:
        v.animation_player.seek(row.time, true)
        sk.force_update_all_bone_transforms()
        for bone in row.bones:
            var xyz = row.bones[bone]
            var expected := Vector3(xyz[0], xyz[1], xyz[2])
            var actual: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin / 1.25
            if actual.distance_to(expected) > max_error:
                max_error = actual.distance_to(expected)
                worst = str(row.source_frame) + ":" + bone + " actual=" + str(actual) + " expected=" + str(expected)
            if bone == "Hips":
                if row.source_frame == 15: hip_first = actual
                if not check(actual.distance_to(hip_first) < 0.00001, "no root travel XYZ or double vertical arc"): return
    if not check(max_error < 0.0001, "all 44 imported poses match approved anchored source, error=" + str(max_error) + " " + worst): return
    print("PASS: Teknium jump source15-58, double restart, denied jump, fall hold, grounded recovery, attack/hit/freeze/thaw/stock/setup/reset; 1056 source bone positions max error=", max_error)
    fighter.queue_free()
    await process_frame
    quit(0)
