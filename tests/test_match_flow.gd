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
        var vs = load("res://tests/fixtures/vs_route.gd").new()
        var ffa_before: Array = vs.host_ids(self)
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
        check(arena.match_over, "last survivor wins")
        # WP-0 step 5: the payload is the match truth and the frontend presents
        # it; the arena hosts no Results screen of its own any more.
        var post = await vs.wait_for_new_host(self, ffa_before)
        check(post != null, "the resolved FFA hands its payload to the PostMatch surface")
        if post != null:
            var winner: Dictionary = post.post_match_result().winner_entry()
            check(int(winner.get("player_index", 0)) == 4, "the payload declares P4 the last survivor")
            check(str(post.post_match().outcome_label.text).find("P4") != -1, "Results names the last survivor")
        var teams_before: Array = vs.host_ids(self)
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
        check(arena.match_over, "remaining team wins")
        var team_post = await vs.wait_for_new_host(self, teams_before)
        check(team_post != null, "the resolved team match hands its payload to the PostMatch surface")
        if team_post != null:
            check(int(team_post.post_match_result().winning_team) == 1, "the payload declares TEAM B the winner")
            check(str(team_post.post_match().outcome_label.text).find("TEAM B") != -1, "Results names the winning team")
        arena._reset_match()
        check(not arena.match_over and arena.fighters.size() == 4, "restart rebuilds four slots")
        check(arena.get_node("LeftPlatform").is_in_group("pass_through_platforms"), "upper platform configured as pass through")
        check(not arena.get_node("MainPlatform").is_in_group("pass_through_platforms"), "main floor stays solid")
    arena.queue_free()
    await process_frame
    # Test hygiene: the resolution RETURNs to the frontend, so free the
    # post-match hosts this suite created.
    for child in root.get_children():
        if child.has_method("entry_mode"):
            child.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: four player FFA, teams, palettes, restart and stage setup")
    quit(1 if failures else 0)
