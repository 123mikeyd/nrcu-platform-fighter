extends SceneTree
# Visual contract for the shared binary overlay language used by Pause and Quit.
# This is deliberately a live-tree contract: the two route wrappers may own
# different semantics, but they must present the same shell and MenuRow choice
# grammar to the player.

var failures := 0

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func settle(frames: int = 3) -> void:
    for _i in frames:
        await process_frame

func rect(node: Control) -> Rect2:
    return node.get_global_rect()

func row_parts(row: Control) -> bool:
    for child_name in ["ActivePlate", "Label", "QuietRail", "ActiveRail", "CursorAnchor"]:
        check(row.has_node(child_name), "%s carries %s" % [str(row.name), child_name])
    check(row.get_node("ActivePlate").has_node("TopRule"), "%s carries the shared TopRule" % str(row.name))
    return true

func run() -> void:
    root.size = Vector2i(1280, 720)

    var pause := (load("res://scripts/frontend/pause_overlay.gd").new()) as Control
    root.add_child(pause)
    await settle(8)
    pause.open(false)
    await settle(4)

    var home := (load("res://scenes/home.tscn") as PackedScene).instantiate()
    root.add_child(home)
    await settle(24)
    home._open_quit_modal()
    await settle(12)

    var pause_plate: Panel = pause.find_child("Plate", true, false)
    var quit_plate: Panel = home.find_child("Plate", true, false)
    check(pause_plate != null and quit_plate != null, "both overlays expose a visual plate")
    if pause_plate != null and quit_plate != null:
        check(pause_plate.get_global_rect().size == quit_plate.get_global_rect().size,
            "Pause and Quit share the same outer plate size")
        check(pause_plate.get_global_rect().position == quit_plate.get_global_rect().position,
            "Pause and Quit share the same outer plate position")
        check(pause_plate.get_global_rect().size == Vector2(460.0, 272.0),
            "shared overlay plate is the authored 460x272 shell")

    var pause_title: Label = pause.find_child("OverlayTitle", true, false)
    var quit_title: Label = home.find_child("OverlayTitle", true, false)
    check(pause_title != null and quit_title != null, "both overlays expose their title")
    if pause_title != null and quit_title != null and pause_plate != null and quit_plate != null:
        check(pause_title.get_theme_font_size("font_size") == quit_title.get_theme_font_size("font_size"),
            "overlay titles share the same type size")
        check(pause_title.get_theme_font("font").resource_path == quit_title.get_theme_font("font").resource_path,
            "overlay titles share the same font role")
        check(rect(pause_title).position - rect(pause_plate).position == rect(quit_title).position - rect(quit_plate).position,
            "overlay titles share the same plate-local position")

    var pause_rows: Array = pause.menu_rows()
    var quit_rows: Array = []
    for node_name in ["RowStay", "RowQuit"]:
        var row := home.find_child(node_name, true, false) as Control
        if row != null:
            quit_rows.append(row)
    check(pause_rows.size() == 2 and quit_rows.size() == 2,
        "both overlays expose exactly two choice rows")
    if pause_rows.size() == 2 and quit_rows.size() == 2:
        for i in 2:
            row_parts(pause_rows[i])
            row_parts(quit_rows[i])
            check(is_equal_approx(rect(pause_rows[i]).position.x, rect(quit_rows[i]).position.x),
                "choice row %d shares the common x axis" % i)
            check(is_equal_approx(rect(pause_rows[i]).size.y, rect(quit_rows[i]).size.y),
                "choice row %d shares the row height" % i)
        check(rect(pause_rows[1]).position.y > rect(pause_rows[0]).position.y,
            "Pause choices are vertically ordered")
        check(rect(quit_rows[1]).position.y > rect(quit_rows[0]).position.y,
            "Quit choices are vertically ordered")
        var pause_plate_0: Panel = pause.item_plate(0)
        var quit_plate_0: Panel = quit_rows[0].get_node("ActivePlate")
        check(pause_plate_0.visible and quit_plate_0.visible,
            "the default choice uses the shared active material plate")
        check(pause.active_rail(0).visible and quit_rows[0].get_node("ActiveRail").visible,
            "the default choice uses the shared active rail")
        check(not pause.item_plate(1).visible and not quit_rows[1].get_node("ActivePlate").visible,
            "the quiet choice has no active plate")
        check(pause.quiet_rail(1).visible and quit_rows[1].get_node("QuietRail").visible,
            "the quiet choice retains its quiet rail")

    var stay: Button = home.find_child("ActionStay", true, false)
    var quit: Button = home.find_child("ActionQuit", true, false)
    check(stay != null and quit != null, "Quit exposes named semantic actions")
    if stay != null and quit != null:
        stay.grab_focus()
        await settle(2)
        check(home.get_viewport().gui_get_focus_owner() == stay, "Quit defaults focus to STAY")
        check(stay.get_theme_font_size("font_size") == pause.action_resume().get_theme_font_size("font_size"),
            "selected Quit action shares the selected Pause type size")
        quit.grab_focus()
        await settle(2)
        var quit_row: Control = home.find_child("RowQuit", true, false)
        check(quit_row != null, "Quit exposes the second shared choice row")
        if quit_row != null:
            check(quit_row.get_node("ActivePlate").visible and quit_row.get_node("ActiveRail").visible,
                "moving Quit focus transfers the shared active state")
        var stay_row: Control = home.find_child("RowStay", true, false)
        check(stay_row != null and not stay_row.get_node("ActivePlate").visible,
            "moving Quit focus clears the previous active state")

    var main_quit := home.get_node("ReferenceFrame/Navigation/MenuRow_Quit") as Control
    check(not main_quit.get_node("ActivePlate").visible and not main_quit.get_node("ActiveRail").visible,
        "opening Quit suppresses the caller's competing active selection visuals")

    if failures == 0:
        print("PASS: shared Pause/Quit overlay visual grammar")
    else:
        print("FAILURES: %d" % failures)
    quit(1 if failures else 0)
