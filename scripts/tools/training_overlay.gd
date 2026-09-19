extends CanvasLayer

var lab
var telemetry: Array[Label] = []
var status: Label
var pause_button: Button
var record_button: Button
var tick_label: Label
var device_choices: Array[OptionButton] = []
var rebind_slot := -1
var rebind_action := ""
var binding_panel: PanelContainer
var binding_hint: Label

func _open_bindings() -> void:
    if is_instance_valid(binding_panel): return
    lab.set_paused(true)
    binding_panel = PanelContainer.new()
    binding_panel.position = Vector2(320, 180)
    binding_panel.custom_minimum_size = Vector2(640, 300)
    add_child(binding_panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 14)
    binding_panel.add_child(column)
    var title := Label.new()
    title.text = "KEYBOARD BINDINGS / GAMEPLAY PAUSED"
    column.add_child(title)
    var row := HBoxContainer.new()
    column.add_child(row)
    var player := OptionButton.new()
    player.add_item("Player 1")
    player.add_item("Player 2")
    row.add_child(player)
    var action := OptionButton.new()
    for name in ["left", "right", "up", "down", "jump", "attack", "special", "shield"]:
        action.add_item(name)
    action.select(4)
    row.add_child(action)
    _button(row, "Capture next key", func():
        rebind_slot = player.selected
        rebind_action = action.get_item_text(action.selected)
        binding_hint.text = "Press the new physical key. Esc cancels. F1–F5 are reserved.")
    binding_hint = Label.new()
    binding_hint.text = "Choose a player/action, then capture a key.\nEach player's keys must be unique. Changes apply immediately."
    column.add_child(binding_hint)
    var buttons := HBoxContainer.new()
    column.add_child(buttons)
    _button(buttons, "Save profiles", func():
        lab.save_profiles()
        binding_hint.text = lab.status_message)
    _button(buttons, "Close (stay paused)", func():
        rebind_slot = -1
        binding_panel.queue_free())

func _input(event: InputEvent) -> void:
    if rebind_slot < 0 or not event is InputEventKey or not event.pressed or event.echo: return
    get_viewport().set_input_as_handled()
    if event.physical_keycode == KEY_ESCAPE:
        rebind_slot = -1
        binding_hint.text = "Capture cancelled."
        return
    if event.physical_keycode in [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5]:
        binding_hint.text = "F1–F5 are lab shortcuts. Choose another key."
        return
    lab.rebind_key(rebind_slot, rebind_action, event.physical_keycode)
    binding_hint.text = lab.status_message
    rebind_slot = -1

