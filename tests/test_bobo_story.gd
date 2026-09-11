extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        print("FAIL: ",message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    arena.open_story()
    arena.story_action.pressed.emit()
    await process_frame
    check(arena.player_two.character_id == "bobo", "first encounter is Bobo")
    check(arena.player_two.get("health") != null, "Bobo has genuine HP")
    if arena.player_two.get("health") != null:
        var bobo = arena.player_two
        arena._cancel_ready()
        bobo.controls_enabled = true
        bobo.receive_hit(10, Vector3.RIGHT, 100)
        check(bobo.health == 390, "one hit consumes actual HP once")
        check(bobo.damage_percent == 0, "HP is not percent")
        bobo.receive_hit(1000, Vector3.RIGHT, 100)
        check(bobo.health == 0 and arena.story_state == "complete", "clamped lethal HP wins Story")
        bobo.receive_hit(10, Vector3.RIGHT, 10)
        check(bobo.health == 0, "defeated target rejects later damage")
        arena.story_action.pressed.emit()
        await process_frame
        check(arena.player_two.health == 400 and arena.story_state == "playing", "Replay restores full HP")
    arena.queue_free()
    await process_frame
    print("BOBO_STORY failures=",failures)
    quit(1 if failures else 0)
