extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var dog = F.new()
    dog.character_id = "doge_man"
    root.add_child(dog)
    dog.set_physics_process(false)
    var enemy = F.new()
    enemy.player_index = 1
    root.add_child(enemy)
    enemy.set_physics_process(false)
    var view = dog._visual_root.get_node("DogeVisual")
    for face in [1.0, -1.0]:
        dog.reset_fighter(Vector3(0,4,0), true)
        enemy.reset_fighter(Vector3(0,6,0), true)
        dog.facing = face
        dog.jumps_used = 1
        dog.recovery_spent = true
        dog.velocity = Vector3(0,2,0)
        dog.basic_attack(Vector2.UP, true)
        dog._update_move_visuals()
        check(view.current_clip == "Uppercut", "air up basic selects approved Uppercut")
        check(enemy.damage_percent == 8 and dog.attack_cooldown == 0.32, "existing immediate 8 damage and 0.32 cooldown retained")
        check(dog.doge_attack_clip == "" and dog.jumps_used == 1 and dog.recovery_spent and dog.velocity == Vector3(0,2,0), "visual reuse does not start ground combo or alter motion/resources")
        check(view.flight_root.rotation == Vector3.ZERO, "air uppercut stays upright")
        if view.current_clip == "Uppercut":
            check(is_equal_approx(view.animation_player.current_animation_position, 11.0/24.0), "immediate damage uses authored contact pose, not compressed windup")
        dog.attack_cooldown -= 0.1
        dog._update_move_visuals()
        if view.current_clip == "Uppercut":
            check(is_equal_approx(view.animation_player.current_animation_position, 11.0/24.0 + 0.14), "followthrough keeps existing uppercut playback speed")
        dog.attack_cooldown = 0
        dog._update_move_visuals()
        check(view.current_clip == "MidairMoves2", "expiry restores midair without stale takeoff")
    for aim in [Vector2.ZERO, Vector2.DOWN]:
        dog.reset_fighter(Vector3(0,4,0), true)
        dog.basic_attack(Vector2.UP, true)
        dog._update_move_visuals()
        # Input is consumed after cooldown decrement but before visual update.
        dog.attack_cooldown = 0
        dog.basic_attack(aim, true)
        dog._update_move_visuals()
        check(view.current_clip != "Uppercut", "fresh accepted aerial input cannot inherit expired Uppercut presentation")
    dog.queue_free()
    enemy.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge airborne uppercut visual-only contact clock")
    quit(1 if failures else 0)
