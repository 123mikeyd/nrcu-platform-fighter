extends SceneTree
static func configure(arena):
    var config=load("res://scripts/match_config.gd")
    arena.setup.mode.select(0)
    arena.setup.level.select(0)
    for i in 4:
        var row=arena.setup.rows[i]
        row.character.select(config.CHARACTERS.find("mephisto" if i==0 else "doge_man"))
        row.kind.select(0 if i==0 else (1 if i==1 else 2))
        row.difficulty.select(0)
        row.team.select(i%2)
        row.device.select(0)
    arena.setup._refresh()
    arena.setup.error_label.text="Mephisto: girl only. Idle / Run / provisional Block8 reaction. Generic combat; demon & smoke later."
func _initialize():call_deferred("run")
func run():
    var arena=load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    configure(arena)
    DisplayServer.window_set_title("NRCU — Mephisto Girl / Ready to Start")
    print("READY: Mephisto girl. Click START MATCH. A/D move, Space jump, F generic basic, G hold/release generic charge, A/D+G placeholder bolt, W+G generic recovery, E shield. S+G unassigned. No dedicated attack/jump clips or demon powers. Esc returns to safe setup.")
    if "--smoke" in OS.get_cmdline_user_args():
        arena.setup._start()
        if arena.fighters.size()!=2 or arena.fighters[0].character_id!="mephisto":
            printerr("FAIL: Mephisto Start");quit(1);return
        for i in 120:await physics_frame
        arena.show_setup()
        if not arena.setup.visible or arena.fighters[0].controls_enabled:
            printerr("FAIL: Mephisto safe return");quit(1);return
        print("PASS: Mephisto Start, 120 physics frames and safe return")
        quit()
