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
    var slots = load("res://scripts/match_config.gd").default_slots()
    slots[0].character = "turbofit"
    slots[1].character = "ice_mage"
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    arena.start_match(slots, false)
    arena.player_one.reset_fighter(arena.p1_spawn, true)
    arena.player_two.reset_fighter(arena.p2_spawn, true)
    arena.player_one.facing = 1
    arena.player_two.facing = -1
    arena._begin_ready()
    var hero = arena.player_one
    var mage = arena.player_two
    var froze := false
    for i in 240:
        await frames(1)
        if hero.freeze_remaining > 0:
            froze = true
            break
    check(froze, "unmodified Normal Ice Mage NPC autonomously casts a real freezing bolt")
    check(hero.damage_percent == 4, "NPC Frost Bolt uses existing four damage")
    mage.set_physics_process(false)
    mage.position = Vector3(5, 0, 0)
    var x: float = hero.position.x
    key(KEY_D, true)
    key(KEY_F, true)
    await frames(10)
    check(absf(hero.position.x - x) < 0.01 and hero.freeze_remaining > 0, "real P1 movement/basic are locked by NPC freeze")
    key(KEY_F, false)
    await frames(65)
    check(hero.freeze_remaining == 0 and hero.position.x > x + 0.2, "freeze thaws and human D movement resumes")
    key(KEY_D, false)
    hero.reset_fighter(Vector3(-2, 0.1, 0), true)
    mage.reset_fighter(Vector3(1, 0.1, 0), true)
    await frames(30)
    hero.facing = 1
    key(KEY_D, true)
    key(KEY_G, true)
    await frames(2)
    key(KEY_D, false)
    key(KEY_G, false)
    await frames(30)
    check(mage.damage_percent > 0, "actual P1 D+G sound projectile damages Ice Mage NPC")
    # Controlled final-stock setup; use production hit, physics blast-zone and signal, not winner callback.
    mage.stocks = 1
    mage.position = Vector3(8, 1, 0)
    mage.receive_hit(500, Vector3.RIGHT, 50)
    mage.set_physics_process(true)
    for i in 120:
        await frames(1)
        if arena.match_over: break
    check(arena.match_over and arena.winner_label.visible, "physical knockback elimination reaches exact story victory")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: autonomous story NPC freeze, human lock/thaw/input damage, physics knockback elimination -> exact victory")
    quit(1 if failures else 0)
