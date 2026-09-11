extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func frames(n):
    for i in n: await physics_frame
    await process_frame
func key(code,down):
    var e := InputEventKey.new()
    e.keycode = code
    e.pressed = down
    Input.parse_input_event(e)
    Input.flush_buffered_events()
func run():
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    arena.open_story()
    for index in arena.story_character.item_count:
        arena.story_character.select(index)
        arena.story_action.pressed.emit()
        await frames(120)
        var hero = arena.player_one
        var bobo = arena.player_two
        hero.reset_fighter(Vector3(-1.2,0.1,0),true)
        bobo.reset_fighter(Vector3(0,0.1,0),true)
        await frames(30)
        hero.facing = 1
        key(KEY_F,true)
        await frames(2)
        key(KEY_F,false)
        await frames(90)
        print("ROSTER_HP ",hero.character_id," ",bobo.health," reactions ",bobo.reaction_serial)
        check(bobo.health < 400, hero.character_id + " real neutral basic can damage Bobo")
        check(bobo.damage_percent == 0 and bobo.position.distance_to(Vector3(0,-0.05,0)) < 0.15, "stationary HP target stays grounded")
        check(not bobo.can_hit(hero) and not bobo.try_jump(), "Bobo direct APIs cannot attack or jump")
        var hp: float = hero.damage_percent
        bobo.basic_attack(Vector2.ZERO,false)
        bobo.start_special(Vector2.ZERO)
        bobo.release_special()
        await frames(60)
        check(hero.damage_percent == hp, "Bobo direct attack APIs remain harmless")
    arena.queue_free()
    await process_frame
    print("BOBO_ROSTER failures=",failures)
    quit(1 if failures else 0)
