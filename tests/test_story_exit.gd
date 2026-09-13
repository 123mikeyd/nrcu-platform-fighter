extends SceneTree
# Story exit path (Doc 07 §11-16): the briefing's exit animation replaces the
# retired StoryStage flow.
#
# This suite previously guarded every assertion behind a removed node and
# passed VACUOUSLY with zero checks. It is migrated so that the legacy node
# being gone is itself asserted, and the exit contract runs unconditionally.
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func run():
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    for i in 5: await process_frame
    arena.setup.story_requested.emit()
    for i in 3: await process_frame
    check(arena.story_panel.visible, "story open")
    check(arena.story_panel.find_child("StoryStage", true, false) == null,
        "the legacy StoryStage overlay is gone (asserted, not assumed)")
    check(arena.story_panel.find_child("FighterCard0", true, false) == null,
        "the legacy card row is gone")
    var briefing = arena.story_briefing
    check(briefing != null, "the briefing owns the story panel")
    if briefing == null:
        arena.queue_free()
        await process_frame
        quit(1 if failures else 0)
        return
    arena.story_back.pressed.emit()
    await create_timer(0.05).timeout
    check(briefing.is_exiting(), "exit animation started")
    await create_timer(0.9).timeout
    check(not arena.story_panel.visible, "story closed after the exit animation")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: story exit animation path (briefing, unconditional checks)")
    quit(1 if failures else 0)
