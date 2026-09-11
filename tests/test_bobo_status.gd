extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
    if not ok:
        failures += 1
        printerr("FAIL: ",message)
func run():
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    arena.open_story()
    arena.story_character.select(0)
    arena.start_story()
    arena._physics_process(arena.ready_remaining)
    var hero = arena.player_one
    var bobo = arena.player_two
    hero.set_physics_process(false)
    bobo.set_physics_process(false)
    check(bobo.has_method("apply_status_damage"), "Bobo status ticks deplete HP instead of percent")
    if bobo.has_method("apply_status_damage"):
        check(bobo.apply_freeze(hero), "freeze accepts real enemy")
        bobo.apply_status_damage(3)
        check(bobo.health == 397 and bobo.freeze_remaining > 0 and bobo.damage_percent == 0, "status HP does not thaw or change percent")
        bobo._clear_freeze()
        hero.position = Vector3(-1.35,0,0)
        bobo.position = Vector3.ZERO
        hero.facing = 1
        hero.start_special(Vector2.ZERO)
        var magic = hero.teknium_magic
        magic.tick(0.2)
        check(bobo.caught_by == magic, "real electric grab captures Bobo")
        magic.tick(4.0/24)
        magic.tick(0.25)
        check(bobo.health == 395 and bobo.damage_percent == 0, "real electric tick reduces HP without percent")
        magic.cancel()
        bobo.apply_burn(hero)
        bobo.burn.tick(0.5)
        check(bobo.health == 394, "real burn tick reduces HP")
        bobo.burn.clear()
        bobo.shielding = true
        bobo.receive_hit(10,Vector3.RIGHT,4)
        check(is_equal_approx(bobo.health,390.5), "shield damage scales once")
        bobo.shielding = false
        bobo.apply_status_damage(1000)
        check(bobo.health == 0 and arena.story_state == "complete", "status damage can win")
    arena.queue_free()
    await process_frame
    quit(1 if failures else 0)
