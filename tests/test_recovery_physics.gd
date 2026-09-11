extends SceneTree

var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    var slots = load("res://scripts/match_config.gd").default_slots()
    slots[1].kind = "human"
    slots[1].character = "teknium"
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    if not arena.start_match(slots, false):
        push_error("Could not start recovery fixture")
        quit(1)
        return
    arena._physics_process(arena.ready_remaining) # The recovery fixture begins after the real Go transition.
    var f = arena.player_one
    var target = arena.player_two
    # Use the clear center of the main platform, below the top platform.
    f.position = Vector3(0, 0.1, 0)
    target.position = Vector3(8, 0.1, 0)
    for i in range(20):
        await physics_frame
    check(f.is_on_floor(), "fighter physically settled on stage")
    f.start_special(Vector2.UP)
    await physics_frame
    await physics_frame
    check(f.recovery_spent and not f.is_on_floor(), "ground recovery takes off without immediately resetting")
    for i in range(150):
        await physics_frame
    check(f.is_on_floor() and not f.recovery_spent and f.jumps_used == 0, "real landing resets recovery and jumps")
    f.set_physics_process(false)
    target.set_physics_process(false)
    f.position = Vector3(0, 1, 0)
    target.position = Vector3(0, 2.8, 0)
    target.damage_percent = 0
    f.attack_cooldown = 0
    f.start_special(Vector2.UP)
    f._tick_recovery(0.016)
    f._tick_recovery(0.016)
    check(target.damage_percent == 12 and target.velocity.y > 0, "rising attack hits once and launches upward")
    f.attack_cooldown = 0
    f.start_special(Vector2.RIGHT)
    arena._reset_match()
    await process_frame
    check(get_nodes_in_group("projectiles").is_empty(), "restart removes old projectiles")
    check(not f.recovery_spent and f.jumps_used == 0, "restart resets recovery")
    arena.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: recovery physics and restart")
    quit(0 if failures == 0 else 1)
