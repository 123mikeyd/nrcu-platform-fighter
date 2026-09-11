extends SceneTree
const OUT="res://.verification/evidence/witcheer_launcher/"
static func configure(arena):
    var config=load("res://scripts/match_config.gd")
    var characters=["witcheer","doge_man","teknium","turbofit"]
    arena.setup.mode.select(0)
    for i in 4:
        var row=arena.setup.rows[i]
        row.character.select(config.CHARACTERS.find(characters[i]))
        row.kind.select(0 if i==0 else 1)
        row.difficulty.select(1)
        row.team.select(i%2)
        row.device.select(0)
    arena.setup._refresh()
func _initialize():call_deferred("run")
func run():
    var arena=load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    configure(arena)
    DisplayServer.window_set_title("NRCU Fighter — Witcheer Revised Kit / Ready to Start")
    print("READY: WITCHEER REVISED KIT. Click START MATCH. A/D move; Space jump; F high kick / air punch; S+F ground cane sweep; air W+F upward basic; G celebrate; A/D+G fast coin toss; W+G rising swim; S+G projectile-healing dance. Esc: safe setup. Timing/balance provisional; dedicated idle/jump deferred.")
    if "--smoke" in OS.get_cmdline_user_args():
        arena.setup._start()
        if arena.fighters.size()!=4 or arena.fighters[0].character_id!="witcheer":
            printerr("FAIL: Witcheer Start callback");quit(1);return
        for i in 120:await physics_frame
        arena.show_setup()
        if not arena.setup.visible or arena.fighters[0].controls_enabled:
            printerr("FAIL: Witcheer safe setup return");quit(1);return
        print("PASS: Witcheer dedicated Start, 120-frame match, safe setup return")
        quit()
    elif "--capture-setup" in OS.get_cmdline_user_args():
        for i in 15:await process_frame
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(OUT+"witcheer_ready_to_start.png")
        print("SETUP_CAPTURED; awaiting user Start, no match running")
