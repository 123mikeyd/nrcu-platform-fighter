extends SceneTree

var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)
func _init() -> void:
    call_deferred("run")
func run() -> void:
    root.size = Vector2i(1280, 720)
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    for i in range(5):
        await process_frame
    var menu = arena.setup
    check(menu.visible and menu.rows.size() == 4, "four-slot setup opens by default")
    for button in menu.find_children("*", "Button", true, false):
        check(button.get_global_rect().end.y <= 720, "button fits inside viewport: " + button.text)
    menu.rows[0].kind.select(2)
    menu.rows[1].kind.select(2)
    menu.rows[2].kind.select(2)
    menu._start()
    check(menu.visible and not menu.error_label.text.is_empty(), "invalid single fighter setup blocked in UI")
    menu.rows[0].kind.select(0)
    menu.rows[1].kind.select(1)
    menu.rows[2].kind.select(1)
    menu.mode.select(1)
    for row in menu.rows:
        row.team.select(0)
    menu._start()
    check(not menu.error_label.text.is_empty(), "same-team match rejected in UI")
    menu.rows[1].team.select(1)
    menu._start()
    check(arena.fighters.size() == 4 and not menu.visible and arena.teams_enabled, "UI starts actual four-player team match")
    arena.show_setup()
    check(menu.visible, "setup can reopen during match")
    for fighter in arena.fighters:
        check(not fighter.controls_enabled, "fighters freeze while selecting")
    arena.queue_free()
    await process_frame
    if not failures:
        print("PASS: match setup layout, validation, Start and return flow")
    quit(1 if failures else 0)
