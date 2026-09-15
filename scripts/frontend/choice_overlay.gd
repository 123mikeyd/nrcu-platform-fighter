extends Control
# Shared binary-choice overlay presentation for Pause and global Quit.
# Route owners remain responsible for their state machines; this module owns the
# one NRCU visual grammar: dim -> centered shell -> title -> MenuRow choices.

signal choice_pressed(index: int)
signal choice_focused(index: int)

const Tokens = preload("res://scripts/ui_tokens.gd")
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")
const MenuRowScene = preload("res://scenes/components/MenuRow.tscn")

const PLATE_RECT := Rect2(410.0, 224.0, 460.0, 272.0)
const ROW_W := 460.0
const ROW_H := 68.0
const ROW_TOPS: Array = [92.0, 176.0]
const ROW_PLATE_X := 28.0
const ROW_PLATE_W := 404.0
const ROW_PLATE_Y := 5.0
const ROW_PLATE_H := 58.0
const LABEL_X := 40.0
const LABEL_SHIFT := 9.0
const LEDGE_Y := 64.0
const LEDGE_H := 3.0
const QUIET_H := 2.0
const QUIET_Y := 42.0
const QUIET_GAP := 8.0
const QUIET_RIGHT_INSET := 24.0
const ACTIVE_SIZE := 36
const INACTIVE_SIZE := 26

var _dim: ColorRect
var _plate: Panel
var _title: Label
var _rows: Array = []
var _active := 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _build()
    hide()

func _build() -> void:
    _dim = ColorRect.new()
    _dim.name = "Dim"
    _dim.color = Color(0.0, 0.0, 0.0, 0.58)
    _dim.mouse_filter = Control.MOUSE_FILTER_STOP
    _dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(_dim)

    var frame := Tokens.make_reference_frame(self)
    _plate = Panel.new()
    _plate.name = "Plate"
    _plate.position = PLATE_RECT.position
    _plate.size = PLATE_RECT.size
    _plate.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_FLAT))
    frame.add_child(_plate)

    _title = Label.new()
    _title.name = "OverlayTitle"
    _title.position = Vector2(40.0, 28.0)
    _title.size = Vector2(380.0, 40.0)
    _title.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _title.add_theme_font_override("font", Tokens.font("semibold"))
    _title.add_theme_font_size_override("font_size", Tokens.T_SCREEN)
    _title.add_theme_color_override("font_color", Tokens.CREAM)
    _plate.add_child(_title)

    _rows = [
        _make_row("RowChoice0", 0, "CHOICE", "Action0"),
        _make_row("RowChoice1", 1, "CHOICE", "Action1"),
    ]
    for index in _rows.size():
        var hit: Button = _rows[index]["hit"]
        hit.pressed.connect(_on_choice_pressed.bind(index))
        hit.focus_entered.connect(_on_choice_focused.bind(index))
    _set_active(0)

    _wire_choice_focus()

func _wire_choice_focus() -> void:
    var hits: Array = [_rows[0]["hit"], _rows[1]["hit"]]
    FocusGraph.chain(hits, true)
    # Two choices are a trapped pair. All four directions remain explicit so
    # keyboard, pad and legacy directional callers cannot escape the modal.
    for direction in [&"left", &"right", &"top", &"bottom"]:
        FocusGraph.wire(hits[0], hits[1], [direction])
        FocusGraph.wire(hits[1], hits[0], [direction])

func _make_row(node_name: String, index: int, text: String, hit_name: String) -> Dictionary:
    var row: Control = (MenuRowScene as PackedScene).instantiate()
    row.name = node_name
    row.position = Vector2(0.0, ROW_TOPS[index])
    row.size = Vector2(ROW_W, ROW_H)
    _plate.add_child(row)

    var hit: Button = row.get_node("HitArea")
    hit.name = hit_name
    hit.position = Vector2.ZERO
    hit.size = Vector2(ROW_W, ROW_H)
    Tokens.apply_styles(hit, {
        "normal": Tokens.flat(Color(0, 0, 0, 0)),
        "hover": Tokens.flat(Color(0, 0, 0, 0)),
        "pressed": Tokens.flat(Color(0, 0, 0, 0)),
        "focus": Tokens.flat(Color(0, 0, 0, 0)),
        "disabled": Tokens.flat(Color(0, 0, 0, 0)),
    })
    hit.add_theme_font_override("font", Tokens.font("medium"))
    hit.add_theme_font_size_override("font_size", INACTIVE_SIZE)
    for color_name in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_disabled_color"]:
        hit.add_theme_color_override(color_name, Color(0, 0, 0, 0))

    var item_plate: Panel = row.get_node("ActivePlate")
    item_plate.position = Vector2(ROW_PLATE_X, ROW_PLATE_Y)
    item_plate.size = Vector2(ROW_PLATE_W, ROW_PLATE_H)
    item_plate.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_2, Color(0, 0, 0, 0), 0, Tokens.RADIUS_PLATE))
    var top_rule: Panel = item_plate.get_node("TopRule")
    top_rule.size = Vector2(ROW_PLATE_W, 1.0)
    top_rule.add_theme_stylebox_override("panel", Tokens.flat(Color(Tokens.ACCENT, 0.28)))

    var label: Label = row.get_node("Label")
    label.text = text
    label.position = Vector2(LABEL_X, 8.0)
    label.size = Vector2(ROW_W - LABEL_X - 40.0, 52.0)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var quiet: Panel = row.get_node("QuietRail")
    quiet.position = Vector2(LABEL_X, QUIET_Y)
    quiet.size = Vector2(0.0, QUIET_H)
    quiet.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE_WARM))
    quiet.modulate.a = 0.55

    var rail: Panel = row.get_node("ActiveRail")
    rail.position = Vector2(ROW_PLATE_X, LEDGE_Y)
    rail.size = Vector2(ROW_PLATE_W, LEDGE_H)
    rail.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))

    return {
        "root": row,
        "hit": hit,
        "plate": item_plate,
        "top_rule": top_rule,
        "label": label,
        "quiet": quiet,
        "rail": rail,
        "anchor": row.get_node("CursorAnchor"),
    }

