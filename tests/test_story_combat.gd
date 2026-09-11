extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func key(code: int, down: bool):
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()
func frames(count: int):
    for i in count: await physics_frame
    await process_frame
func run():
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    arena.open_story()
    arena.story_action.pressed.emit()
    await frames(120)
    var hero = arena.player_one
    var bobo = arena.player_two
    check(hero.damage_percent == 0 and bobo.health == 400, "passive Bobo never attacks")
    var x: float = hero.position.x
    key(KEY_D,true)
    await frames(12)
    key(KEY_D,false)
    check(hero.position.x > x + 0.2, "human can freely move")
    hero.reset_fighter(Vector3(0,0.1,0),true)
    bobo.reset_fighter(Vector3(2,0.1,0),true)
    await frames(30)
    hero.facing = 1
    key(KEY_D,true)
    key(KEY_G,true)
    await frames(2)
    key(KEY_D,false)
    key(KEY_G,false)
    await frames(45)
    check(bobo.health < 400 and bobo.reaction_serial > 0, "real P1 projectile consumes HP and starts native reaction")
    var hp: float = bobo.health
    await frames(50)
    check(bobo.health == hp, "one projectile cannot consume HP twice")
    bobo.receive_hit(5,Vector3.RIGHT,100)
    bobo._handle_blast_zone()
    check(not arena.match_over and bobo.health == hp-5, "knockoff never bypasses HP")
    bobo.receive_hit(1000,Vector3.RIGHT,100)
    check(arena.story_state == "complete" and arena.story_title.text == "your pretty cool", "real lethal damage completes Story")
    arena.story_action.pressed.emit()
    await frames(120)
    check(arena.player_two.health == 400, "Replay restores HP")
    for i in 3: arena.player_one._handle_blast_zone()
    check(arena.story_state == "lost", "player stock loss remains real")
    arena.story_action.pressed.emit()
    check(arena.player_two.health == 400 and arena.player_one.stocks == 3, "Retry restores both fighters")
    arena.show_setup()
    check(not arena.bobo_health_bar.visible, "Back hides encounter-only HP bar")
    arena.queue_free()
    await process_frame
    print("BOBO_INPUT failures=", failures)
    quit(1 if failures else 0)
