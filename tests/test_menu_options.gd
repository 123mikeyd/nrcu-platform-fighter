extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func settle() -> void:
    # Long enough to pass any action cooldown (0.083) between test actions.
    await create_timer(0.1).timeout
func run():
    var menu = load("res://scripts/menu_options.gd").new()
    var host := Control.new()
    host.size = Vector2(600, 400)
    root.add_child(host)
    host.add_child(menu)
    var sounds: Array = []
    menu.sound_requested.connect(func(k): sounds.append(k))
    var backs := [0]
    menu.back_requested.connect(func(): backs[0] += 1)
    var confirmed_rows: Array = []
    menu.confirmed.connect(func(i): confirmed_rows.append(i))
    var changed_pairs: Array = []
    menu.changed.connect(func(i, v): changed_pairs.append([i, v]))
    menu.build([
        {"label": "Alpha", "kind": "value", "values": ["One", "Two", "Three"], "value": 0, "enabled": true},
        {"label": "Grey", "kind": "value", "values": ["x", "y"], "value": 0, "enabled": false},
        {"label": "Bravo", "kind": "value", "values": ["A", "B"], "value": 0, "enabled": true},
        {"label": "Go", "kind": "action", "enabled": true},
    ])
    check(menu.rows.size() == 4, "rows built")
    check(menu.focus == 0, "initial focus on first enabled row")
    check(menu.get_cooldown() > 0.0, "scene-start cooldown active")
    menu.move_focus(1)
    check(menu.focus == 0, "input swallowed during scene-start cooldown")
    await create_timer(0.4).timeout

    menu.move_focus(1)
    check(menu.focus == 2, "focus skips disabled rows")
    menu.move_focus(1)
    check(menu.focus == 3, "focus reaches the action row")
    menu.move_focus(1)
    check(menu.focus == 0, "focus wraps around")
    menu.move_focus(-1)
    check(menu.focus == 3, "focus wraps backwards, skipping disabled")
    menu.adjust(1)
    check(menu.focus == 3 and confirmed_rows.is_empty(), "adjust does nothing on an action row")
    menu.move_focus(-1)
    check(menu.focus == 2, "moved to a value row")

    menu.adjust(1)
    check(int(menu.rows[2]["value"]) == 1 and changed_pairs.size() == 1, "value changed + signal")
    await settle()
    menu.adjust(1)
    check(int(menu.rows[2]["value"]) == 0, "value wraps at the limit")
    await settle()
    menu.confirm()
    check(int(menu.rows[2]["value"]) == 1, "confirm on a value row steps the value")
    await settle()
    menu.move_focus(1)
    check(menu.focus == 3, "to the action row")
    menu.adjust(1)
    check(confirmed_rows.is_empty(), "adjust is silent on an action row")
    menu.confirm()
    check(confirmed_rows == [3], "confirm fires on an action row")
    menu.move_focus(1)
    check(menu.focus == 3, "post-action cooldown swallows the next input")
    await settle()
    menu.go_back()
    check(backs[0] == 1, "back requested")
    check("back" in sounds and "move" in sounds and "forward" in sounds, "sound hooks fired")
    await settle()

    # hold-to-scroll: keep the key held; count move sounds (with 4 rows the
    # focus wrap can land back on the start row after N steps)
    var moves_before := 0
    for s in sounds:
        if s == "move": moves_before += 1
    menu.set_nav_held(1)
    await create_timer(0.9).timeout
    menu.set_nav_held(0)
    var moves_after := 0
    for s in sounds:
        if s == "move": moves_after += 1
    check(moves_after >= moves_before + 2, "hold-to-scroll repeats while held")
    host.queue_free()
    await process_frame
    if failures == 0: print("PASS: menu options widget (navigation, cooldown, wrap, skip, hold, hooks)")
    quit(1 if failures else 0)
