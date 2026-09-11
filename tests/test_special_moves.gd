extends SceneTree

const FighterScript = preload("res://scripts/fighter.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var fighter = FighterScript.new()
    root.add_child(fighter)
    fighter.set_physics_process(false)
    var target = FighterScript.new()
    root.add_child(target)
    target.set_physics_process(false)
    target.position = Vector3(2, 0, 0)
    if not fighter.has_method("start_special"):
        check(false, "RED: special move lifecycle missing")
    else:
        var legacy = FighterScript.new()
        legacy.character_id = "turbofit"
        root.add_child(legacy)
        legacy.set_physics_process(false)
        legacy.start_special(Vector2.ZERO)
        check(legacy.charging, "unchanged TurboFit neutral special starts holding a charge")
        check(target.damage_percent == 0, "holding does not attack immediately")
        legacy.advance_charge(3.0)
        check(legacy.charge_time == legacy.MAX_CHARGE_TIME, "charge is capped")
        legacy.release_special()
        check(target.damage_percent == 26.0, "full charge releases stronger melee hit")
        legacy.attack_cooldown = 0
        legacy.start_special(Vector2.ZERO)
        legacy.receive_hit(1, Vector3.RIGHT, 1)
        check(not legacy.charging, "getting hit cancels charge")
        legacy.queue_free()
        await process_frame
        fighter.hitstun = 0
        fighter.attack_cooldown = 0
        fighter.start_special(Vector2.DOWN)
        check(not fighter.charging and fighter.attack_cooldown == 0, "down special is deliberately unassigned")
        if not fighter.has_method("try_jump"):
            check(false, "RED: recovery jump lifecycle missing")
        else:
            fighter.jumps_used = 2
            fighter.start_special(Vector2.UP)
            check(fighter.velocity.y > fighter.JUMP_SPEED, "up special provides third-jump lift")
            check(fighter.recovery_spent, "up special marks recovery exhausted")
            check(not fighter.try_jump(), "cannot jump after recovery")
            fighter.attack_cooldown = 0
            fighter.velocity.y = -2
            fighter.start_special(Vector2.UP)
            check(fighter.velocity.y == -2, "cannot repeat recovery before landing")
            fighter.reset_air_resources()
            check(not fighter.recovery_spent and fighter.try_jump(), "landing restores jumps")
            fighter.recovery_spent = true
            fighter.lose_stock()
            check(not fighter.recovery_spent and not fighter.charging, "stock loss clears special state")
        fighter.hitstun = 0
        fighter.attack_cooldown = 0
        fighter.position = Vector3.ZERO
        target.position = Vector3(5, 0, 0)
        target.damage_percent = 0
        await physics_frame
        await process_frame
        fighter.start_special(Vector2.RIGHT)
        check(get_nodes_in_group("projectiles").is_empty(), "Teknium no immediate shot")
        fighter.teknium_magic.tick(0.25)
        var shots := get_nodes_in_group("projectiles")
        check(shots.size() == 1, "side special spawns a real projectile")
        if shots.size() == 1:
            shots[0].set_physics_process(false)
            check(target.damage_percent == 0, "projectile is not an instant ranged hit")
            shots[0]._physics_process(0.3)
            check(target.damage_percent == 8, "traveling force projectile hits target")
            check(shots[0].is_queued_for_deletion(), "projectile is consumed on hit")
    fighter.queue_free()
    target.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: special moves")
    quit(0 if failures == 0 else 1)
