extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    print(("PASS " if ok else "FAIL ") + message)
    if not ok: failures += 1
func run():
    var view = load("res://scripts/frontend/fighter_render_view.gd").new()
    root.add_child(view)
    view.set_subjects(["turbofit", "bobo"])
    view.set_presentation_mode(view.MODE_LIVE_IDLE)
    await process_frame
    check(view.find_children("*", "SubViewport", true, false).is_empty(), "static menu never constructs preview viewport")
    check(view.subject_nodes().is_empty(), "static menu never constructs fighter")
    check(not view.is_animating(), "static menu never animates")
    view.queue_free()
    for scene_path in ["res://scenes/title.tscn", "res://scenes/home.tscn", "res://scenes/match_flow.tscn"]:
        change_scene_to_file(scene_path)
        for i in 5: await process_frame
        check(current_scene.find_children("*", "SubViewport", true, false).is_empty(), scene_path + " has zero hidden/offscreen preview viewports")
        check(current_scene.find_children("*", "Skeleton3D", true, false).is_empty(), scene_path + " has zero character skeletons")
    quit(0 if failures == 0 else 1)
