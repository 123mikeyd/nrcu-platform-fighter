extends Control
# Melee-style options list (reference: melee_ref/01_menue_framework.md §2.6/§3/§4).
#
# A reusable menu widget for NRCU screens: rows of label + value + arrows with
# keyboard/gamepad/mouse navigation, focus wrap + skip of disabled rows, the
# reference input loop (per-action cooldown, scene-start lock, sound grammar
# hooks), hold-to-scroll repeat and 20F one-shot enter/exit transitions.
#
# The widget is presentation + navigation only: the owning screen feeds rows,
# reacts to its signals and decides where each action leads. SFX assets are not
# wired yet — sound_requested("move"/"forward"/"back"/"deny") is the hook.

signal focus_changed(row: int)
signal changed(row: int, value: int)
signal confirmed(row: int)
signal back_requested()
signal sound_requested(kind: String)

const COOLDOWN_ACTION := 0.083   # 5 frames @ 60 fps (Doc 01 §3.1)
const COOLDOWN_START := 0.33     # 20 frames scene start (§3.1)
const TRANSITION_SECONDS := 0.33 # 20F one-shot list transition (§4.1)
const HOLD_DELAY := 0.33         # repeat: trigger -> delay (frames unclear in decomp §2.9)
const HOLD_STEP := 0.12          # then stepped repeat
const HOLD_STEP_FAST := 0.06     # ... accelerating after a while

var rows: Array[Dictionary] = []
var focus := 0

var _cooldown := 0.0
var _nav_held := 0               # -1 focus up / +1 focus down while a key is held
var _hold_time := 0.0
var _repeat_timer := 0.0
var _exiting := false
var _list: VBoxContainer
var _row_nodes: Array[Control] = []

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    lock_start()
    set_process(true)

# --- setup ------------------------------------------------------------------

func build(defs: Array) -> void:
    # defs: {label: String, kind: "value"|"action", values: [String], value: int,
    #        enabled: bool  (disabled rows are skipped by focus, Doc 01 §3.3)}
    if _list == null:
        _list = VBoxContainer.new()
        _list.add_theme_constant_override("separation", 6)
        add_child(_list)
        _list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for c in _list.get_children():
        _list.remove_child(c)
        c.queue_free()
    _row_nodes.clear()
    rows.clear()
    for d in defs:
        rows.append((d as Dictionary).duplicate(true))
    for i in rows.size():
        _row_nodes.append(_make_row(i, _list))
    focus = 0
    for i in rows.size():
        if focus_enabled(i):
            focus = i
            break
    _refresh_all()
    custom_minimum_size.y = _list.get_combined_minimum_size().y + 4.0

func _make_row(index: int, into: Container) -> Control:
    var row_def: Dictionary = rows[index]
    var button := Button.new()
    button.name = "MenuRow%d" % index
    button.custom_minimum_size.y = 40
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_stylebox_override("normal", _box(Color("284e50"), Color("1b3436"), 2))
    button.add_theme_stylebox_override("hover", _box(Color("3d6362"), Color("e5ad69"), 2))
    button.add_theme_stylebox_override("pressed", _box(Color("2f4f4e"), Color("e5ad69"), 2))
    var box := HBoxContainer.new()
    box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    box.add_theme_constant_override("separation", 10)
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    button.add_child(box)
    var label := Label.new()
    label.text = row_def.get("label", "")
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(label)
    if row_def.get("kind", "value") == "value":
        var left := _arrow_button("<", index, -1)
        box.add_child(left)
        var value := Label.new()
        value.name = "Value"
        value.custom_minimum_size.x = 130
        value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        value.mouse_filter = Control.MOUSE_FILTER_IGNORE
        box.add_child(value)
        var right := _arrow_button(">", index, 1)
        box.add_child(right)
    button.mouse_entered.connect(_on_row_hover.bind(index))
    button.pressed.connect(_on_row_clicked.bind(index))
    into.add_child(button)
    _refresh_row(index)
    return button

