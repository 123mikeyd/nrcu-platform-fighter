extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var dog = F.new()
    dog.character_id = "doge_man"
    root.add_child(dog)
    dog.set_physics_process(false)
    var enemy = F.new()
    enemy.character_id = "ice_mage"
    enemy.player_index = 1
    root.add_child(enemy)
    enemy.set_physics_process(false)
    check(dog.has_method("_query_doge_two_piece"), "two-piece exposes post-movement fist contact query")
    if not dog.has_method("_query_doge_two_piece"):
        dog.queue_free(); enemy.queue_free()
        await process_frame
        quit(1); return
    # Synthetic timing+Idle fixture tests event/contact logic, not authored art.
    var view = dog._visual_root.get_node("DogeVisual")
    var ap: AnimationPlayer = view.animation_player
    var library: AnimationLibrary = ap.get_animation_library("")
    if library.has_animation("TysonTwoPiece"): library.remove_animation("TysonTwoPiece")
    var fixture: Animation = ap.get_animation("Idle").duplicate(true)
    fixture.length = 1.0
    fixture.loop_mode = Animation.LOOP_NONE
    library.add_animation("TysonTwoPiece", fixture)
    dog.doge_attack_timings.TysonTwoPiece = {"duration": 1.0, "hits": [
        {"time": 0.25, "bone": "LeftHand", "damage": 4.0, "knockback": 0.1, "radius": 0.2},
        {"time": 0.5, "bone": "RightHand", "damage": 12.0, "knockback": 5.5, "radius": 0.2}]}
    var skeleton: Skeleton3D = view.model.find_children("*", "Skeleton3D", true, false)[0]
    for facing in [1.0, -1.0]:
        dog.reset_fighter(Vector3.ZERO, true)
        enemy.reset_fighter(Vector3.ZERO, true)
        dog.facing = facing
        dog.basic_attack(Vector2(facing, 1), false)
        dog._tick_character_move(0.24)
        dog._query_doge_two_piece()
        check(enemy.damage_percent == 0, "no input/windup damage")
        for event in dog.doge_attack_timings.TysonTwoPiece.hits:
            dog._tick_character_move(float(event.time) - dog.doge_attack_elapsed)
            dog._update_move_visuals()
            skeleton.force_update_all_bone_transforms()
            var fist: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(event.bone)).origin
            enemy.position = Vector3(fist.x + facing * 0.15, fist.y - 0.9, fist.z)
            dog._query_doge_two_piece()
            var expected := 4.0 if event.bone == "LeftHand" else 16.0
            check(enemy.damage_percent == expected, "actual fist capsule overlap hits once " + str(event.bone) + " facing=" + str(facing))
            if event.bone == "LeftHand":
                dog.basic_attack(Vector2.ZERO, false)
                check(enemy.velocity.length() <= 0.20001, "setup jab caps displacement, not damage/hitstun, so rising right retains reach")
            dog._query_doge_two_piece()
            check(enemy.damage_percent == expected, "repeated queries cannot duplicate event")
        check(enemy.velocity.x * facing > 0 and enemy.velocity.y > 0, "haymaker knocks foe forward/up")
        dog._tick_character_move(0.5)
        check(dog.doge_attack_clip.is_empty(), "recovery ends complete episode")
    for scenario in ["far", "behind", "team", "menu", "hit", "jump", "reset", "stock", "freeze", "grab"]:
        dog.reset_fighter(Vector3.ZERO, true)
        enemy.reset_fighter(Vector3.RIGHT, true)
        dog.team_id = -1; enemy.team_id = -1
        dog.basic_attack(Vector2(1, 1), false)
        match scenario:
            "far": enemy.position.x = 10
            "behind": enemy.position.x = -1
            "team": dog.team_id = 0; enemy.team_id = 0
            "menu": dog.controls_enabled = false
            "hit": dog.receive_hit(1, Vector3.LEFT, 1)
            "jump": dog.try_jump()
            "reset": dog.reset_fighter(Vector3.ZERO, true)
            "stock": dog.lose_stock()
            "freeze": dog.apply_freeze(enemy)
            "grab": dog.cancel_for_grab()
        dog._tick_character_move(0.5)
        dog._query_doge_two_piece()
        check(enemy.damage_percent == 0, "no inappropriate contact after " + scenario)
    dog.queue_free(); enemy.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge two-piece events, fist-local contact, both facings, misses, teams and interruptions")
    quit(1 if failures else 0)
