extends SceneTree
func _initialize():call_deferred("run")
func run():
    if not ResourceLoader.exists("res://tools/play_ggb.gd"):
        printerr("FAIL: dedicated GGB ready-to-start launcher missing")
        quit(1);return
    var arena=load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    var launch=load("res://tools/play_ggb.gd")
    launch.configure(arena)
    if arena.setup.rows[0].character.get_item_text(arena.setup.rows[0].character.selected)!="GGB" or not arena.setup.visible or not arena.fighters.is_empty():
        printerr("FAIL: P1 GGB must be selected without combat running")
        quit(1);return
    arena.setup._start()
    arena._physics_process(arena.ready_remaining) # Advance the real Ready gate before combat fixtures.
    var f=arena.fighters[0]
    if arena.fighters.size()!=4 or f.character_id!="ggb" or f.control_type!="human":
        printerr("FAIL: actual Start must create P1 GGB plus three bots")
        quit(1);return
    for other in arena.fighters.slice(1):
        if other.control_type!="bot":
            printerr("FAIL: requested bots")
            quit(1);return
    f.set_physics_process(false)
    f.position=Vector3(0,7,0)
    f.start_special(Vector2.DOWN)
    var v=f.get_node("VisualRoot/GGBVisual")
    if not v.is_lead:
        printerr("FAIL: pre-menu lead state")
        quit(1);return
    arena.show_setup()
    if v.is_lead or f.drop_committed or not arena.setup.visible or f.controls_enabled:
        printerr("FAIL: actual menu callback must synchronously restore GGB")
        quit(1);return
    arena.setup._start()
    arena._physics_process(arena.ready_remaining) # Advance the real Ready gate before combat fixtures.
    f=arena.fighters[0]
    f.set_physics_process(false)
    f.position.y=7
    f.start_special(Vector2.DOWN)
    for other in arena.fighters.slice(1):other.stocks=0
    arena._on_fighter_eliminated(arena.fighters[1])
    if not arena.match_over or f.get_node("VisualRoot/GGBVisual").is_lead or f.drop_committed:
        printerr("FAIL: actual winner cleanup must restore GGB")
        quit(1);return
    arena.queue_free()
    await process_frame
    print("PASS: dedicated GGB setup/Start/bots and synchronous menu/winner restoration")
    quit()
