extends SceneTree

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    var slots = load("res://scripts/match_config.gd").default_slots()
    for i in range(4):
        slots[i].kind = "bot"
        slots[i].difficulty = ["easy", "normal", "hard", "normal"][i]
    if not arena.start_match(slots, false):
        push_error("Bot battle could not start")
        quit(1)
        return
    var max_damage := 0.0
    var moved := false
    for frame in range(900):
        await physics_frame
        for fighter in arena.fighters:
            max_damage = maxf(max_damage, fighter.damage_percent)
            moved = moved or fighter.global_position.distance_to(fighter.spawn_position) > 1
            if not fighter.global_position.is_finite() or fighter.stocks < 0:
                push_error("Invalid state in live bot battle")
                quit(1)
                return
    if not moved or max_damage <= 0:
        push_error("Bots must move and land real attacks; damage=%s" % max_damage)
        quit(1)
        return
    print("PASS: 900 physics-frame mixed-difficulty bot battle; peak damage=", max_damage)
    arena.queue_free()
    await process_frame
    quit(0)
