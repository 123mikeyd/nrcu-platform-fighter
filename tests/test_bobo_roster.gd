extends SceneTree
# Bobo roster contract — every playable Story fighter launches the encounter
# through the TWO-STEP MatchFlow story route: the Story Fighter Select commits
# the fighter, Continue steps into the Briefing, and the frontend freezes the
# config.
var failures := 0
var story
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func frames(n: int):
    for i in n: await physics_frame
    await process_frame
func key(code: int,down: bool):
    var e := InputEventKey.new()
    e.keycode = code
    e.pressed = down
    Input.parse_input_event(e)
    Input.flush_buffered_events()
func run():
    root.size = Vector2i(1280, 720)
    story = load("res://tests/fixtures/story_route.gd").new()
    var roster = load("res://scripts/roster.gd")
    var encounter = load("res://scripts/catalogs/story_encounter_catalog.gd")
    var playable: Array = []
    for id in encounter.allowed_fighter_ids("story_01"):
        playable.append(str(id))
    var expected: Array = []
    for id in roster.ids():
        if str(id) != "ice_mage":
            expected.append(str(id))
    check(playable == expected, "the encounter catalogue owns the playable roster (prototype excluded)")
    for id in playable:
        var chosen := str(id)
        var host = await story.enter(self, chosen)
        var select = host.story_select()
        check(select.selected_fighter_id() == chosen, "the Story Select opens on the roster choice " + chosen)
        var arena = await story.start_encounter(self, host)
        if arena == null:
            check(false, "the encounter launches for " + chosen)
            continue
        check(arena.player_one.character_id == chosen, "the story launch uses " + chosen)
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
        await story.free_hosts(self)
    await process_frame
    print("BOBO_ROSTER failures=",failures)
    quit(1 if failures else 0)