func _arrow_button(glyph: String, index: int, dir: int) -> Button:
    var arrow := Button.new()
    arrow.text = glyph
    arrow.custom_minimum_size = Vector2(36, 0)
    arrow.focus_mode = Control.FOCUS_NONE
    arrow.add_theme_stylebox_override("normal", _box(Color("35595a"), Color("1b3436"), 2))
    arrow.add_theme_stylebox_override("hover", _box(Color("416b69"), Color("e5ad69"), 2))
    arrow.pressed.connect(_adjust_from.bind(index, dir))
    return arrow

func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = bg
    s.border_color = border
    s.set_border_width_all(width)
    s.set_corner_radius_all(8)
    return s

# --- state ------------------------------------------------------------------

func lock_start() -> void:
    _cooldown = maxf(_cooldown, COOLDOWN_START)

func get_cooldown() -> float:
    return _cooldown

func row_buttons() -> Array:
    return _row_nodes.duplicate()

func is_exiting() -> bool:
    return _exiting

func focused_row() -> Dictionary:
    return rows[focus] if focus >= 0 and focus < rows.size() else {}

func focus_enabled(i: int) -> bool:
    return i >= 0 and i < rows.size() and bool(rows[i].get("enabled", true))

func set_focus(i: int) -> void:
    if i < 0 or i >= rows.size() or i == focus:
        return
    focus = i
    _refresh_all()
    focus_changed.emit(focus)

func move_focus(dir: int) -> void:
    if _cooldown > 0.0 or rows.is_empty():
        return
    var i := focus
    for _step in rows.size():
        i = (i + dir + rows.size()) % rows.size()   # wrap (§3.3)
        if focus_enabled(i):
            break
    if i != focus:
        set_focus(i)
        sound_requested.emit("move")

func adjust(dir: int) -> void:
    if _cooldown > 0.0 or rows.is_empty():
        return
    var row: Dictionary = rows[focus]
    if row.get("kind", "value") != "value" or not focus_enabled(focus):
        return
    var values: Array = row.get("values", [])
    if values.is_empty():
        return
    var v := int(row.get("value", 0))
    v = (v + dir + values.size()) % values.size()               # wrap within limits (§3.4)
    row["value"] = v
    _cooldown = COOLDOWN_ACTION
    _refresh_row(focus)
    sound_requested.emit("move")
    changed.emit(focus, v)

func confirm() -> void:
    if _cooldown > 0.0 or rows.is_empty():
        return
    if not focus_enabled(focus):
        sound_requested.emit("deny")
        return
    var row: Dictionary = rows[focus]
    if row.get("kind", "value") == "action":
        _cooldown = COOLDOWN_ACTION
        sound_requested.emit("forward")
        confirmed.emit(focus)
    else:
        adjust(1)  # confirm on a value row steps the value (mouse-friendly)

func go_back() -> void:
    if _cooldown > 0.0 or _exiting:
        return
    _cooldown = COOLDOWN_ACTION
    sound_requested.emit("back")
    back_requested.emit()

# --- hold-to-scroll ---------------------------------------------------------

func set_nav_held(dir: int) -> void:
    # Key/pad hold: immediate step on press, then repeat after HOLD_DELAY.
    if dir == 0:
        _nav_held = 0
        _hold_time = 0.0
        _repeat_timer = 0.0
        return
    if _nav_held == dir:
        return
    _nav_held = dir
    _hold_time = 0.0
    _repeat_timer = HOLD_DELAY
    move_focus(dir)

func _process(delta: float) -> void:
    if _cooldown > 0.0:
        _cooldown = maxf(_cooldown - delta, 0.0)
    if _nav_held != 0:
        _hold_time += delta
        _repeat_timer -= delta
        if _repeat_timer <= 0.0 and _cooldown <= 0.0:
            move_focus(_nav_held)
            _repeat_timer = HOLD_STEP if _hold_time < HOLD_DELAY + HOLD_STEP * 4.0 else HOLD_STEP_FAST

