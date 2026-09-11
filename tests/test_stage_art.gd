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
    arena.setup.level.select(1)
    arena.setup._start()
    var theme = arena.stage_theme
    var figures = theme.find_children("Figure_*", "Node3D", true, false)
    check(figures.size() == 7, "all seven roster figurines")
    for id in preload("res://scripts/roster.gd").ids():
        var figure = theme.find_child("Figure_" + id, true, false)
        check(figure != null, "roster display " + id)
        if figure:
            check(figure.get_child(0).scale.y < 3.0 and figure.get_child(0).scale.y > 0.05, "figurine sane imported scale")
            check(figure.process_mode == Node.PROCESS_MODE_DISABLED, "frozen figurine")
            check(not figure.find_children("*", "MeshInstance3D", true, false).is_empty(), "actual model meshes")
            for player in figure.find_children("*", "AnimationPlayer", true, false):
                check(not player.is_playing(), "idle pose paused")
    check(theme.find_children("*", "CollisionObject3D", true, false).is_empty(), "no decor colliders")
    arena.show_setup()
    arena.setup.level.select(2)
    arena.setup._start()
    await process_frame
    check(not is_instance_valid(theme), "old theme freed")
    var video = arena.stage_theme.find_child("CloudVideo", true, false)
    check(video != null, "real cloud video")
    if video: check(video.loop and video.is_playing() and video.stream != null, "looping video playing")
    check(arena.stage_theme.find_children("*", "CollisionObject3D", true, false).is_empty(), "sky collision-free")
    check(arena.stage_theme.find_child("HUDContrast",true,false) != null, "readable HUD backing")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: roster-complete frozen models, collision-free themes, cleanup, looping video")
    quit(1 if failures else 0)
