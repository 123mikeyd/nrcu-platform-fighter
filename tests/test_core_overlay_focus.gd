extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        print("FAIL: ", message)

func _init() -> void:
    call_deferred("run")

func button_named(node: Node, text: String) -> BaseButton:
    for child in node.get_children():
        if child is BaseButton and child.text == text:
            return child
        var found := button_named(child, text)
        if found != null: return found
    return null

func click(control: Control) -> void:
    var point := control.get_global_rect().get_center()
    for down in [true, false]:
        var event := InputEventMouseButton.new()
        event.position = point
        event.global_position = point
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = down
        root.push_input(event, true)
    await process_frame

func key(code: Key, unicode_value: int = 0) -> void:
    for down in [true, false]:
        var event := InputEventKey.new()
        event.keycode = code
        event.physical_keycode = code
        event.unicode = unicode_value
        event.pressed = down
        root.push_input(event, true)
    await process_frame

func run() -> void:
    root.size = Vector2i(1280, 720)
    root.gui_embed_subwindows = true
    var lab = load("res://scenes/training_lab.tscn").instantiate()
    root.add_child(lab)
    lab.set_physics_process(false)
    await process_frame
    await process_frame
    var preview := button_named(lab.overlay, "Teknium preview")
    await click(preview)
    check(lab.show_models and preview.button_pressed, "real mouse click enables Teknium preview")
    await key(KEY_SPACE)
    check(lab.show_models and preview.button_pressed, "Space after preview click must not toggle models")
    await key(KEY_ENTER)
    check(lab.show_models and preview.button_pressed, "Enter after preview click must not toggle models")
    check(root.gui_get_focus_owner() != preview, "preview click must not retain gameplay-key focus")
    var tap := button_named(lab.overlay, "Tap jump")
    var was_tap: bool = lab.sources[0].tap_jump
    await click(tap)
    check(lab.sources[0].tap_jump != was_tap, "real mouse click changes tap jump")
    lab.set_paused(false)
    await key(KEY_SPACE)
    check(lab.sources[0].tap_jump != was_tap and not lab.paused, "Space after tap-jump click/resume must not retoggle or pause")
    await key(KEY_ENTER)
    check(lab.sources[0].tap_jump != was_tap and not lab.paused, "Enter after tap-jump click/resume must not retoggle or pause")
    check(root.gui_get_focus_owner() != tap, "tap jump must not retain gameplay-key focus")
    var devices: OptionButton = lab.overlay.device_choices[0]
    await click(devices)
    var popup := devices.get_popup()
    check(popup.visible, "device menu opens by mouse")
    popup.set_focused_item(0)
    for code in [KEY_DOWN, KEY_ENTER]:
        for down in [true, false]:
            var event := InputEventKey.new()
            event.keycode = code
            event.physical_keycode = code
            event.pressed = down
            root.push_input(event, true)
        await process_frame
    check(not popup.visible and devices.selected == 1 and lab.slot_modes[0] == "Dummy", "open device menu retains arrow/Enter selection")
    lab.set_paused(false)
    await key(KEY_SPACE)
    check(not popup.visible and devices.selected == 1, "Space after device selection must not reopen menu")
    popup.hide()
    await process_frame
    await key(KEY_ENTER)
    check(not popup.visible, "Enter after menu dismissal must not reopen menu")
    popup.hide()
    # Cancellation is a separate path from selecting an item.
    await click(devices)
    await key(KEY_ESCAPE)
    check(not popup.visible, "Escape dismisses the device menu")
    await key(KEY_SPACE)
    check(not popup.visible, "Space after menu cancellation must stay gameplay input")
    popup.hide()
    await process_frame

    await click(lab.overlay.pause_button)
    check(lab.paused, "ordinary lab button remains mouse operable")
    await key(KEY_SPACE)
    await key(KEY_ENTER)
    check(lab.paused, "ordinary lab button cannot be activated by subsequent jump keys")

    var zones: Array[Node] = lab.overlay.find_children("*", "SpinBox", true, false)
    var zone: SpinBox = zones[0]
    var edit := zone.get_line_edit()
    await click(edit)
    check(edit.has_focus(), "deliberate spinbox text input keeps focus")
    edit.select_all()
    for digit in [[KEY_0, 48], [KEY_PERIOD, 46], [KEY_3, 51]]:
        await key(digit[0], digit[1])
    await key(KEY_ENTER)
    check(is_equal_approx(zone.value, 0.3) and is_equal_approx(lab.sources[0].deadzone, 0.3), "typed spinbox value is committed normally")

    await click(button_named(lab.overlay, "Bindings"))
    await process_frame
    check(is_instance_valid(lab.overlay.binding_panel) and lab.paused, "bindings opens while paused")
    var capture := button_named(lab.overlay.binding_panel, "Capture next key")
    await click(capture)
    check(lab.overlay.rebind_slot == 0, "capture button starts deliberate key capture")
    await key(KEY_SPACE)
    check(lab.overlay.rebind_slot == -1 and lab.sources[0].bindings.jump == KEY_SPACE, "bindings captures Space rather than treating it as UI activation")
    await click(capture)
    await key(KEY_F12)
    check(lab.sources[0].bindings.jump == KEY_F12, "bindings still applies a new physical key")
    await click(capture)
    await key(KEY_F1)
    check(lab.overlay.rebind_slot == 0, "reserved shortcut is rejected without ending capture")
    await key(KEY_ESCAPE)
    check(lab.overlay.rebind_slot == -1 and lab.sources[0].bindings.jump == KEY_F12, "Escape cancels capture without changing binding")
    await click(button_named(lab.overlay.binding_panel, "Close (stay paused)"))
    check(not is_instance_valid(lab.overlay.binding_panel) and lab.paused, "bindings close remains operable and paused")
    lab.queue_free()
    await process_frame
    if failures == 0: print("PASS: core overlay gameplay focus regression")
    quit(1 if failures else 0)
