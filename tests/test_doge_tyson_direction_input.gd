extends SceneTree
# Production reads raw keys, not InputMap actions. Inject real InputEventKey
# press/release events and run the full fighter physics callback on real terrain.
const F = preload("res://scripts/fighter.gd")
var failures := 0
var cases := 0
var dog
var keys: Array
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func key(code: int, down: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()
func advance(seconds: float) -> void:
    var left := seconds
    while left > 0.000001:
        var dt := minf(left, 0.01)
        await physics_frame
        dog._physics_process(dt)
        left -= dt
func release_all() -> void:
    for code in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_F, KEY_SPACE, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_K, KEY_ENTER]:
        key(code, false)
func aim(direction: Vector2) -> void:
    key(keys[0], direction.x < 0)
    key(keys[1], direction.x > 0)
    key(keys[2], direction.y < 0)
    key(keys[3], direction.y > 0)
func opener(facing: float) -> void:
    release_all()
    dog.reset_fighter(Vector3.ZERO, true)
    dog.facing = facing
    await advance(0.1)
    check(dog.is_grounded(), "fixture has terrain grounding")
    aim(Vector2.DOWN)
    key(keys[4], true)
    await advance(0.01)
    check(dog.doge_attack_clip == "TysonTwoPiece", "grounded down+attack opens Tyson")
func _initialize() -> void: call_deferred("run")
func run() -> void:
    dog = F.new()
    dog.character_id = "doge_man"
    root.add_child(dog)
    dog.set_physics_process(false)
    var floor_body := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(100, 1, 5)
    shape.shape = box
    floor_body.position.y = -0.5
    floor_body.add_child(shape)
    root.add_child(floor_body)
    var directions := {"neutral": Vector2.ZERO, "left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN, "up_left": Vector2(-1,-1), "up_right": Vector2(1,-1), "down_left": Vector2(-1,1), "down_right": Vector2(1,1)}
    for player in [1, 2]:
        dog.player_index = player
        keys = [KEY_A, KEY_D, KEY_W, KEY_S, KEY_F] if player == 1 else [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_K]
        for facing in [1.0, -1.0]:
            for label in directions:
                var before := failures
                await opener(facing)
                key(keys[4], false)
                # Keep DOWN held from the opener until selecting the followup:
                # the down case NEVER passes through neutral.
                await advance(0.2)
                aim(directions[label])
                await advance(0.02) # Direction is already held before the new edge.
                key(keys[4], true)
                await advance(0.01)
                check(dog.doge_tyson_followup, "P%d facing%s %s fresh edge commits second punch" % [player, facing, label])
                check(dog.doge_attack_facing == facing and dog.facing == facing, "followup keeps committed facing")
                check(dog.is_grounded() and dog.jumps_used == 0, "up chord does not jump")
                check(not dog.doge_punch_buffered, "second press does not queue a new combo")
                cases += 1
                print("CASE P%d facing%s %s %s" % [player, facing, label, "PASS" if before == failures else "FAIL"])
        # Guard existing edge/lifecycle/window behavior for each keyboard layout.
        var before := failures
        await opener(1.0)
        await advance(0.4)
        check(not dog.doge_tyson_followup, "P%d held opener never commits second punch" % player)
        await advance(1.2)
        check(dog.doge_attack_clip.is_empty() and not dog.doge_punch_buffered, "held opener never repeats after recovery")
        cases += 1
        print("CASE P%d held_opener %s" % [player, "PASS" if before == failures else "FAIL"])
        for press_time in [0.10, 0.16, 0.34, 0.40]:
            before = failures
            await opener(1.0)
            key(keys[4], false)
            await advance(press_time - float(dog.doge_attack_elapsed))
            var actual_time: float = dog.doge_attack_elapsed
            key(keys[4], true)
            await advance(0.01)
            var expected: bool = press_time >= 0.15 and press_time <= 0.35
            check(dog.doge_tyson_followup == expected, "P%d unchanged commit window at %.3f" % [player, actual_time])
            if not expected:
                await advance(0.1)
                check(not dog.doge_tyson_followup, "outside-window edge cannot commit later while held")
            else:
                await advance(1.3)
                check(dog.doge_attack_clip.is_empty() and not dog.doge_punch_buffered, "held second press never repeats")
            cases += 1
            print("CASE P%d window_%.3f %s" % [player, actual_time, "PASS" if before == failures else "FAIL"])
        before = failures
        await opener(1.0)
        key(keys[4], false)
        await advance(0.2)
        key(KEY_SPACE if player == 1 else KEY_ENTER, true)
        await advance(0.01)
        check(dog.jumps_used == 1 and dog.doge_attack_clip.is_empty(), "dedicated jump still cancels Tyson")
        cases += 1
        print("CASE P%d explicit_jump %s" % [player, "PASS" if before == failures else "FAIL"])
        before = failures
        release_all()
        dog.reset_fighter(Vector3.ZERO, true)
        await advance(0.1)
        aim(Vector2.UP)
        await advance(0.01)
        check(dog.jumps_used == 1, "ordinary tap-up still jumps outside Tyson")
        cases += 1
        print("CASE P%d ordinary_tap_up %s" % [player, "PASS" if before == failures else "FAIL"])
        for interruption in ["hit", "controls", "reset"]:
            before = failures
            await opener(1.0)
            key(keys[4], false)
            await advance(0.2)
            key(keys[4], true)
            await advance(0.01)
            check(dog.doge_tyson_followup, "fixture commits before interruption")
            key(keys[4], false)
            if interruption == "hit":
                dog.receive_hit(5.0, Vector3.LEFT, 2.0)
            elif interruption == "controls":
                dog.controls_enabled = false
            else:
                dog.reset_fighter(Vector3.ZERO, true)
            await advance(0.01)
            check(dog.doge_attack_clip.is_empty() and not dog.doge_tyson_followup and not dog.doge_punch_buffered, "interruption clears committed followup and buffer")
            if interruption != "reset":
                key(keys[4], true)
                await advance(0.01)
                check(dog.doge_attack_clip.is_empty() and not dog.doge_tyson_followup, "fresh edge while interrupted cannot resurrect combo")
            cases += 1
            print("CASE P%d interrupt_%s %s" % [player, interruption, "PASS" if before == failures else "FAIL"])
    release_all()
    dog.queue_free()
    floor_body.queue_free()
    await process_frame
    print("PASS TYSON_DIRECTION_INPUT_COMPLETE cases=%d failures=%d" % [cases, failures])
    quit(1 if failures else 0)
