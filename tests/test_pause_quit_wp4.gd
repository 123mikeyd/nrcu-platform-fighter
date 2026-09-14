extends SceneTree
# WP-4 PUBLIC_INPUT_ACCEPTANCE: Pause and global Quit route coverage.
# The setup fixture uses the real arena scene only to reach a live match; every
# interaction under test is then driven through Input.parse_input_event() and
# the viewport/window event path, not private overlay helpers.

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

func run() -> void:
    root.size = Vector2i(1280, 720)
    await pause_public_path()
    await quit_from_how_to_play_public_path()
    if failures == 0:
        print("PASS: WP-4 Pause state machine and How-to-Play global Quit public routes")
    else:
        print("FAILURES: %d" % failures)
    quit(1 if failures else 0)

func pause_public_path() -> void:
    var arena := (load("res://scenes/main.tscn") as PackedScene).instantiate()
    root.add_child(arena)
    await settle(3)
    var slots = load("res://scripts/match_config.gd").default_slots()
    slots[2].kind = "empty"
    slots[3].kind = "empty"
    check(arena.start_match(slots, false), "the real arena reaches a live two-fighter match")
    await settle(3)
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