func _ready() -> void:
    layer = 20
    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)
    var top := PanelContainer.new()
    top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    top.offset_left = 20
    top.offset_right = -20
    top.offset_top = 14
    root.add_child(top)
    var box := VBoxContainer.new()
    top.add_child(box)
    var title := Label.new()
    title.text = "NRCU  /  MOVEMENT LAB"
    title.add_theme_font_size_override("font_size", 25)
    title.add_theme_color_override("font_color", Color("61e6b3"))
    box.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "P0–P2 candidate · 60 Hz · no combat / no ledge grabs · legacy game unchanged"
    box.add_child(subtitle)
    var actions := HBoxContainer.new()
    box.add_child(actions)
    pause_button = _button(actions, "Pause [F1]", func(): lab.set_paused(not lab.paused))
    _button(actions, "Step [F2]", func(): lab.step_once())
    _button(actions, "Reset [F3]", func(): lab.reset_lab())
    record_button = _button(actions, "Record [F4]", func():
        if lab.recording: lab.stop_recording()
        else: lab.start_recording())
    _button(actions, "Replay [F5]", func(): lab.start_replay())
    _button(actions, "Save trace", func(): lab.save_trace())
    var models := CheckButton.new()
    models.text = "Teknium preview"
    # One-shot lab controls must not retain Space/Enter (both players' jump keys).
    models.focus_mode = Control.FOCUS_NONE
    models.toggled.connect(func(value): lab.set_models_visible(value))
    actions.add_child(models)
    tick_label = Label.new()
    actions.add_child(tick_label)
    var bottom := PanelContainer.new()
    bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    bottom.offset_left = 20
    bottom.offset_right = -20
    bottom.offset_top = -190
    bottom.offset_bottom = -12
    root.add_child(bottom)
    var bottom_box := VBoxContainer.new()
    bottom.add_child(bottom_box)
    var slots := HBoxContainer.new()
    slots.add_theme_constant_override("separation", 28)
    bottom_box.add_child(slots)
    for slot in range(2):
        var column := VBoxContainer.new()
        column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        slots.add_child(column)
        var row := HBoxContainer.new()
        column.add_child(row)
        var name_label := Label.new()
        name_label.text = "P%d" % (slot + 1)
        name_label.add_theme_color_override("font_color", Color("61e6b3") if slot == 0 else Color("ffb665"))
        row.add_child(name_label)
        var devices := OptionButton.new()
        # Keep deliberate keyboard menu navigation, but return focus to gameplay
        # after selection/cancellation. Defer until the popup restores its owner.
        devices.get_popup().popup_hide.connect(devices.release_focus.call_deferred)
        devices.custom_minimum_size.x = 160
        devices.add_item("Keyboard %d" % (slot + 1))
        devices.set_item_metadata(0, -1)
        devices.add_item("Dummy")
        devices.set_item_metadata(1, -2)
        devices.add_item("Movement bot")
        devices.set_item_metadata(2, -3)
        _append_pads(devices)
        devices.select(0 if slot == 0 else 1)
        devices.item_selected.connect(func(index):
            var id: int = devices.get_item_metadata(index)
            var mode := "Dummy" if id == -2 else ("Bot" if id == -3 else ("Keyboard" if id == -1 else "Pad"))
            lab.set_slot_mode(slot, mode, maxi(-1, id)))
        row.add_child(devices)
        device_choices.append(devices)
        var tap := CheckButton.new()
        tap.text = "Tap jump"
        tap.focus_mode = Control.FOCUS_NONE
        tap.button_pressed = lab.sources[slot].tap_jump
        tap.toggled.connect(func(value):
            lab.set_paused(true)
            lab.sources[slot].tap_jump = value
            lab.sources[slot].reset())
        row.add_child(tap)
        var zone := SpinBox.new()
        zone.min_value = 0.05
        zone.max_value = 0.8
        zone.step = 0.05
        zone.value = lab.sources[slot].deadzone
        zone.tooltip_text = "Analog stick deadzone"
        zone.value_changed.connect(func(value):
            lab.sources[slot].deadzone = value)
        row.add_child(zone)
        var text := Label.new()
        text.add_theme_font_size_override("font_size", 15)
        text.custom_minimum_size.y = 68
        column.add_child(text)
        telemetry.append(text)
    var controls := Label.new()
    controls.text = "P1  A/D move · Space jump · S fast-fall/drop   |   P2  arrows · Enter jump   |   Tap / hold jump for short / full hop"
    controls.add_theme_font_size_override("font_size", 15)
    bottom_box.add_child(controls)
    var footer := HBoxContainer.new()
    bottom_box.add_child(footer)
    _button(footer, "Refresh pads", _refresh_pads)
    _button(footer, "Bindings", _open_bindings)
    _button(footer, "Combat lab (first strike slice)", func():
        lab.set_paused(true)
        get_tree().change_scene_to_file("res://scenes/combat_lab.tscn"))
    _button(footer, "Save profiles", func(): lab.save_profiles())
    status = Label.new()
    status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    status.clip_text = true
    status.add_theme_font_size_override("font_size", 14)
    footer.add_child(status)

func _button(parent: Node, text: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size.y = 34
    button.focus_mode = Control.FOCUS_NONE
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

func _append_pads(choice: OptionButton) -> void:
    for id in Input.get_connected_joypads():
        choice.add_item("Pad %d: %s" % [id, Input.get_joy_name(id)])
        choice.set_item_metadata(choice.item_count - 1, id)

func _refresh_pads() -> void:
    for slot in range(device_choices.size()):
        var choice := device_choices[slot]
        var selected_id: int = choice.get_item_metadata(choice.selected)
        while choice.item_count > 3: choice.remove_item(3)
        _append_pads(choice)
        for index in range(choice.item_count):
            if choice.get_item_metadata(index) == selected_id: choice.select(index)
    lab.status_message = "Device list refreshed. Select a slot device while paused."

func _process(_delta: float) -> void:
    if not is_instance_valid(lab) or telemetry.size() != 2: return
    var snapshot: Dictionary = lab.get_snapshot()
    tick_label.text = "   tick %d" % lab.simulation_tick
    pause_button.text = "Resume [F1]" if lab.paused else "Pause [F1]"
    record_button.text = "Stop recording" if lab.recording else "Record [F4]"
    for slot in range(2):
        var data: Dictionary = snapshot.actors[slot]
        var position: Array = data.position
        var motion: Array = data.velocity
        telemetry[slot].text = "%s / %s / %s   air jumps: %s\npos %.2f, %.2f   velocity %.2f, %.2f   queued: %d\n%s" % [
            data.get("locomotion", "?"), data.get("action", "?"), data.get("status", "?"),
            str(data.get("air_jumps_left", "?")), position[0], position[1], motion[0], motion[1],
            data.pending.size(), data.last_request]
        if lab.show_models and is_instance_valid(lab.imported_visuals[slot]):
            var pose: Dictionary = lab.imported_visuals[slot].state.output
            telemetry[slot].text += "\nVisual: %s / %s%s" % [pose.get("state", "?"), pose.get("clip", "?"), " [TEMP pose]" if not str(pose.get("fallback", "")).is_empty() else ""]
            telemetry[slot].tooltip_text = str(pose.get("fallback", ""))
        else:
            telemetry[slot].tooltip_text = ""
        if lab.slot_modes[slot] == "Pad" and not data.connected:
            telemetry[slot].text += "\nDISCONNECTED — neutral input; reconnect or reassign"
    status.text = lab.status_message
