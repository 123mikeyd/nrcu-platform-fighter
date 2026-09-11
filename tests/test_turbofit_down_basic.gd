extends SceneTree

const FighterScript = preload("res://scripts/fighter.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        printerr("FAIL: " + message)

func make_fighter(character: String, position: Vector3):
    var fighter = FighterScript.new()
    fighter.character_id = character
    root.add_child(fighter)
    fighter.set_physics_process(false)
    fighter.global_position = position
    return fighter

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var turbo = make_fighter("turbofit", Vector3.ZERO)
    var grounded = make_fighter("teknium", Vector3(1.5, 0.0, 0.0))
    turbo.basic_attack(Vector2.DOWN, false)
    check(turbo.last_move == "GOALKEEPER KICK" and turbo.turbofit_attack_clip == "GoalkeeperKick", "grounded down-basic routes to goalkeeper kick")
    turbo._tick_character_move(0.44)
    check(grounded.damage_percent == 0.0, "down kick respects its sampled strike windup")
    turbo._tick_character_move(0.02)
    check(grounded.damage_percent == 14.0, "grounded down-basic hits a grounded enemy in front")

    turbo.reset_fighter(Vector3.ZERO, true)
    var airborne_above = make_fighter("teknium", Vector3(1.0, 1.5, 0.0))
    turbo.basic_attack(Vector2.DOWN, false)
    turbo._tick_character_move(0.46)
    check(airborne_above.damage_percent == 0.0, "grounded down kick preserves down-basic low cone and misses an enemy above")

    turbo.reset_fighter(Vector3(0.0, 2.0, 0.0), true)
    var target_below = make_fighter("teknium", Vector3(0.0, 0.5, 0.0))
    turbo.basic_attack(Vector2.DOWN, true)
    turbo._tick_character_move(14.0 / 30.0)
    var visual = turbo.get_node("VisualRoot/TurboFitVisual")
    var volume: Dictionary = visual.air_down_kick_volume(turbo.turbofit_attack_elapsed, 38.0 / 30.0, 1)
    target_below.position = volume.center - Vector3(0, 1.6, 0)
    turbo._query_air_down_kick()
    check(target_below.position.y < turbo.position.y and target_below.damage_percent == 14.0, "airborne down-basic foot contacts and spikes a target below")

    for fighter in [target_below, airborne_above, grounded, turbo]:
        fighter.queue_free()
    await process_frame
    if failures == 0:
        print("PASS TurboFit down-basic hit geometry")
    quit(1 if failures else 0)
