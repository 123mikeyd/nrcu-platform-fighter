extends SceneTree
const V = preload("res://scripts/doge_visual.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var visual = V.new()
    check(visual.has_method("locomotion_clip"), "presentation selects grounded locomotion from actual speed")
    if visual.has_method("locomotion_clip"):
        check(visual.locomotion_clip(true, Vector3.ZERO, false, 0) == "Idle", "stationary idle")
        check(visual.locomotion_clip(true, Vector3(2, 0, 0), false, 0) == "Walk", "low speed walk")
        check(visual.locomotion_clip(true, Vector3(-7.5, 0, 0), false, 0) == "Run", "high speed run either direction")
        var down := Vector3(0, -3, 0)
        check(visual.locomotion_clip(false, down, false, 0) == "MidairMoves2", "offledge enters approved loop directly")
        check(visual.locomotion_clip(false, down, false, 0.74) == "MidairMoves2", "approved loop persists")
        check(visual.locomotion_clip(false, down, false, 0.011) == "MidairMoves2", "no legacy falling transition")
        check(visual.locomotion_clip(false, down, false, 5) == "MidairMoves2", "loop persists with no floor contact")
        for interruption in ["floor", "upward", "hit/torpedo/menu"]:
            visual.locomotion_clip(interruption == "floor", Vector3.UP if interruption == "upward" else down, interruption == "hit/torpedo/menu", 0)
            check(visual.locomotion_clip(false, down, false, 0) == "MidairMoves2", "approved midair after " + interruption)
            visual.locomotion_clip(false, down, false, 1)
    visual.free()
    var fighter_script = load("res://scripts/fighter.gd")
    var dog = fighter_script.new()
    dog.character_id = "doge_man"
    root.add_child(dog)
    dog.set_physics_process(false)
    var view = dog._visual_root.get_node("DogeVisual")
    dog.velocity = Vector3(2, -3, 0)
    dog._update_move_visuals()
    check(view.current_clip == "MidairMoves2", "fighter forwards airborne descent to approved midair")
    var other = V.new()
    root.add_child(other)
    for clip in ["Idle", "Run", "Walk", "FallStart", "FallLoop"]:
        check(view.animation_player.has_animation(clip), "movement asset contains " + clip)
        if view.animation_player.has_animation(clip):
            var animation = view.animation_player.get_animation(clip)
            check(animation != other.animation_player.get_animation(clip), "per-instance animation " + clip)
            check(animation.loop_mode == (Animation.LOOP_NONE if clip == "FallStart" else Animation.LOOP_LINEAR), "correct loop mode " + clip)
    view.sync_pose("idle", 1, 0.4, 0.42, 0.18, 0.6, true, Vector3(5, 0, 0))
    check(view.current_clip == "Run", "ground speed selects real Run clip")
    view.animation_player.advance(0.2)
    var run_position: float = view.animation_player.current_animation_position
    var slow_rate: float = view.animation_player.get_playing_speed()
    view.sync_pose("idle", -1, 0.4, 0.42, 0.18, 0.6, true, Vector3(-7.5, 0, 0))
    check(is_equal_approx(view.animation_player.current_animation_position, run_position), "same Run clip does not seek/restart each tick")
    check(view.animation_player.get_playing_speed() > slow_rate, "Run rate scales with actual speed")
    check(is_equal_approx(view.model.rotation.y, -PI / 2), "running preserves yaw facing")
    for interruption in ["jump", "hit", "reset", "stock", "menu", "torpedo"]:
        dog.reset_fighter(Vector3.ZERO, true)
        dog.velocity = Vector3(0, -3, 0)
        dog._update_move_visuals()
        dog._update_move_visuals(0.76)
        check(view.current_clip == "MidairMoves2", "fighter remains in approved airborne loop")
        match interruption:
            "jump": dog.try_jump()
            "hit": dog.receive_hit(3, Vector3.UP, 3)
            "reset": dog.reset_fighter(Vector3.ZERO, true)
            "stock": dog.lose_stock()
            "menu":
                dog.controls_enabled = false
                dog._physics_process(0.016)
            "torpedo": dog.start_special(Vector2.RIGHT)
        check(view.fall_elapsed < 0, "immediate falling episode reset on " + interruption)
        if interruption == "torpedo":
            dog.torpedo_phase = "fall"
            dog.torpedo_time = 0
            dog.velocity.y = -4
            dog._update_move_visuals(2)
            check(view.current_clip == "Brake" and view.fall_elapsed < 0, "uncommitted torpedo Brake retains priority until actual landing")
    check(is_equal_approx(view.animation_player.get_blend_time("FallStart", "FallLoop"), 4.0 / 24.0), "four-frame transition after complete FallStart")
    dog.queue_free()
    other.queue_free()
    await process_frame
    # Real post-move floor contact, not elapsed animation, ends normal falling.
    var floor_body := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(100, 1, 5)
    shape.shape = box
    floor_body.position.y = -0.5
    floor_body.add_child(shape)
    root.add_child(floor_body)
    var falling_dog = fighter_script.new()
    falling_dog.character_id = "doge_man"
    falling_dog.player_index = 3
    falling_dog.position.y = 12
    root.add_child(falling_dog)
    var falling_view = falling_dog._visual_root.get_node("DogeVisual")
    var saw_start := false
    var saw_loop := false
    for tick in 120:
        await physics_frame
        saw_start = saw_start or falling_view.current_clip == "MidairMoves2"
        saw_loop = saw_loop or falling_view.current_clip == "MidairMoves2"
        if falling_dog.is_on_floor():
            check(falling_view.current_clip == "Idle" and falling_view.fall_elapsed < 0, "actual contact resets normal falling")
            break
    check(saw_start and saw_loop and falling_dog.is_on_floor(), "physical fall runs approved loop then lands")
    falling_dog.queue_free()
    floor_body.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge locomotion")
    quit(1 if failures else 0)