# --- input (keyboard/gamepad; mouse is row-level) ---------------------------

func _input(event: InputEvent) -> void:
    # Navigation keys are handled eagerly (and consumed) so the list is the
    # cursor; Enter stays unhandled so a focused button still gets it first.
    if not is_visible_in_tree() or not (event is InputEventKey) or event.echo:
        return
    var key: InputEventKey = event
    if key.pressed:
        match key.keycode:
            KEY_UP, KEY_W:
                set_nav_held(-1)
            KEY_DOWN, KEY_S:
                set_nav_held(1)
            KEY_LEFT, KEY_A:
                adjust(-1)
            KEY_RIGHT, KEY_D:
                adjust(1)
            KEY_ESCAPE, KEY_BACKSPACE:
                go_back()
            KEY_ENTER, KEY_KP_ENTER:
                pass  # left to _unhandled_key_input / focused buttons
            _:
                return
        get_viewport().set_input_as_handled()
    else:
        if key.keycode in [KEY_UP, KEY_W, KEY_DOWN, KEY_S]:
            set_nav_held(0)
            get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
    if not is_visible_in_tree():
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
        confirm()

func _on_row_hover(index: int) -> void:
    if _cooldown <= 0.0 and focus_enabled(index) and index != focus:
        set_focus(index)
        sound_requested.emit("move")

func _on_row_clicked(index: int) -> void:
    if _cooldown > 0.0:
        return
    if index != focus:
        set_focus(index)
        return
    confirm()

func _adjust_from(index: int, dir: int) -> void:
    if _cooldown > 0.0:
        return
    if index != focus:
        set_focus(index)
    adjust(dir)

# --- rendering / transitions ------------------------------------------------

func _refresh_all() -> void:
    for i in _row_nodes.size():
        _refresh_row(i)

func _refresh_row(index: int) -> void:
    if index >= _row_nodes.size():
        return
    var row_def: Dictionary = rows[index]
    var button: Button = _row_nodes[index] as Button
    var focused := index == focus
    var enabled: bool = row_def.get("enabled", true)
    var fill := Color("35595a") if focused else Color("284e50")
    if not enabled:
        fill = Color("302e29")
    var border := Color("e5ad69") if focused else Color("1b3436")
    button.add_theme_stylebox_override("normal", _box(fill, border, 3 if focused else 2))
    var value_label := button.find_child("Value", true, false) as Label
    if value_label != null:
        var values: Array = row_def.get("values", [])
        var v := int(row_def.get("value", 0))
        value_label.text = str(values[v]) if v >= 0 and v < values.size() else ""
        value_label.modulate = Color(1, 1, 1, 1.0 if enabled else 0.45)
    button.modulate = Color(1, 1, 1, 1.0 if enabled else 0.6)

func play_enter() -> void:
    # 20F one-shot list transition (Doc 01 §4.1): eases in from small+transparent.
    _exiting = false
    if _list == null:
        return
    _list.pivot_offset = Vector2(_list.size.x * 0.5, 0.0)
    _list.modulate.a = 0.0
    _list.scale = Vector2(0.97, 0.94)
    var tween := create_tween().set_parallel()
    tween.tween_property(_list, "modulate:a", 1.0, TRANSITION_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_property(_list, "scale", Vector2.ONE, TRANSITION_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func play_exit(then: Callable = Callable()) -> void:
    if _exiting:
        return
    _exiting = true
    _cooldown = maxf(_cooldown, TRANSITION_SECONDS)
    if _list == null:
        if then.is_valid():
            then.call()
        return
    var tween := create_tween().set_parallel()
    tween.tween_property(_list, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    tween.tween_property(_list, "scale", Vector2(0.97, 0.94), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    if then.is_valid():
        tween.chain().tween_callback(then)
