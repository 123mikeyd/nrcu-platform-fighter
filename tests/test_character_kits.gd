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
    dog.start_special(Vector2.RIGHT)
    check(get_nodes_in_group("projectiles").is_empty(), "Doge tackle has no projectile")
    check(dog.has_method("_tick_character_move"), "character move lifecycle")
    if dog.has_method("_tick_character_move"):
        check(dog.torpedo_phase == "launch" and dog.tackle_active == 0, "tackle starts with non-damaging launch")
        dog._tick_character_move(dog.TORPEDO_LAUNCH_TIME)
        check(dog.torpedo_phase == "tackle" and dog.tackle_active > 0 and dog.velocity.x > 0, "launch enters horizontal flying tackle")
        dog._tick_character_move(1)
        dog.attack_cooldown = 0
        dog.start_special(Vector2.RIGHT)
        check(dog.tackle_active == 0, "one tackle per airtime")
        dog.reset_fighter(Vector3.ZERO, true)
        dog.recovery_spent = true
        dog.start_special(Vector2.RIGHT)
        check(dog.tackle_active == 0 and dog.torpedo_phase == "idle", "tackle cannot bypass spent recovery")
    var emo = F.new()
    emo.character_id = "ggb"
    root.add_child(emo)
    emo.set_physics_process(false)
    var previous := INF
    for i in 5:
        check(emo.try_jump(), "Emo jump %d" % i)
        check(emo.velocity.y < previous, "diminishing jump")
        previous = emo.velocity.y
    check(not emo.try_jump(), "five jump limit")
    emo.start_special(Vector2.DOWN)
    check(emo.last_move == "HEAVY DROP", "Emo heavy drop")
    if emo.has_method("_tick_character_move"):
        check(emo.drop_committed and not emo.try_jump(), "drop commits until floor")
        emo._land_character_move()
        check(not emo.drop_committed and emo.attack_cooldown >= 0.5, "drop landing lag")
        emo.jumps_used = 0
        check(not emo.try_jump(), "landing lag cannot be jump canceled")
    var turbo = F.new()
    turbo.character_id = "turbofit"
    root.add_child(turbo)
    turbo.set_physics_process(false)
    check(turbo._visual_root.get_node_or_null("Guitar") == null, "primitive guitar placeholder removed")
    check(turbo.get_node("PlayerLabel").no_depth_test, "player labels readable through stage")
    check(turbo.get_node("PlayerLabel").text == "P1", "compact player label")
    turbo.last_move = "GUITAR SWING"
    turbo.attack_cooldown = 0.5
    turbo._update_move_visuals()
    check(turbo._move_status.text == "", "ordinary attacks do not clutter overhead labels")
    turbo.attack_cooldown = 0

    turbo.position.x = 4
    emo.position.x = 5
    emo.damage_percent = 0
    turbo.basic_attack(Vector2.RIGHT, false)
    check(emo.damage_percent == 0, "basic strike windup delays damage without prop")
    check(turbo.swing_windup == 0.28 and turbo.attack_cooldown == 0.8, "basic strike retains original windup and cooldown")
    turbo._update_move_visuals()
    check(turbo.get_node("VisualRoot/TurboFitVisual").current_clip == "MeleeHorizontal", "basic strike retains original motion without prop")
    if turbo.has_method("_tick_character_move"):
        turbo._tick_character_move(0.279)
        check(emo.damage_percent == 0, "basic strike cannot hit before original windup")
        turbo._tick_character_move(0.002)
        check(emo.damage_percent == 14 and turbo.swing_followthrough == 0.22, "basic strike connects after original windup with unchanged followthrough")
        turbo._tick_character_move(0.4)
        check(emo.damage_percent == 14, "basic strike hits only once without prop")
    for f in [dog, emo, turbo]: f.queue_free()
    await process_frame
    if failures == 0: print("PASS character kits")
    quit(1 if failures else 0)
