extends SceneTree
# Legacy Punch1..4 direct-motion/mechanics coverage, not the mapped F action.
# Synthetic clocks below deliberately do not describe installed source timing.
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
    check(dog.get("doge_attack_timings") != null, "timed attack configuration exists")
    if dog.get("doge_attack_timings") != null:
        # Synthetic test clock, not source animation claims.
        dog.doge_attack_timings = {"Punch1": {"duration": 0.6, "impact_time": 0.2}, "Uppercut": {"duration": 0.8, "impact_time": 0.3}}
        dog._start_doge_attack("Punch1", Vector2.ZERO)
        check(enemy.damage_percent == 0, "legacy direct punch has windup, never instant damage")
        dog._tick_character_move(0.19)
        check(enemy.damage_percent == 0, "before impact cannot hit")
        dog._tick_character_move(0.01)
        check(enemy.damage_percent == 8, "strike event deals one punch")
        check(dog.attack_flash_time == 0 and not dog._attack_flash.visible, "animated punch stays readable without placeholder flash")
        dog._tick_character_move(0.1)
        check(enemy.damage_percent == 8, "strike cannot damage twice")
        check(dog.attack_cooldown > 0, "recovery remains after strike")
        dog._tick_character_move(0.3)
        check(dog.doge_attack_clip == "", "clip ends at configured duration")
        dog.reset_fighter(Vector3.ZERO, true)
        enemy.damage_percent = 0
        enemy.position = Vector3(0.3, 1.5, 0)
        dog.basic_attack(Vector2.UP, false)
        check(dog.doge_attack_clip == "Uppercut", "up ground basic selects uppercut")
        dog._tick_character_move(0.29)
        check(enemy.damage_percent == 0, "uppercut windup cannot hit")
        dog._tick_character_move(0.01)
        check(enemy.damage_percent == 8 and enemy.velocity.y > 0, "uppercut strike launches upward")
        check(dog.attack_flash_time == 0 and not dog._attack_flash.visible, "uppercut fist is unobscured by placeholder flash")
        for cancel in ["hit", "stock", "reset", "menu", "up_special", "jump"]:
            dog.reset_fighter(Vector3.ZERO, true)
            enemy.damage_percent = 0
            enemy.position = Vector3.RIGHT
            dog._start_doge_attack("Punch1", Vector2.ZERO)
            match cancel:
                "hit": dog.receive_hit(1, Vector3.LEFT, 1)
                "stock": dog.lose_stock()
                "reset": dog.reset_fighter(Vector3.ZERO, true)
                "menu": dog.controls_enabled = false
                "up_special": dog.start_special(Vector2.UP)
                "jump": dog.try_jump()
            dog._tick_character_move(0.4)
            check(enemy.damage_percent == 0, cancel + " cancels pending strike")
            check(dog.doge_attack_clip == "", cancel + " clears attack presentation")
            if cancel == "up_special":
                check(dog.recovery_spent, "up special interrupts windup despite basic cooldown")
        dog.reset_fighter(Vector3.ZERO, true)
        enemy.damage_percent = 0
        enemy.position = Vector3.RIGHT
        dog.team_id = 0
        enemy.team_id = 0
        dog._start_doge_attack("Punch1", Vector2.ZERO)
        dog._tick_character_move(0.25)
        check(enemy.damage_percent == 0, "punch respects teams")
        dog.reset_fighter(Vector3.ZERO, true)
        enemy.team_id = 1
        dog.basic_attack(Vector2.UP, false)
        dog._tick_character_move(0.3)
        check(enemy.damage_percent == 8 and enemy.velocity.y > 0, "uppercut catches nearby front chest, not only overhead feet")
        dog.reset_fighter(Vector3.ZERO, true)
        dog.doge_attack_timings = {}
        for clip in ["Punch1", "Punch2", "Punch3", "Punch4", "Uppercut"]:
            dog.doge_attack_timings[clip] = {"duration": 0.6, "impact_time": 0.2}
        for step in range(1, 5):
            if step == 1: dog._start_doge_attack("Punch1", Vector2.ZERO)
            check(dog.doge_attack_clip == "Punch%d" % step, "legacy buffer advances exactly to punch %d" % step)
            dog.basic_attack(Vector2.LEFT, false)
            dog._tick_character_move(0.2)
            check(dog.facing == 1, "windup rejects early taps and reversal")
            if step < 4:
                dog.basic_attack(Vector2.LEFT, false)
                dog.basic_attack(Vector2.LEFT, false)
            dog._tick_character_move(0.4)
        check(dog.doge_attack_clip == "", "fourth punch ends, never loops automatically")
        check(dog.doge_combo_next == 1, "completed legacy combo resets to first punch")
        dog._start_doge_attack("Punch1", Vector2.ZERO)
        dog._tick_character_move(0.6)
        check(dog.doge_attack_clip == "", "one direct legacy start plays one punch only")
        check(dog.doge_combo_next == 2, "legacy recovery retains next-step bookkeeping")
        dog._start_doge_attack("Punch2", Vector2.ZERO)
        check(dog.doge_attack_clip == "Punch2", "explicit legacy continuation starts punch two")
        dog._tick_character_move(1.0)
        dog._tick_character_move(1.0)
        check(dog.doge_combo_next == 1, "pause expires legacy combo")
        dog._start_doge_attack("Punch1", Vector2.ZERO)
        dog._tick_character_move(0.2)
        dog.basic_attack(Vector2.ZERO, false)
        dog.receive_hit(1, Vector3.LEFT, 1)
        dog.hitstun = 0
        dog._tick_character_move(1)
        check(dog.doge_attack_clip == "", "hit cancels buffered continuation")
        check(dog.doge_combo_next == 1, "interruption clears legacy combo step")
        dog._start_doge_attack("Punch1", Vector2.ZERO)
        dog.reset_fighter(Vector3.ZERO, true)
        enemy.position = Vector3.RIGHT
        enemy.damage_percent = 0
        dog._start_doge_attack("Punch1", Vector2.ZERO)
        dog.attack_cooldown = 0
        dog.start_special(Vector2.RIGHT)
        check(dog.torpedo_phase == "idle", "active punch cannot be overwritten by side special even at cooldown boundary")
        dog.reset_fighter(Vector3.ZERO, true)
        dog.start_special(Vector2.RIGHT)
        dog.attack_cooldown = 0
        dog.basic_attack(Vector2.UP, false)
        check(dog.doge_attack_clip == "", "torpedo commitment rejects available grounded uppercut")
        dog.reset_fighter(Vector3.ZERO, true)
        dog.doge_attack_timings["SupermanMoves2"] = {"duration": 10.0 / 24.0, "impact_time": 7.25 / 24.0}
        dog.basic_attack(Vector2.ZERO, true)
        check(enemy.damage_percent == 0 and dog.doge_attack_clip == "SupermanMoves2", "approved air basic now has source-clock windup")
        dog.reset_fighter(Vector3.ZERO, true)
        enemy.damage_percent = 0
        enemy.position = Vector3(-1, 0, 0)
        dog.basic_attack(Vector2.UP, false)
        dog._tick_character_move(0.2)
        check(enemy.damage_percent == 0, "uppercut excludes foe behind")
        enemy.position = Vector3.RIGHT
        dog._tick_character_move(0.1)
        check(enemy.damage_percent == 0, "entering uppercut volume after event cannot take a late hit")
        dog.reset_fighter(Vector3.ZERO, true)
        dog._start_doge_attack("Punch1", Vector2.ZERO)
        dog._tick_character_move(0.6)
        dog.start_special(Vector2.UP)
        check(dog.doge_combo_next == 1, "up special clears post-punch followup state")
    dog.queue_free()
    enemy.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge legacy direct punches, uppercut, aerial and lifecycle")
    quit(1 if failures else 0)
