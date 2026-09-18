extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    print(("PASS " if ok else "FAIL ") + message)
    if not ok: failures += 1
func run():
    change_scene_to_file("res://scenes/main.tscn")
    for i in 8: await process_frame
    var game = current_scene
    var slots = load("res://scripts/match_config.gd").default_slots()
    slots[0].character = "turbofit"
    slots[1].character = "bobo"
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    check(game.start_match(slots,false,true,"debug"), "fixture launches actual match")
    await create_timer(4).timeout
    var pad = root.get_node("MobileTouch")
    pad.touch_mode = true
    await process_frame
    check(pad.gameplay_enabled,"published arena supports touch without legacy story panel")
    root.min_size = Vector2i.ZERO
    root.size = Vector2i(390,844)
    for i in 8: await process_frame
    check(paused,"portrait pauses actual combat")
    var before = game.player_one.position
    await create_timer(0.4,true).timeout
    check(before == game.player_one.position,"portrait simulation remains frozen")
    root.size = Vector2i(844,390)
    for i in 8: await process_frame
    check(not paused,"landscape releases owned rotate pause")
    game._on_pause_toggle()
    for i in 4: await process_frame
    check(not game.player_one.is_visible_in_tree(), "pause menu hides retained fighters")
    root.size = Vector2i(390,844)
    for i in 4: await process_frame
    root.size = Vector2i(844,390)
    for i in 4: await process_frame
    check(paused, "rotation does not release player's pause")
    game._pause_overlay.resume()
    for i in 4: await process_frame
    check(game.player_one.is_visible_in_tree(), "Resume restores combat rendering")
    var p = game.player_one
    game.player_two.set_physics_process(false)
    game.player_two.controls_enabled = true
    p.reset_fighter(Vector3(-1.5,0.2,0),true)
    game.player_two.position = Vector3(0.6,0.1,0)
    await create_timer(0.5).timeout
    var zones = pad.regions(root.get_visible_rect().size)
    var hp: float = game.player_two.health
    touch(1,zones.attack,true)
    await create_timer(0.45).timeout
    touch(1,zones.attack,false)
    check(game.player_two.health < hp, "touch attack damages Bobo in published arena")
    print("HP ",hp," -> ",game.player_two.health)
    await create_timer(1).timeout
    p.reset_fighter(Vector3(-4,0.2,0),true)
    await create_timer(0.5).timeout
    touch(2,zones.special,true)
    await create_timer(0.2).timeout
    check(p.charging, "touch Special starts existing charge")
    var cancel := InputEventScreenTouch.new()
    cancel.index = 2
    cancel.canceled = true
    cancel.pressed = false
    Input.parse_input_event(cancel)
    for i in 4: await process_frame
    check(not p.charging and p.last_move != "POWER CHORD", "OS cancellation aborts charge without release attack")
    touch(2,zones.special,true)
    await create_timer(0.2).timeout
    touch(2,zones.special,false)
    for i in 4: await process_frame
    check(not p.charging and p.last_move != "CHARGING", "normal release commits special")
    quit(0 if failures == 0 else 1)
func touch(index: int, point: Vector2, pressed: bool):
    var e := InputEventScreenTouch.new()
    e.index = index
    e.position = root.get_final_transform() * point
    e.pressed = pressed
    Input.parse_input_event(e)
