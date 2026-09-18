extends SceneTree
# WP-4 PUBLIC_INPUT_ACCEPTANCE: Pause and global Quit route coverage.
# The setup fixture uses the real arena scene only to reach a live match; every
# interaction under test is then driven through Input.parse_input_event() and
# the viewport/window event path, not private overlay helpers.
#
# WP-1 POINTER CONTRACT (owner round on the Pause surface): hover AND a real
# left-click are asserted per pause item through the viewport GUI path
# (`gui_get_hovered_control()` + Button.pressed), and the pause rows are the
# owner-approved Main row grammar (MenuRow instances: label left, plate + gold
# ledge on the selected row, the quiet row's own rail).

var failures := 0

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func settle(frames: int = 2) -> void:
    for _i in frames:
        await process_frame

func key_event(keycode: Key, pressed := true) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = pressed
    return event

func pad_button(button_index: JoyButton, pressed := true) -> InputEventJoypadButton:
    var event := InputEventJoypadButton.new()
    event.device = 0
    event.button_index = button_index
    event.pressed = pressed
    return event

func mouse_motion(at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.relative = Vector2(2.0, 0.0)
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    await process_frame

func mouse_click(at: Vector2) -> void:
    await mouse_motion(at)
    var down := InputEventMouseButton.new()
    down.button_index = MOUSE_BUTTON_LEFT
    down.position = at
    down.global_position = at
    down.pressed = true
    Input.parse_input_event(down)
    Input.flush_buffered_events()
    await process_frame
    var up := InputEventMouseButton.new()
    up.button_index = MOUSE_BUTTON_LEFT
    up.position = at
    up.global_position = at
    up.pressed = false
    Input.parse_input_event(up)
    Input.flush_buffered_events()
    await process_frame

func pointer_hand():
    var cursor = root.get_node_or_null("Cursor")
    return cursor.hand if cursor != null else null

func hovered_control() -> Control:
    return root.gui_get_hovered_control() if root.has_method("gui_get_hovered_control") else null

func live_arena() -> Node:
    var arena := (load("res://scenes/main.tscn") as PackedScene).instantiate()
    root.add_child(arena)
    await settle(3)
    var slots = load("res://scripts/match_config.gd").default_slots()
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    check(arena.start_match(slots, false), "the real arena reaches a live match")
    await settle(3)
    return arena

func free_leftovers() -> void:
    # One leg's route change (LEAVE MATCH/ENCOUNTER -> MatchFlow) makes the new
    # host the CURRENT scene. A later leg must start from a clean tree: drop the
    # current-scene pointer BEFORE freeing, so the tree can never hold a
    # dangling scene reference (engine crash on the next frame).
    var current: Node = current_scene
    if current != null and is_instance_valid(current):
        current_scene = null
    for child in root.get_children():
        if child.has_method("entry_mode") or child.has_method("start_match"):
            child.queue_free()
    await settle(3)

func run() -> void:
    root.size = Vector2i(1280, 720)
    await pause_public_path()
    await pause_pointer_contract()
    await pause_story_pointer_contract()
    await quit_from_how_to_play_public_path()
    if failures == 0:
        print("PASS: WP-4 Pause state machine, pointer contract and How-to-Play global Quit public routes")
    else:
        print("FAILURES: %d" % failures)
    quit(1 if failures else 0)

func pause_public_path() -> void:
    var arena := await live_arena()
    var pause = arena.pause_overlay()
    check(pause != null, "the live match owns the shared Pause overlay")
    var input_service: Node = root.get_node("FrontendInput")
    check(input_service.scope() == input_service.SCOPE_GAMEPLAY, "live match owns gameplay input scope")
    Input.parse_input_event(key_event(KEY_ESCAPE))
    Input.flush_buffered_events()
    await settle(3)
    check(pause.state() == pause.STATE_OPEN, "Esc opens Pause through the semantic input path")
    check(root.get_tree().paused, "opening Pause freezes gameplay")
    check(input_service.scope() == input_service.SCOPE_FRONTEND, "Pause owns frontend input scope")
    check(pause.title_text() == "PAUSED", "Pause renders the PAUSED title")
    check(pause.resume_label() == "RESUME", "Pause exposes RESUME")
    check(pause.leave_label() == "LEAVE MATCH", "VS Pause exposes LEAVE MATCH")
    check(pause.action_resume().focus_mode != Control.FOCUS_NONE and pause.action_leave().focus_mode != Control.FOCUS_NONE,
        "Pause actions remain focusable")
    var focus: Control = root.get_viewport().gui_get_focus_owner()
    check(focus == pause.action_resume(), "Pause seeds focus on RESUME")
    check(pause.focus_anchor_for(focus) != null, "Pause focus has an authored CursorAnchor")
    # Keyboard/controller parity: the visible Pause choices must be a real
    # focus column, not merely two focusable buttons with a seeded first owner.
    Input.parse_input_event(key_event(KEY_DOWN))
    Input.flush_buffered_events()
    await settle(2)
    check(root.get_viewport().gui_get_focus_owner() == pause.action_leave(),
        "keyboard ui_down moves Pause focus from RESUME to LEAVE")
    check(pause.active_index() == 1, "keyboard ui_down moves Pause selection to LEAVE")
    Input.parse_input_event(key_event(KEY_UP))
    Input.flush_buffered_events()
    await settle(2)
    check(root.get_viewport().gui_get_focus_owner() == pause.action_resume(),
        "keyboard ui_up moves Pause focus back to RESUME")
    Input.parse_input_event(pad_button(JOY_BUTTON_DPAD_DOWN))
    Input.flush_buffered_events()
    await settle(2)
    check(root.get_viewport().gui_get_focus_owner() == pause.action_leave(),
        "controller D-pad down moves Pause focus to LEAVE")
    Input.parse_input_event(pad_button(JOY_BUTTON_DPAD_UP))
    Input.flush_buffered_events()
    await settle(2)
    check(root.get_viewport().gui_get_focus_owner() == pause.action_resume(),
        "controller D-pad up moves Pause focus back to RESUME")
    Input.parse_input_event(key_event(KEY_ESCAPE))
    Input.flush_buffered_events()
    await settle(3)
    check(pause.state() == pause.STATE_CLOSED, "ui_cancel resumes from Pause")
    check(not root.get_tree().paused, "resuming unfreezes gameplay")
    check(input_service.scope() == input_service.SCOPE_GAMEPLAY, "resume restores gameplay input scope")
    Input.parse_input_event(pad_button(JOY_BUTTON_START))
    Input.flush_buffered_events()
    await settle(3)
    check(pause.state() == pause.STATE_OPEN, "controller Start opens Pause through the semantic input path")
    check(input_service.scope() == input_service.SCOPE_FRONTEND, "controller Start transfers frontend ownership to Pause")
    await mouse_click(pause.action_resume().get_global_rect().get_center())
    await settle(3)
    check(pause.state() == pause.STATE_CLOSED, "real mouse RESUME closes Pause")
    check(not root.get_tree().paused, "mouse RESUME unfreezes gameplay")
    check(input_service.scope() == input_service.SCOPE_GAMEPLAY, "mouse RESUME restores gameplay input scope")
    arena.queue_free()
    await settle(3)

# --- WP-1 pointer contract (hover + left-click per item) --------------------
func pause_pointer_contract() -> void:
    var arena := await live_arena()
    var pause = arena.pause_overlay()
    Input.parse_input_event(key_event(KEY_ESCAPE))
    Input.flush_buffered_events()
    await settle(3)
    check(pause.state() == pause.STATE_OPEN, "the pointer-contract leg opens Pause through the semantic path")
    check(root.get_tree().paused, "the pointer-contract leg runs on a paused tree")

    # The pointer service must stay alive while paused: it IS the visible
    # pointer (the OS pointer is hidden), so a frozen hand means no pointer.
    var hand = pointer_hand()
    check(hand != null, "the shared pointer hand is mounted")
    check(hand.can_process(), "the pointer service keeps processing while the match is paused")
    check(hand.is_processing(), "the pointer service is actively processing while paused")

    # The rows are the approved MenuRow grammar (measured from the live tree).
    var rows: Array = pause.menu_rows()
    check(rows.size() == 2, "Pause owns exactly two rows")
    for index in rows.size():
        var row: Control = rows[index]
        check(row.name == "RowResume" or row.name == "RowLeave", "row %d is a MenuRow-shaped row (%s)" % [index, str(row.name)])
        for child_name in ["HitArea", "ActivePlate", "Label", "QuietRail", "ActiveRail", "CursorAnchor"]:
            check(row.has_node(child_name), "row %d carries the MenuRow child %s" % [index, child_name])
        check(row.get_node("ActivePlate").has_node("TopRule"), "row %d keeps the Main row's top rule" % index)
        check(pause.row_hit(index).mouse_filter == Control.MOUSE_FILTER_STOP, "row %d owns a STOP hit area" % index)
    var label_x: float = pause.row_label(0).get_global_rect().position.x
    var plate: Rect2 = pause.item_plate(0).get_global_rect()
    check(is_equal_approx(label_x - plate.position.x, 9.0 + 12.0),
        "the active label sits 12 px inside its plate plus the 9 px active shift (Main grammar)")
    check(is_equal_approx(pause.row_label(1).get_global_rect().position.x, plate.position.x + 12.0),
        "every quiet label shares the one authored label x (Main grammar)")
    check(is_equal_approx(pause.active_rail(0).size.x, plate.size.x),
        "the gold ledge spans the selected row's plate width")
    check(is_equal_approx(pause.item_plate(0).get_global_rect().end.y + 1.0, pause.active_rail(0).get_global_rect().position.y),
        "the gold ledge sits directly under the selected row's plate")
    check(pause.item_plate(0).visible and pause.active_rail(0).visible,
        "the seeded row carries the plate and the ledge")
    check(not pause.item_plate(1).visible and not pause.active_rail(1).visible and pause.quiet_rail(1).visible,
        "the unselected row carries its own quiet rail and no ledge (no orphan rule)")
    var quiet: Rect2 = pause.quiet_rail(1).get_global_rect()
    check(is_equal_approx(pause.item_plate(1).get_global_rect().end.x - quiet.end.x, 24.0),
        "the quiet rail ends 24 px before the plate's right edge, like the Main rows")
    check(quiet.size.x > 0.0, "the quiet rail has a measured length")

    # Real hover per item through the viewport path.
    for index in 2:
        var hit: Button = pause.row_hit(index)
        await mouse_motion(hit.get_global_rect().get_center())
        await settle(2)
        check(hovered_control() == hit, "the viewport hit test resolves row %d under the pointer" % index)
        check(hand.hovered == hit, "the pointer's semantic hover owns row %d" % index)
        check(pause.active_index() == index, "hovering row %d moves the visible selection to it" % index)
        check(pause.item_plate(index).visible and pause.active_rail(index).visible,
            "hovering row %d shows its plate and ledge" % index)
        check(pause.quiet_rail(1 - index).visible and not pause.item_plate(1 - index).visible,
            "the other row falls back to its quiet rail when row %d is hovered" % index)
    check(root.get_viewport().gui_get_focus_owner() == pause.action_resume(),
        "hovering never steals focus (a click that focuses cannot hijack the pointer)")

    # Real left-click per item: RESUME first, then LEAVE MATCH (which routes).
    await mouse_click(pause.action_resume().get_global_rect().get_center())
    await settle(3)
    check(pause.state() == pause.STATE_CLOSED, "real left-click on RESUME resumes the match")
    check(not root.get_tree().paused, "resume from the pointer unfreezes gameplay")
    Input.parse_input_event(pad_button(JOY_BUTTON_START))
    Input.flush_buffered_events()
    await settle(3)
    check(pause.state() == pause.STATE_OPEN, "Pause opens again for the LEAVE leg")
    # The leave routes THROUGH main.gd (scene change), so the surface state is
    # captured at the signal: reading the overlay after the click can touch a
    # scene the route already freed.
    var leave_events: Array = []
    pause.leave_requested.connect(func(mode: String) -> void:
        leave_events.append({"mode": mode, "state": pause.state()}))
    await mouse_motion(pause.action_leave().get_global_rect().get_center())
    await settle(2)
    check(pause.active_index() == 1, "the pointer selects LEAVE MATCH before the click")
    await mouse_click(pause.action_leave().get_global_rect().get_center())
    await settle(3)
    check(leave_events.size() == 1, "the LEAVE MATCH click leaves exactly once")
    if leave_events.size() == 1:
        check(leave_events[0]["state"] == "leaving", "the surface reports LEAVING when it requests the leave")
        check(leave_events[0]["mode"] == "vs", "LEAVE MATCH routes the VS leave mode (%s)" % str(leave_events[0]["mode"]))
    check(root.get_node("FrontendInput").scope() == root.get_node("FrontendInput").SCOPE_FRONTEND,
        "leaving hands the frontend back its scope")
    await free_leftovers()

# --- Story pause: the pointer contract on the second wording ----------------
func pause_story_pointer_contract() -> void:
    # The real Story route (Story Select -> Encounter Briefing -> launch); the
    # encounter's Pause is the Story wording of the same surface.
    var story = load("res://tests/fixtures/story_route.gd").new()
    var host: Node = await story.enter(self, "teknium")
    var arena: Node = await story.start_encounter(self, host)
    check(arena != null, "the Story route reaches a live encounter arena")
    if arena == null:
        await free_leftovers()
        return
    var pause = arena.pause_overlay()
    Input.parse_input_event(key_event(KEY_ESCAPE))
    Input.flush_buffered_events()
    await settle(3)
    check(pause.state() == pause.STATE_OPEN, "the Story pause opens through the semantic path")
    check(pause.is_story_pause(), "the Story encounter opens the Story wording")
    check(pause.leave_label() == "LEAVE ENCOUNTER", "Story Pause exposes LEAVE ENCOUNTER")
    var leave_events: Array = []
    pause.leave_requested.connect(func(mode: String) -> void:
        leave_events.append({"mode": mode, "state": pause.state()}))
    var hit: Button = pause.action_leave()
    await mouse_motion(hit.get_global_rect().get_center())
    await settle(2)
    check(hovered_control() == hit, "the viewport hit test resolves the Story LEAVE row")
    check(pause.active_index() == 1, "hovering the Story LEAVE row selects it")
    # Hosts already mounted: the return route must produce one that is NOT one
    # of them (the launched host is freed, and an id can be reused).
    var previous_hosts: Array = []
    for child in root.get_children():
        if child.has_method("entry_mode"):
            previous_hosts.append(child.get_instance_id())
    await mouse_click(hit.get_global_rect().get_center())
    var returned: Node = null
    for _i in 240:
        await process_frame
        for child in root.get_children():
            if not child.has_method("entry_mode"):
                continue
            if child.get_instance_id() in previous_hosts:
                continue
            returned = child
            break
        if returned != null and returned.is_story_mode() and str(returned.active_surface()).begins_with("story"):
            break
    check(leave_events.size() == 1, "the LEAVE ENCOUNTER click leaves exactly once")
    if leave_events.size() == 1:
        check(leave_events[0]["state"] == "leaving", "the Story surface reports LEAVING when it requests the leave")
        check(leave_events[0]["mode"] == "story", "LEAVE ENCOUNTER routes the story leave mode (%s)" % str(leave_events[0]["mode"]))
    check(returned != null, "LEAVE ENCOUNTER returns to a MatchFlow host")
    if returned != null:
        check(returned.is_story_mode(), "the returned host re-enters the Story route (mode=%s)" % str(returned.entry_mode()))
        check(str(returned.active_surface()).begins_with("story"),
            "the returned Story host presents a Story surface (%s)" % str(returned.active_surface()))
    await free_leftovers()

func quit_from_how_to_play_public_path() -> void:
    var home := (load("res://scenes/home.tscn") as PackedScene).instantiate()
    root.add_child(home)
    await settle(24)
    var help_hit: Button = home.menu_rows()[2].get_node("HitArea")
    await mouse_click(help_hit.get_global_rect().get_center())
    await settle(12)
    check(home.state == "help", "real mouse input opens How to Play")
    var page := home.find_child("HowToPlay", true, false)
    check(page != null, "How to Play remains mounted for modal overlay")
    var page_id := page.get_instance_id() if page != null else 0
    var help_section: String = page.section() if page != null else ""
    home.get_window().close_requested.emit()
    await settle(4)
    check(home.is_quit_modal_open(), "OS close opens the global Quit modal from How to Play")
    check(home.state == "quit", "Quit modal is the active state")
    var still_page: Node = home.find_child("HowToPlay", true, false)
    check(still_page != null and still_page.get_instance_id() == page_id, "Quit overlays Help without destroying the caller")
    var stay: Button = home.find_child("ActionStay", true, false)
    check(stay != null and root.get_viewport().gui_get_focus_owner() == stay, "Quit modal seeds focus on STAY")
    Input.parse_input_event(key_event(KEY_ESCAPE))
    Input.flush_buffered_events()
    await settle(4)
    check(not home.is_quit_modal_open(), "ui_cancel dismisses Quit from the Help caller")
    check(home.state == "help", "ui_cancel returns to the same How to Play caller")
    check(home.find_child("HowToPlay", true, false) != null, "ui_cancel keeps How to Play mounted")
    home.get_window().close_requested.emit()
    await settle(4)
    check(home.is_quit_modal_open(), "How to Play can reopen the global Quit modal")
    stay = home.find_child("ActionStay", true, false)
    await mouse_click(stay.get_global_rect().get_center())
    await settle(12)
    check(not home.is_quit_modal_open(), "STAY closes the global Quit modal")
    check(home.state == "help", "STAY restores the How to Play caller state")
    var restored := home.find_child("HowToPlay", true, false)
    check(restored != null and restored.get_instance_id() == page_id, "STAY restores the exact Help instance")
    check(restored.section() == help_section, "STAY preserves the Help section")
    home.queue_free()
    await settle(3)
