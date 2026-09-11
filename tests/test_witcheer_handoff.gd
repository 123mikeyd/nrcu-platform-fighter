extends SceneTree
func _initialize():call_deferred("run")
func run():
    if not ResourceLoader.exists("res://tools/play_witcheer.gd"):
        printerr("FAIL: dedicated Witcheer launcher missing");quit(1);return
    var arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
    load("res://tools/play_witcheer.gd").configure(arena)
    if arena.setup.rows[0].character.selected!=5 or not arena.setup.visible:
        printerr("FAIL: ready Witcheer preselection");quit(1);return
    arena.setup._start()
    if arena.ready_remaining <= 0 or arena.fighters[0].controls_enabled:
        printerr("FAIL: Start must gate controls during Ready");quit(1);return
    while arena.ready_remaining > 0: await physics_frame
    if arena.fighters.size()!=4 or arena.fighters[0].character_id!="witcheer" or not arena.fighters[0].controls_enabled:
        printerr("FAIL: real Start callback");quit(1);return
    for i in 120:await physics_frame
    arena.show_setup()
    for f in arena.fighters:
        if f.controls_enabled:printerr("FAIL: setup not safe");quit(1);return
    arena.queue_free();await process_frame
    print("PASS: Witcheer ready setup, real Start, four-fighter match and safe return")
    quit()
