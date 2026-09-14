extends SceneTree
# Focused check for WP-C: the canonical Main Menu, "Selection Rail" (Doc 03).
#
# Migrated from the rejected card/context/shelf contract (Doc 10 §11): this
# file now protects the design-locked invariants of Doc 03 §25 —
#   no shelf background, no context frame, no numbering;
#   exactly the four destinations, authored geometry, one CursorAnchor each;
#   exactly one row owns active state; the rail exists only for it;
#   selection never changes row layout bounds;
#   row/hit geometry stays inside the composition bands and never overlaps;
#   controller focus moves selection (and the hand) without touching the
#   physical pointer; mouse hover after genuine motion selects the row;
#   Quit is an in-place modal over the mounted Main (default focus STAY,
#   Esc/Back dismisses, OS close takes the same path);
#   all four semantic destinations are reachable.
const Tokens = preload("res://scripts/ui_tokens.gd")

const LABELS: Array = ["PLAY", "STORY MODE", "HOW TO PLAY", "QUIT"]
const HAND_REACH := 46.0   # pointing hand art is ~45 px wide from its tip

var failures := 0

func _initialize(): call_deferred("run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func settle(frames: int) -> void:
    for i in frames:
        await process_frame

func rail_of(row: Control) -> Panel:
    return row.get_node("ActiveRail")

func plate_of(row: Control) -> Panel:
    return row.get_node("ActivePlate")

func hit_of(row: Control) -> Button:
    return row.get_node("HitArea")

func label_of(row: Control) -> Label:
    return row.get_node("Label")

func anchor_of(row: Control) -> Control:
    return row.find_child("CursorAnchor", true, false)

func active_indices(rows: Array) -> Array:
    var out: Array = []
    for i in rows.size():
        var rail := rail_of(rows[i])
        if rail.visible and rail.size.x > 1.0:
            out.append(i)
    return out

func key_event(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.pressed = true
    return event

func run() -> void:
    if not ResourceLoader.exists("res://scenes/home.tscn"):
        check(false, "static main menu scene missing")
    var home = load("res://scenes/home.tscn").instantiate()
    root.add_child(home)
    await settle(40)
    var hand = _hand()
    check(hand != null, "cursor service is present")

    # --- rejected architecture is gone (Doc 03 §17/§18/§26) ----------------
    check(home.find_child("ShelfBackground", true, false) == null,
        "Main must not instantiate the shelf background")
    check(home.find_child("ContextFrame", true, false) == null,
        "Main must not instantiate a context frame")
    check(home.find_children("*", "Node3D", true, false).size() == 0,
        "Main stays a pure Control screen")
    for label in home.find_children("*", "Label", true, false):
        var text := str(label.text).strip_edges()
        check(not (text in ["01", "02", "03", "04"]), "no row numbering on Main")
        check(text.find("ENTER") == -1, "no ENTER callout on Main")

    # --- the small header (Doc 03 §6) --------------------------------------
    var wordmark = home.find_child("NRCU", true, false)
    check(wordmark != null and wordmark.get_theme_font_size("font_size") >= 46
        and wordmark.get_theme_font_size("font_size") <= 58,
        "header wordmark sits in the 46-58 px band")
    var header_rule = home.find_child("HeaderRule", true, false)
    check(header_rule != null and header_rule.size.x >= 180.0 and header_rule.size.x <= 230.0
        and header_rule.size.y <= 2.0,
        "warm header rule is 2 px and 180-230 px long")
    var menu_label = home.find_child("MainMenuLabel", true, false)
    check(menu_label != null and str(menu_label.text).replace(" ", "").find("MAINMENU") != -1,
        "tracked MAIN MENU label exists")
    var header: Control = home.find_child("Header", true, false)

    # --- exactly the four destinations, authored and visible (Doc 03 §8) ---
    var rows: Array = home.menu_rows()
    check(rows.size() == 4, "exactly four destinations exist")
    if rows.size() != 4:
        home.queue_free()
        await process_frame
        quit(1)
        return
    for i in rows.size():
        var row: Control = rows[i]
        var hit := hit_of(row)
        check(row.visible and hit.visible, "row %d is visible" % i)
        var rect := hit.get_global_rect()
        check(rect.size.x >= 540.0 and rect.size.x <= 620.0,
            "row %d hit width is in the 540-620 semantic band" % i)
        check(rect.size.y >= 64.0 and rect.size.y <= 70.0,
            "row %d hit height is in the 64-70 semantic band" % i)
        check(label_of(row).text == LABELS[i], "row %d carries the canonical label" % i)
        var anchor := anchor_of(row)
        check(anchor != null and anchor.has_method("anchor_position"),
            "row %d exposes a CursorAnchor" % i)

    # --- one active row, rail only for it, quiet fragment only elsewhere ---
    var active := active_indices(rows)
    check(active.size() == 1, "exactly one row owns the active rail")
    check(int(active[0]) == home.selected_index(), "the selected row is the active one")
    check(plate_of(rows[int(active[0])]).visible, "the active row owns the plate")
    for i in rows.size():
        var quiet: Panel = rows[i].get_node("QuietRail")
        if i == home.selected_index():
            check(not quiet.visible, "the active row hides its quiet fragment")
        else:
            check(quiet.visible and quiet.size.x >= 80.0 and quiet.size.x <= 130.0,
                "inactive row %d keeps one short quiet fragment" % i)

    # --- authored geometry bands, layout stability across selection --------
    var bounds: Array = []
    var hit_bounds: Array = []
    for row in rows:
        bounds.append(row.get_global_rect())
        hit_bounds.append(hit_of(row).get_global_rect())
    for i in rows.size():
        home.select_row(i)
        await settle(30)
        var active_now := active_indices(rows)
        check(active_now.size() == 1 and int(active_now[0]) == i,
            "selecting %d retargets exactly one active rail" % i)
        var rail_rect := rail_of(rows[i]).get_global_rect()
        check(rail_rect.end.x <= 1030.0, "rail stays inside the capped composition reach")
        check(rail_rect.end.x >= 900.0 and rail_rect.end.x <= 980.0,
            "the resting rail reaches into the negative space (x~900-980)")
        check(absf(rail_rect.position.x - plate_of(rows[i]).get_global_rect().position.x) <= 4.0,
            "the rail starts at the plate leading edge")
        check(rail_rect.size.y >= 2.0 and rail_rect.size.y <= 3.0, "rail is a 2-3 px edge")
        for j in rows.size():
            check(rows[j].get_global_rect() == bounds[j],
                "selection never changes row layout bounds (row %d)" % j)
            check(hit_of(rows[j]).get_global_rect() == hit_bounds[j],
                "selection never changes hit bounds (row %d)" % j)
    for a in rows.size():
        for b in range(a + 1, rows.size()):
            check(not bounds[a].intersects(bounds[b]), "rows %d/%d do not overlap" % [a, b])
    var plate_rect := plate_of(rows[home.selected_index()]).get_global_rect()
    check(plate_rect.position.y >= header.get_global_rect().end.y,
        "the active plate does not overlap the header")
    check(plate_rect.position.x >= 105.0 and plate_rect.position.x <= 120.0,
        "plate leading edge sits at the authored x 105-120")
    check(plate_rect.size.x >= 320.0 and plate_rect.size.x <= 370.0,
        "plate width is the shallow ledge 320-370")
    check(plate_rect.size.y >= 54.0 and plate_rect.size.y <= 60.0,
        "plate height is 54-60")
    for i in rows.size():
        var label := label_of(rows[i])
        var anchor := anchor_of(rows[i])
        check(anchor.anchor_position().x + HAND_REACH <= label.get_global_rect().position.x,
            "the focus hand never covers the first glyph of row %d" % i)
        if i != home.selected_index():
            var font := label.get_theme_font("font")
            var font_size := label.get_theme_font_size("font_size")
            var text_w: float = font.get_string_size(str(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
            var quiet: Panel = rows[i].get_node("QuietRail")
            check(quiet.get_global_rect().position.x >= label.get_global_rect().position.x + text_w + 8.0,
                "the quiet fragment stays clear of row %d's label" % i)

    # --- geometry evidence (frame-local, so it reads at any window size) ---
    home.select_row(0)
    await settle(30)
    var frame_origin: Vector2 = home.find_child("ReferenceFrame", true, false).get_global_rect().position
    var geo: Array = []
    for row in rows:
        var r: Rect2 = row.get_global_rect()
        geo.append(Vector2i(int(r.position.x - frame_origin.x), int(r.position.y - frame_origin.y)))
    var active_plate := plate_of(rows[0]).get_global_rect()
    var active_rail := rail_of(rows[0]).get_global_rect()
    var quiets: Array = []
    for row in rows:
        quiets.append(int(row.get_node("QuietRail").size.x))
    print("GEO frame=", frame_origin, " row_origins=", geo, " quiet_widths=", quiets,
        " PLAY plate=", Rect2(active_plate.position - frame_origin, active_plate.size),
        " PLAY rail=", Rect2(active_rail.position - frame_origin, active_rail.size),
        " header_bottom=", int(header.get_global_rect().end.y - frame_origin.y))

    # --- controller/keyboard focus (no pointer warp, Doc 03 §12/§25) -------
    check(FileAccess.get_file_as_string("res://scripts/home.gd").find("warp_mouse") == -1,
        "no pointer-warp call path exists in home.gd")
    home.select_row(0)
    hit_of(rows[0]).grab_focus()
    await settle(20)
    Input.parse_input_event(key_event(KEY_DOWN))
    await settle(24)
    check(hand.mode == 1, "a key event puts the cursor in focus mode")
    check(home.selected_index() == 1, "focus navigation changes the selected index")
    var focus_anchor: Vector2 = anchor_of(rows[1]).anchor_position()
    check(hand.hotspot.distance_to(focus_anchor) <= 3.0,
        "the focus hand settles at the authored anchor")
    check(hand.hotspot.distance_to(home.get_viewport().get_mouse_position()) > 30.0,
        "controller focus never moves the physical pointer")

    # --- mouse hover after genuine motion (Doc 03 §12) ---------------------
    # Focus -> mouse re-acquires the pointer on the first genuine motion
    # without inheriting hover; a later motion over a row arms semantic hover.
    var vp: Viewport = home.get_viewport()
    var pointer := hit_of(rows[2]).get_global_rect().get_center()
    var field := Vector2(940.0, pointer.y)
    var travel := InputEventMouseMotion.new()
    travel.position = vp.get_screen_transform() * field
    travel.relative = Vector2(160.0, 0.0)
    Input.parse_input_event(travel)
    await settle(4)
    check(home.selected_index() == 1, "pointer travel through the empty field never selects")
    var motion := InputEventMouseMotion.new()
    motion.position = vp.get_screen_transform() * pointer
    motion.relative = Vector2(-160.0, 0.0)
    Input.parse_input_event(motion)
    await settle(8)
    check(home.selected_index() == 2, "mouse hover after genuine motion selects the same row")
    check(hand.mode == 0, "hover returns the cursor to mouse mode")
    check(hand.hotspot.distance_to(pointer) <= 1.0, "the mouse hand stays exact on the pointer")
    await settle(24)
    check(active_indices(rows) == [2], "hover keeps exactly one active rail")

    # --- semantic events + How to Play subpage (selection memory) ----------
    # (autoloads are reached through the tree: a --script main loop compiles
    #  before autoload identifiers are registered)
    var events_node = root.get_node("FrontendEvents")
    var events: Array = []
    events_node.confirm.connect(func(id: String) -> void: events.append(id))
    events_node.back.connect(func(id: String) -> void: events.append("back:" + id))
    hit_of(rows[2]).pressed.emit()
    await settle(10)
    check(home.state == "help", "HOW TO PLAY opens the subpage")
    check(events.has("main_help"), "the semantic confirm fires for How to Play")
    var back: Button = home.find_child("HelpBack", true, false)
    check(back != null, "the subpage keeps a visible Back route")
    back.pressed.emit()
    await settle(10)
    check(home.state == "home", "Back returns to Main")
    check(home.selected_index() == 2, "returning from How to Play keeps HOW TO PLAY selected")

    # --- quit confirmation is an in-place modal (Doc 07 §9-10) -------------
    hit_of(rows[3]).pressed.emit()
    await settle(12)
    check(home.is_quit_modal_open(), "QUIT opens the confirmation layer")
    check(home.state == "quit", "the confirmation is a modal state, not a page")
    check(home.is_inside_tree(), "Main stays mounted behind the confirmation")
    check(home.find_child("Navigation", true, false).visible,
        "the destination stack stays visible and subdued behind the modal")
    check(events.has("main_quit"), "the semantic confirm fires for QUIT")
    var dim = home.find_child("Dim", true, false)
    check(dim != null and dim.visible and dim.modulate.a > 0.3,
        "Main stays visible but subdued behind the confirmation")
    var focus = home.get_viewport().gui_get_focus_owner()
    check(focus != null and str(focus.name) == "ActionStay", "default modal focus is STAY")
    var modal = home.quit_modal_rect()
    check(modal.size.x >= 420.0 and modal.size.x <= 500.0, "modal is the compact 420-500 plate")
    check(modal.size.y >= 180.0 and modal.size.y <= 220.0, "modal is the compact 180-220 plate")
    for row in rows:
        check(hit_of(row).focus_mode == Control.FOCUS_NONE,
            "modal focus cannot move behind the overlay")
    # WALK-UP (Doc 08 §2 public input): the modal dismiss is driven by a real
    # ui_cancel event through the tree, not by calling the screen's handler.
    Input.parse_input_event(key_event(KEY_ESCAPE))
    await settle(12)
    check(not home.is_quit_modal_open(), "Esc dismisses the confirmation")
    check(home.state == "home", "dismissing returns to Main")
    check(events.has("back:main"), "dismissing reports the semantic back event")
    var refocused = home.get_viewport().gui_get_focus_owner()
    check(refocused != null and str(refocused.name) == "HitArea", "dismissing restores row focus")
    home.get_window().close_requested.emit()
    await settle(12)
    check(home.is_quit_modal_open(), "OS close_requested takes the same confirmation path")
    var quit_conns := (home.find_child("ActionQuit", true, false) as Button).pressed.get_connections()
    check(quit_conns.size() > 0, "the modal QUIT action is wired to the exit")
    (home.find_child("ActionStay", true, false) as Button).pressed.emit()
    await settle(12)
    check(not home.is_quit_modal_open(), "STAY closes the confirmation")

    # --- all four destinations reachable, keyboard wraps (Doc 03 §25) ------
    for i in rows.size():
        var rect := hit_of(rows[i]).get_global_rect()
        check(rect.has_point(rect.get_center()), "row %d hit region is usable" % i)
        check(rect.position.x >= Tokens.MARGIN and rect.end.x <= 1280.0 - Tokens.MARGIN,
            "row %d stays inside the safe composition" % i)
    home.select_row(0)
    hit_of(rows[0]).grab_focus()
    await settle(20)
    var visited: Array = []
    for step in 4:
        Input.parse_input_event(key_event(KEY_DOWN))
        await settle(20)
        visited.append(home.selected_index())
    check(visited == [1, 2, 3, 0], "keyboard navigation reaches all four destinations and wraps")

    if failures > 0:
        print("FAILURES: %d" % failures)
        home.queue_free()
        await process_frame
        quit(1)
        return
    print("PASS main menu selection rail (Doc 03) invariants")
    home.queue_free()
    await process_frame
    quit(0)

func _hand():
    var cursor = root.get_node_or_null("Cursor")
    if cursor == null or cursor.hand == null:
        return null
    return cursor.hand
