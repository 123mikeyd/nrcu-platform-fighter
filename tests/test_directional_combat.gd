extends SceneTree

var failures := 0
const FighterScript = preload("res://scripts/fighter.gd")

func check(condition: bool, message: String) -> void:
    if not condition:
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
    if not fighter.has_method("basic_attack"):
        check(false, "RED: directional basic attacks missing")
    else:
        target.position = Vector3(0, 1.8, 0)
        fighter.basic_attack(Vector2.UP, false)
        check(target.damage_percent > 0 and target.velocity.y > 0, "uppercut hits above and launches upward")
        target.damage_percent = 0
        target.position = Vector3(0, -1.8, 0)
        fighter.attack_cooldown = 0
        fighter.basic_attack(Vector2.DOWN, true)
        check(target.damage_percent > 0 and target.velocity.y < 0, "down aerial hits below and spikes")
        target.damage_percent = 0
        target.position = Vector3(1.7, 0, 0)
        fighter.attack_cooldown = 0
        fighter.basic_attack(Vector2.ZERO, true)
        check(target.damage_percent > 0, "neutral jump attack hits forward")
        check(fighter.last_move == "AIR STRIKE", "air attack has distinct presentation")
        target.damage_percent = 0
        target.position = Vector3(-1.7, 0, 0)
        fighter.attack_cooldown = 0
        fighter.basic_attack(Vector2.RIGHT, false)
        check(target.damage_percent == 0, "forward attack cannot hit behind")
    fighter.queue_free()
    target.queue_free()
    await process_frame
    if failures == 0:
        print("PASS: directional combat")
    quit(0 if failures == 0 else 1)
