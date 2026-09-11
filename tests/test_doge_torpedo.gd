extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, msg: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + msg)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var dog = F.new()
    dog.character_id = "doge_man"
    root.add_child(dog)
    dog.set_physics_process(false)
    var enemy = F.new()
    root.add_child(enemy)
    enemy.set_physics_process(false)
    enemy.position.x = 1
    dog.start_special(Vector2.RIGHT)
    check(dog.tackle_active == 0, "launch has no active hitbox")
    dog._tick_character_move(0.1)
    check(enemy.damage_percent == 0, "launch cannot damage")
    check(dog.has_method("_tick_torpedo"), "torpedo phase controller exists")
    if dog.has_method("_tick_torpedo"):
        check(dog.torpedo_phase == "launch", "starts in launch")
        dog._tick_character_move(dog.TORPEDO_LAUNCH_TIME)
        check(dog.torpedo_phase == "tackle" and dog.tackle_active > 0, "launch transitions to tackle")
        dog._tick_character_move(0.05)
        check(enemy.damage_percent == 14, "tackle damages")
        dog._tick_character_move(0.05)
        check(enemy.damage_percent == 14, "tackle hits each target once")
        dog._tick_character_move(1)
        check(dog.torpedo_phase == "fall", "air timeout falls rather than lands")
        dog.attack_cooldown = 0
        dog.start_special(Vector2.LEFT)
        check(dog.torpedo_phase == "fall" and dog.facing == 1, "spent tackle cannot restart or reverse")
        check(not dog.try_jump(), "fall cannot be jump canceled")
        dog.basic_attack(Vector2.LEFT, true)
        check(dog.facing == 1 and enemy.damage_percent == 14, "fall blocks basic attacks")
        dog.start_special(Vector2.UP)
        check(not dog.recovery_spent, "fall blocks recovery cancel")
        dog.receive_hit(2, Vector3.LEFT, 2)
        check(dog.torpedo_phase == "idle" and dog.tackle_active == 0 and dog.tackle_targets.is_empty(), "hit interrupts and clears torpedo")
        check(dog.tackle_spent, "hit does not restore airborne tackle")
        dog.reset_fighter(Vector3.ZERO, true)
        check(dog.torpedo_phase == "idle" and not dog.tackle_spent, "reset cleans torpedo")
        dog.start_special(Vector2.RIGHT)
        dog.lose_stock()
        check(dog.torpedo_phase == "idle" and dog.torpedo_time == 0, "stock loss cleans torpedo")
        dog.reset_fighter(Vector3.ZERO, true)
        dog.team_id = 0
        enemy.team_id = 0
        enemy.damage_percent = 0
        dog.start_special(Vector2.RIGHT)
        dog._tick_character_move(dog.TORPEDO_LAUNCH_TIME)
        dog._tick_character_move(0.05)
        check(enemy.damage_percent == 0, "torpedo respects friendly fire")
        dog.reset_fighter(Vector3.ZERO, true)
        dog.start_special(Vector2.RIGHT)
        dog._tick_character_move(dog.TORPEDO_LAUNCH_TIME)
        dog._tick_character_move(dog.TORPEDO_TACKLE_TIME)
        dog._tick_character_move(dog.TORPEDO_BRAKE_TIME)
        dog.attack_cooldown = 0
        dog.start_special(Vector2.UP)
        check(dog.recovery_spent and dog.torpedo_phase == "idle", "completed brake allows remaining up recovery")
    dog.queue_free()
    enemy.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge torpedo phases")
    quit(1 if failures else 0)
