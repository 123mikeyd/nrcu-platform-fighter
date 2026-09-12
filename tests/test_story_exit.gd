extends SceneTree
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
    for i in 2: await process_frame
    var stage = arena.story_panel.find_child("StoryStage", true, false)
    check(arena.story_panel.visible, "story open")
    if stage != null:
        arena.story_back.pressed.emit()
        await create_timer(0.05).timeout
        check(stage.is_exiting(), "exit animation started")
        await create_timer(0.5).timeout
        check(not arena.story_panel.visible, "story closed after the exit animation")
        check(stage.get_input_lock() > 0.0 or not arena.story_panel.visible, "inputs locked during exit")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: story exit animation path")
    quit(1 if failures else 0)
