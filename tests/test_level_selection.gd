extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        print("FAIL: " + message)
func run():
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    if not arena.setup.has_method("selected_level"):
        print("FAIL: setup has no level selection")
        arena.queue_free()
        await process_frame
        quit(1)
        return
    check(arena.active_level == "debug", "debug default")
    var bodies: Array = []
    for n in arena.get_children():
        if n is StaticBody3D:
            bodies.append([n, n.transform, n.collision_layer, n.get_child(1).shape.size])
    arena.setup.level.select(1)
    check(arena.active_level == "debug", "selection waits for Start")
    arena.setup._start()
    check(arena.active_level == "toy_room" and not arena.setup.visible, "actual Start applies toy room")
    for b in bodies:
        check(is_instance_valid(b[0]) and b[0].transform == b[1] and b[0].collision_layer == b[2] and b[0].get_child(1).shape.size == b[3], "same collision instance/layout")
    arena._reset_match()
    check(arena.active_level == "toy_room", "rematch retains stage")
    arena.show_setup()
    arena.setup.level.select(2)
    arena.setup._start()
    check(arena.active_level == "sky", "switch to sky")
    # Story route (WP-0 step 4): the encounter's stage comes from StoryEncounter
    # Catalog, so the story launch never reads the debug setup's level dropdown.
    var catalog = load("res://scripts/catalogs/story_encounter_catalog.gd")
    var encounter_stage := str(catalog.by_id("story_01")["stage_id"])
    var story = load("res://tests/fixtures/story_route.gd").new()
    var host = await story.enter(self)
    var story_arena = await story.start_encounter(self, host)
    check(story_arena != null and story_arena.story_state == "playing", "story launches through MatchFlow")
    if story_arena != null:
        check(story_arena.active_level == encounter_stage, "story uses the encounter's catalog stage")
        check(story_arena.active_level == "debug", "the encounter's effective stage is the recorded default")
        check(story_arena.active_level != arena.active_level, "the story stage never follows the debug dropdown")
        story_arena.queue_free()
    await story.free_hosts(self)
    arena.show_setup()
    arena.setup.level.select(0)
    arena.setup._start()
    check(arena.active_level == "debug" and arena.stage_theme == null, "debug restoration cleans theme")
    for n in arena.debug_visuals: check(n.visible, "debug visuals restored")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: level selection Start, collisions, rematch, story/replay, debug restoration")
    quit(1 if failures else 0)
