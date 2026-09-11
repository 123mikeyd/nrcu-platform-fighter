extends SceneTree
func _initialize():call_deferred("run")
func run():
    var f=load("res://scripts/fighter.gd").new();f.character_id="witcheer";root.add_child(f);f.set_physics_process(false)
    var ap=f.get_node("VisualRoot/WitcheerVisual").animation_player
    if not ap.has_animation("Celebration"):
        printerr("FAIL: approved source Celebration missing");quit(1);return
    if absf(ap.get_animation("Celebration").length-40.0/24.0)>0.001:
        printerr("FAIL: Celebration exact source duration");quit(1);return
    print("PASS Celebration source asset")
    f.queue_free();await process_frame;quit(0)
