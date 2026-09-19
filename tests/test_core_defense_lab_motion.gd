extends "res://tests/test_core_combat_lab.gd"
func settle(lab) -> void:
    for code in [KEY_E, KEY_O, KEY_F, KEY_K, KEY_D, KEY_W, KEY_LEFT, KEY_SPACE, KEY_ENTER]: key(code, false)
    lab.set_paused(false)
    lab.reset_lab()
    for i in 40: await tick(lab)
func run() -> void:
    var lab = load("res://scenes/combat_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    lab.set_defense_enabled(true)
    for endpoint in ["dodge_startup", "dodge_invulnerable", "dodge_recovery"]:
        await settle(lab)
        key(KEY_LEFT, true); key(KEY_O, true)
        await tick(lab)
        key(KEY_LEFT, false); key(KEY_O, false)
        check(lab.simulation.defense_telemetry(2).state == "dodge_startup" and lab.simulation.defense_telemetry(2).damage_eligible, "fresh press has vulnerable startup")
        var start: float = lab.actors[1].position.x
        for i in 20:
            if lab.simulation.defense_telemetry(2).state == endpoint: break
            await tick(lab)
        var state: Dictionary = lab.simulation.defense_telemetry(2)
        check(state.state == endpoint, "bounded dodge reaches exact endpoint")
        if endpoint == "dodge_invulnerable":
            check(lab.actors[1].position.x < start and lab.actors[1].velocity.x == -10, "latched active ground velocity moves actual body after direction release")
        lab.actors[0].position.x = lab.actors[1].position.x - 1
        key(KEY_F, true)
        await tick(lab)
        key(KEY_F, false)
        check(not lab.simulation.events.is_empty(), "physical strike has actual contact candidate at endpoint")
        check(lab.simulation.fighters[2].percent == (0 if endpoint == "dodge_invulnerable" else 8), "real damage filtered only in active interval")
    await settle(lab)
    lab.actors[0].position.y = 7
    await tick(lab)
    key(KEY_E, true)
    await tick(lab)
    check(lab.simulation.defense_telemetry(1).dodge_air and lab.simulation.defense_telemetry(1).air_charges == 0, "neutral airborne E is air spot and spends one charge")
    for i in 4: await tick(lab)
    check(lab.simulation.defense_telemetry(1).state == "dodge_invulnerable" and lab.actors[0].velocity == Vector3.ZERO, "air neutral spot zero velocity replaces gravity only while active")
    var height: float = lab.actors[0].position.y
    for i in 3: await tick(lab)
    check(lab.actors[0].position.y == height, "spot holds real body during active interval")
    for i in 30: await tick(lab)
    check(not lab.simulation.defense_telemetry(1).state.begins_with("dodge_"), "held E does not repeat dodge")
    key(KEY_E, false)
    for airborne in [false, true]:
        await settle(lab)
        if airborne:
            lab.actors[0].position.y = 7
            await tick(lab)
        key(KEY_W, true); key(KEY_E, true); await tick(lab)
        key(KEY_W, false); key(KEY_E, false)
        for i in (4 if airborne else 3): await tick(lab)
        check(lab.simulation.defense_telemetry(1).state == "dodge_invulnerable", "vertical physical shield request reaches active dodge")
        check(lab.simulation.defense_telemetry(1).motion_velocity == (Vector2(0,8) if airborne else Vector2.ZERO), "physical up direction inverts input Y in air and becomes ground spot")
        if airborne: check(lab.actors[0].velocity.y == 8, "directional air dodge applies real upward velocity")
    await settle(lab)
    key(KEY_O, true); await tick(lab)
    lab.simulation.fighters[2].defense.shield_health = 9 # Exact low-health contact fixture, never UI tuning.
    key(KEY_F, true); await tick(lab); key(KEY_F, false)
    check(lab.simulation.fighters[2].percent == 0 and lab.simulation.defense_telemetry(2).state == "break", "breaking physical hit stays blocked")
    key(KEY_O, false)
    for i in 20: await tick(lab)
    key(KEY_F, true); await tick(lab); key(KEY_F, false)
    check(lab.simulation.fighters[2].percent == 8, "later physical hit damages vulnerable break")
    lab.free()
    if failures == 0: print("PASS: defense lab parsed dodge endpoints motion spot held suppression and breaking contact")
    quit(1 if failures else 0)
