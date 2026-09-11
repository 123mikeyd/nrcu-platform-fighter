extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    check(ResourceLoader.exists("res://scripts/fire_prototype_harness.gd"), "isolated opponent setup adapter exists")
    if failures: quit(1); return
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    var harness = load("res://scripts/fire_prototype_harness.gd").new()
    arena.add_child(harness)
    harness.install(arena)
    check(arena.fighters.is_empty() and arena.setup.visible, "launcher remains safe at setup, no battle")
    arena.setup._start()
    check(arena.fighters.size() == 2 and arena.ready_remaining > 0, "real Start keeps production Ready gate")
    check(arena.player_one.character_id == "teknium" and not arena.player_one.prototype_fire and arena.player_one.control_type == "human", "P1 existing Teknium default")
    check(arena.player_two.prototype_fire and arena.player_two.control_type == "bot" and not arena.player_two.controls_enabled, "P2 Fire bot awaits Ready")
    check(arena.story_state == "" and arena.hud_title.text.contains("PROTOTYPE"), "not Story encounter; clear prototype HUD")
    arena._physics_process(arena.ready_remaining)
    arena.player_one.apply_burn(arena.player_two)
    arena.show_setup()
    check(not arena.player_one.controls_enabled and arena.player_one.burn.remaining == 0, "safe return clears burn synchronously")
    arena.setup.rows[0].character.select(3)
    arena.setup._start()
    check(arena.player_one.character_id == "turbofit" and arena.player_two.prototype_fire, "existing P1 choice retained across actual Start")
    arena._physics_process(arena.ready_remaining)
    arena.player_one.apply_burn(arena.player_two)
    arena.player_two.stocks = 1
    arena.player_two._handle_blast_zone()
    check(arena.match_over and arena.player_one.burn.remaining == 0, "winner immediately clears burn")
    arena._reset_match()
    check(arena.player_two.prototype_fire and arena.ready_remaining > 0, "rematch remains Fire prototype and Ready gated")
    arena.show_setup()
    arena.open_story()
    arena.start_story()
    check(arena.story_state == "playing" and not arena.player_two.prototype_fire and arena.player_two.character_id == "bobo", "first Bobo Story remains independent from Fire prototype")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: isolated prototype safe setup, real Start/Ready, existing P1 choices, cleanup/winner/rematch and unchanged Ice Story")
    quit(1 if failures else 0)