func configure(title_text: String, labels: Array, row_names: Array = [], action_names: Array = []) -> void:
    _title.text = title_text
    for index in _rows.size():
        var row: Control = _rows[index]["root"]
        var label: Label = _rows[index]["label"]
        row.name = str(row_names[index]) if index < row_names.size() else "RowChoice%d" % index
        (_rows[index]["hit"] as Button).name = str(action_names[index]) if index < action_names.size() else "Action%d" % index
        label.text = str(labels[index]) if index < labels.size() else "CHOICE"
    _wire_choice_focus()
    _set_active(0)

func open() -> void:
    show()
    _set_active(0)
    (_rows[0]["hit"] as Button).grab_focus()

func close() -> void:
    hide()

func _on_choice_pressed(index: int) -> void:
    choice_pressed.emit(index)

func _on_choice_focused(index: int) -> void:
    _set_active(index)
    choice_focused.emit(index)

func set_active(index: int) -> void:
    _set_active(index)

func _set_active(index: int) -> void:
    _active = clampi(index, 0, _rows.size() - 1)
    for i in _rows.size():
        _reflect_row_state(i, i == _active)

func _reflect_row_state(index: int, active: bool) -> void:
    var entry: Dictionary = _rows[index]
    var label: Label = entry["label"]
    var quiet: Panel = entry["quiet"]
    if active:
        label.add_theme_font_size_override("font_size", ACTIVE_SIZE)
        label.add_theme_font_override("font", Tokens.font("medium"))
        label.add_theme_color_override("font_color", Tokens.CREAM)
        label.position.x = LABEL_X + LABEL_SHIFT
        quiet.hide()
        (entry["plate"] as Panel).show()
        (entry["plate"] as Panel).modulate.a = 1.0
        (entry["rail"] as Panel).show()
    else:
        label.add_theme_font_size_override("font_size", INACTIVE_SIZE)
        label.add_theme_font_override("font", Tokens.font("regular"))
        label.add_theme_color_override("font_color", Tokens.CREAM_DIM)
        label.position.x = LABEL_X
        (entry["plate"] as Panel).hide()
        (entry["plate"] as Panel).modulate.a = 0.0
        (entry["rail"] as Panel).hide()
        quiet.show()
        _layout_quiet_rail(entry)

func _layout_quiet_rail(entry: Dictionary) -> void:
    var label: Label = entry["label"]
    var font := label.get_theme_font("font")
    var size := label.get_theme_font_size("font_size")
    var text_width: float = font.get_string_size(str(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
    var quiet: Panel = entry["quiet"]
    var start := label.position.x + text_width + QUIET_GAP
    var end := ROW_PLATE_X + ROW_PLATE_W - QUIET_RIGHT_INSET
    quiet.position.x = start
    quiet.size.x = maxf(end - start, 0.0)

func active_index() -> int:
    return _active

func choice(index: int) -> Button:
    return _rows[index]["hit"]

func choice_label(index: int) -> Label:
    return _rows[index]["label"]

func menu_rows() -> Array:
    var out: Array = []
    for entry in _rows:
        out.append(entry["root"])
    return out

func item_plate(index: int) -> Panel:
    return _rows[index]["plate"]

func active_rail(index: int) -> Panel:
    return _rows[index]["rail"]

func quiet_rail(index: int) -> Panel:
    return _rows[index]["quiet"]

func focus_anchor_for(control: Control) -> Control:
    for index in _rows.size():
        if control == _rows[index]["hit"]:
            return _rows[index]["anchor"]
    return FocusGraph.anchor_of(control)

func choice_index(control: Control) -> int:
    for index in _rows.size():
        if control == _rows[index]["hit"]:
            return index
    return -1

func title_text() -> String:
    return str(_title.text)

func plate_rect() -> Rect2:
    return _plate.get_global_rect()
