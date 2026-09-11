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
    if not arena.has_method("start_match"):
        check(false, "RED: four-player match lifecycle missing")
    else:
        var slots = load("res://scripts/match_config.gd").default_slots()
        check(arena.start_match(slots, false), "valid four player match starts")
        check(arena.fighters.size() == 4, "four fighters instantiated")
        for fighter in arena.fighters:
            fighter.set_physics_process(false)
        arena.fighters[0].stocks = 0
        arena._on_fighter_eliminated(arena.fighters[0])
        check(not arena.match_over, "FFA continues with three survivors")
        arena.fighters[1].stocks = 0
        arena.fighters[2].stocks = 0
        arena._on_fighter_eliminated(arena.fighters[2])
        check(arena.match_over and "P4" in arena.winner_label.text, "last survivor wins")
        slots[1].character = slots[0].character
        check(arena.start_match(slots, true), "teams and duplicates start")
        for fighter in arena.fighters:
            fighter.set_physics_process(false)
        check(arena.fighters[0].body_color != arena.fighters[1].body_color, "duplicates have distinct palettes")
        arena.fighters[0].stocks = 0
        arena._on_fighter_eliminated(arena.fighters[0])
        check(not arena.match_over, "team survives individual elimination")
        arena.fighters[2].stocks = 0
        arena._on_fighter_eliminated(arena.fighters[2])
        check(arena.match_over and "TEAM B" in arena.winner_label.text, "remaining team wins")
        arena._reset_match()
        check(not arena.match_over and arena.fighters.size() == 4, "restart rebuilds four slots")
        check(arena.get_node("LeftPlatform").is_in_group("pass_through_platforms"), "upper platform configured as pass through")
        check(not arena.get_node("MainPlatform").is_in_group("pass_through_platforms"), "main floor stays solid")
    arena.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: four player FFA, teams, palettes, restart and stage setup")
    quit(1 if failures else 0)
