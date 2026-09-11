extends SceneTree

const FighterScript = preload("res://scripts/fighter.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)

func key(code: int, down: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    check(Input.is_key_pressed(code) == down, "synthetic key delivered")

func _init() -> void:
    call_deferred("run")

func run() -> void:
    for player in [1, 2]:
        var f = FighterScript.new()
        f.player_index = player
        root.add_child(f)
        f.set_physics_process(false)
        # move_and_slide uses engine delta, not the manually supplied delta.
        # Run keyboard probes within a real physics tick so asset import time
        # cannot make the second player's body fall into the blast zone.
        await physics_frame
        var up := KEY_W if player == 1 else KEY_UP
        var down := KEY_S if player == 1 else KEY_DOWN
        var attack := KEY_F if player == 1 else KEY_K
        var special := KEY_G if player == 1 else KEY_L
        key(up, true)
        key(attack, true)
        f._physics_process(0.016)
        check(f.last_move == "UP AIR", "up + basic routes to upward attack for player %d" % player)
        check(f.jumps_used == 0, "attack chord does not accidentally jump")
        key(up, false)
        key(attack, false)
        f._physics_process(0.4)
        key(down, true)
        key(attack, true)
        f._physics_process(0.016)
        check(f.last_move == "DOWN STRIKE" and not f.shielding, "down + basic attacks without shielding")
        key(down, false)
        key(attack, false)
        f._physics_process(0.4)
        key(special, true)
        f._physics_process(0.016)
        f._physics_process(0.15)
        check(not f.charging and f.teknium_magic.phase == "startup", "Teknium neutral press starts delayed electric grab, not charge")
        key(special, false)
        f._physics_process(0.016)
        check(not f.charging and f.last_move == "ELECTRIC GRAB", "key release does not fire old charged melee")
        f.teknium_magic.tick(2.0)
        check(f.teknium_magic.phase == "idle", "whiff finishes before recovery input")
        f.attack_cooldown = 0
        f.jumps_used = 2
        key(up, true)
        key(special, true)
        f._physics_process(0.016)
        check(f.recovery_spent and f.velocity.y > 0, "up special input recovers")
        check(f.has_node("MoveStatus"), "recovery has visible status indicator")
        if f.has_node("MoveStatus"):
            check("LAND TO RESET" in f.get_node("MoveStatus").text, "exhaustion is visibly labeled")
        key(up, false)
        key(special, false)
        f.queue_free()
        await process_frame
        var legacy = FighterScript.new()
        legacy.character_id = "turbofit"
        legacy.player_index = player
        root.add_child(legacy)
        legacy.set_physics_process(false)
        await physics_frame
        key(special, true)
        legacy._physics_process(0.016)
        legacy._physics_process(0.5)
        check(legacy.charging and legacy.charge_time >= 0.5, "unchanged TurboFit keyboard hold accumulates charge for both players")
        key(special, false)
        legacy._physics_process(0.016)
        check(not legacy.charging and legacy.last_move == "POWER CHORD", "unchanged TurboFit keyboard release fires charge")
        legacy.queue_free()
        await process_frame
    if failures == 0:
        print("PASS: combat keyboard input")
    quit(0 if failures == 0 else 1)
