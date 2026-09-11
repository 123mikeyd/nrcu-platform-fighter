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
    arena.setup.rows[0].character.select(4)
    arena.setup._start()
    arena._physics_process(arena.ready_remaining) # Advance the real Ready gate before combat fixtures.
    var mage = arena.fighters[0]
    var target = arena.fighters[1]
    for other in arena.fighters.slice(2):
        other.controls_enabled = false
        other.position = Vector3(10 + other.player_index, 8, 0)
    target.control_type = "human"
    target.player_index = 2
    mage.position = Vector3(-2, 0.1, 0)
    target.position = Vector3(1, 0.1, 0)
    await frames(30)
    key(KEY_G, true)
    await frames(2)
    key(KEY_G, false)
    await frames(25)
    check(target.has_method("apply_freeze"), "real finite freeze status API exists")
    if not target.has_method("apply_freeze"):
        arena.queue_free()
        await process_frame
        quit(1)
        return
    check(target.freeze_remaining > 0, "actual neutral G projectile hits and freezes enemy")
    check(target.damage_percent == 4.0, "freeze bolt deals four damage")
    check(target.get_node("FrozenShell").visible, "compact frozen shell visible")
    var x: float = target.position.x
    key(KEY_RIGHT, true)
    key(KEY_ENTER, true)
    key(KEY_K, true)
    key(KEY_L, true)
    await frames(12)
    check(absf(target.position.x-x)<0.01 and target.is_on_floor(), "freeze blocks keyboard movement/jump on floor")
    check(target.attack_cooldown == 0 and not target.charging, "freeze blocks keyboard basic/special")
    check(not target.try_jump(), "direct jump also blocked")
    await frames(65)
    check(target.freeze_remaining == 0 and not target.get_node("FrozenShell").visible, "freeze expires and shell clears")
    check(target.position.x>x+0.2, "held movement resumes after thaw")
    for code in [KEY_RIGHT, KEY_ENTER, KEY_K, KEY_L]: key(code, false)
    check(not target.apply_freeze(mage), "brief post-thaw immunity blocks immediate re-freeze")
    target.reset_fighter(Vector3(1,4,0))
    check(target.apply_freeze(mage), "reset clears status and immunity")
    var y: float = target.position.y
    await frames(12)
    check(target.position.y<y-0.1 and target.freeze_remaining>0, "frozen airborne body still falls under gravity")
    target.receive_hit(8, Vector3.RIGHT, 3.8)
    check(target.freeze_remaining==0 and target.freeze_immunity>0, "next damaging hit shatters early with immunity")
    target.reset_fighter(Vector3(1,0,0))
    target.shielding = true
    check(not target.apply_freeze(mage), "shield blocks status")
    target.shielding = false
    mage.team_id = 0
    target.team_id = 0
    check(not target.apply_freeze(mage), "same-team target excluded")
    mage.team_id = -1
    target.team_id = -1
    target.apply_freeze(mage)
    target.lose_stock()
    check(target.freeze_remaining==0 and target.freeze_immunity==0, "stock loss clears freeze and immunity")
    target.reset_fighter(Vector3(1,0,0))
    target.apply_freeze(mage)
    arena.show_setup()
    await frames(2)
    check(target.freeze_remaining==0 and not target.get_node("FrozenShell").visible, "setup clears status and cue")
    arena.queue_free()
    await process_frame
    if failures==0: print("PASS: Ice freeze real G input/projectile, damage, locks, gravity, thaw, immunity, shatter, shield, teams, stock/reset/setup")
    quit(1 if failures else 0)
