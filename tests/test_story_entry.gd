extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    root.size = Vector2i(1280, 720)
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    for i in 5: await process_frame
    var entry = arena.setup.find_child("StoryModeButton", true, false)
    check(entry != null, "setup offers obvious Story Mode entry")
    if entry == null:
        arena.queue_free()
        await process_frame
        quit(1)
        return
    check(entry.text == "Story Mode", "Story entry uses mode name without encounter details")
    entry.pressed.emit()
    check(arena.story_state == "ready" and arena.story_panel.visible, "Story entry opens safe ready screen")
    check(arena.fighters.is_empty() and not arena.setup.visible, "no unattended fight at intro")
    check(arena.story_character.get_selected_metadata() == "turbofit" and "Bobo" in arena.story_detail.text, "ready screen identifies default fighter and encounter")
    arena.story_action.pressed.emit()
    check(arena.story_state == "playing" and not arena.story_panel.visible, "actual Start encounter button starts story")
    check(arena.fighters.size() == 2 and get_nodes_in_group("fighters").size() == 2, "only two active fighters; no phantom bots")
    check(not arena.teams_enabled, "story has no teams")
    var hud_controls = arena.find_child("MatchControls", true, false)
    check(hud_controls != null and "Bobo: 400 HP" in hud_controls.text, "story HUD teaches human controls and identifies NPC, not a second keyboard player")
    var hero = arena.fighters[0]
    var mage = arena.fighters[1]
    check(hero.character_id == "turbofit" and hero.control_type == "human" and hero.player_index == 1 and hero.input_device == -1, "TurboFit uses human P1 keyboard")
    check(mage.character_id == "bobo" and mage.control_type == "bot" and mage.player_index == 2, "Bobo is distinct NPC bot")
    check(hero.team_id == -1 and mage.team_id == -1 and hero.stocks == 3 and mage.stocks == 3, "three-stock duel with opposing targets")
    check(hero.spawn_position.x < 0 and mage.spawn_position.x > 0, "duel starts on opposite arena sides")
    check(load("res://scripts/roster.gd").ids().has("ice_mage"), "Ice Mage stays in freeplay roster")
    arena.show_setup()
    arena.setup._start()
    check(arena.story_state == "" and arena.fighters.size() == 4, "existing freeplay Start retains all four defaults")
    check(not arena.story_panel.visible, "no story UI over freeplay")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: story UI entry, safe ready, real Start, two distinct fighters, freeplay separation")
    quit(1 if failures else 0)
