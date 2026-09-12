extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    arena.setup.find_child("StoryModeButton", true, false).pressed.emit()
    arena.story_action.pressed.emit()
    arena._physics_process(arena.ready_remaining) # Status/cleanup fixtures start after Go, not during Ready.
    var hero = arena.player_one
    var mage = arena.player_two
    for f in arena.fighters: f.set_physics_process(false)
    mage.receive_hit(150, Vector3.RIGHT, 4)
    check(not arena.match_over and arena.story_state == "playing" and mage.health == 250, "first stock loss is not completion")
    mage.receive_hit(150, Vector3.RIGHT, 4)
    check(not arena.match_over and mage.health == 100, "second stock loss continues encounter")
    check(mage.apply_freeze(hero), "Bobo receives existing finite freeze")
    var bolt = load("res://scripts/projectile.gd").new()
    bolt.source = hero
    bolt.sound_wave = true
    arena.add_child(bolt)
    mage.receive_hit(150, Vector3.RIGHT, 4)
    check(arena.match_over and arena.story_state == "complete", "Ice Mage final elimination completes one-stage story")
    var stage = arena.story_panel.find_child("StoryStage", true, false)
    check(stage != null and not stage.is_chip_visible(), "no placed chip on the results screen")
    if stage != null:
        check(not stage.cursor.is_carrying(), "hand no longer carries into the results")
    check(arena.story_panel.visible and arena.story_title.text == "your pretty cool", "victory title is exact requested lowercase string")
    check(arena.story_action.text == "REPLAY" and arena.story_back.visible, "victory offers replay and back")
    check(not arena.winner_label.visible, "generic freeplay winner text does not leak")
    check(hero.freeze_remaining == 0 and not hero.get_node("FrozenShell").visible, "completion clears freeze even with physics disabled")
    check(bolt.is_queued_for_deletion(), "completion immediately queues every projectile for cleanup")
    for f in arena.fighters: check(not f.controls_enabled, "result blocks combat")
    await process_frame
    check(get_nodes_in_group("projectiles").is_empty(), "no projectile remains at result")
    arena.story_action.pressed.emit()
    arena._physics_process(arena.ready_remaining) # Status/cleanup fixtures start after Go, not during Ready.
    await process_frame
    check(arena.story_state == "playing" and not arena.match_over and arena.fighters.size() == 2, "Replay launches fresh single encounter")
    check(get_nodes_in_group("fighters").size() == 2, "Replay removes old fighters")
    for f in arena.fighters:
        f.set_physics_process(false)
        check(f.stocks == 3 and f.damage_percent == 0 and f.freeze_remaining == 0 and f.freeze_immunity == 0 and f.ice_cast_cooldown == 0, "Replay resets stocks, damage and freeze lifecycle")
    hero = arena.player_one
    mage = arena.player_two
    for i in 3: hero._handle_blast_zone()
    check(arena.story_state == "lost" and arena.story_panel.visible and arena.match_over, "human stock exhaustion shows loss")
    check(arena.story_title.text != "your pretty cool" and arena.story_action.text == "RETRY", "loss offers Retry, not victory")
    arena.story_action.pressed.emit()
    arena._physics_process(arena.ready_remaining) # Status/cleanup fixtures start after Go, not during Ready.
    check(arena.story_state == "playing" and arena.player_one.stocks == 3 and arena.player_two.stocks == 3, "Retry starts fresh duel")
    hero = arena.player_one
    mage = arena.player_two
    mage.apply_freeze(hero)
    bolt = load("res://scripts/projectile.gd").new()
    bolt.source = mage
    bolt.freeze_bolt = true
    arena.add_child(bolt)
    arena._unhandled_key_input(make_escape())
    check(arena.setup.visible and arena.story_state == "" and not arena.story_panel.visible, "Esc exits story to existing menu")
    check(hero.freeze_remaining == 0 and hero.freeze_immunity == 0 and not hero.controls_enabled, "exit clears freeze and stops human")
    check(bolt.is_queued_for_deletion(), "exit clears projectiles")
    arena.setup.mode.select(1)
    arena.setup._start()
    check(arena.fighters.size() == 4 and arena.teams_enabled and arena.story_state == "", "freeplay Teams survives story exit")
    for f in arena.fighters: f.set_physics_process(false)
    for i in [0, 2]:
        for stock in 3: arena.fighters[i]._handle_blast_zone()
    check(arena.winner_label.visible and "TEAM B WINS!" in arena.winner_label.text and not arena.story_panel.visible, "freeplay uses original winner flow")
    arena.show_setup()
    arena.setup.find_child("StoryModeButton", true, false).pressed.emit()
    arena.story_back.pressed.emit()
    check(arena.setup.visible and arena.story_state == "", "ready Back returns without starting")
    arena.open_story()
    arena.story_action.pressed.emit()
    arena._physics_process(arena.ready_remaining) # Status/cleanup fixtures start after Go, not during Ready.
    for f in arena.fighters: f.set_physics_process(false)
    arena.player_two.receive_hit(400, Vector3.RIGHT, 4)
    arena._reset_match()
    check(arena.story_state == "playing" and not arena.story_panel.visible and arena.fighters.size() == 2, "R rematch stays in story")
    for f in arena.fighters: f.set_physics_process(false)
    arena.player_two.receive_hit(400, Vector3.RIGHT, 4)
    arena.story_back.pressed.emit()
    check(arena.setup.visible and arena.story_state == "" and not arena.match_over, "victory Back clears completion")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: story stocks, exact victory, completion cleanup, Replay, loss/Retry, Esc, Back and freeplay teams/winner")
    quit(1 if failures else 0)
func make_escape() -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.pressed = true
    return event
