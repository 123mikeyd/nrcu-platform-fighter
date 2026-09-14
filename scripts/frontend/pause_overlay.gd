extends Control
# WP-4 Pause surface.
#
# The overlay is deliberately a small, input-complete state machine. Gameplay
# owns the match and the adapter owns SceneTree.paused/input scope; this surface
# only owns the visible actions and emits semantic route requests.
#
# CLOSED --open(story)--> OPEN --resume()--> CLOSED
#                         |
#                         `--leave()--> LEAVING
#
# Gameplay entry: Esc / controller Start -> OPEN.
# OPEN: ui_cancel / RESUME -> CLOSED; LEAVE MATCH/ENCOUNTER -> LEAVING.
#
# ROW GRAMMAR (Doc 07 / owner round): each action is a MenuRow-shaped row --
# the SAME component the owner-approved Main rows use (scenes/components/
# MenuRow.tscn: HitArea / ActivePlate + TopRule / Label / QuietRail /
# ActiveRail / CursorAnchor), fitted to this plate instead of the field:
#   * label left, one authored x for every row (never re-aligned per state);
#   * the SELECTED row carries the plate + the gold ledge (ActiveRail) spanning
#     the row's width directly under it; the quiet rows carry their own QuietRail
#     to the right of the label, ending at the same right edge;
#   * label 26 regular CREAM_DIM quiet / 36 medium CREAM active, +9 px shift.
# State is switched, not tweened: the pause surface is a trap for an
# interrupted match and owns no motion of its own (Doc 07: minimal overlay).
#
# POINTER CONTRACT (WP-1): the physical mouse must always be functional. The
# rows are hit-tested by the viewport (Button hit areas), and the shared hand
# cursor keeps processing while the tree is paused (scripts/cursor_layer.gd),
# so hover follows the authoritatively-positioned pointer and every row can be
# left-clicked through the real viewport GUI path. Hover selects a row exactly
# like the Main rows (the hand's semantic hover drives the visible selection);
# it never moves focus, so a click that focuses a row cannot hijack modality.

signal opened
signal resume_requested
signal leave_requested(mode: String)

const Tokens = preload("res://scripts/ui_tokens.gd")
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")
# The owner-approved row component. The pause rows ARE MenuRow instances with
# their geometry re-fitted to this plate, so the two surfaces can never drift
# into two different row grammars.
const MenuRowScene = preload("res://scenes/components/MenuRow.tscn")

const STATE_CLOSED := "closed"
const STATE_OPEN := "open"
const STATE_LEAVING := "leaving"

const PLATE_RECT := Rect2(410.0, 224.0, 460.0, 272.0)

# --- row grammar (plate-local; mirrors the Main rows' relationships) --------
const ROW_W := 460.0             # the row (and its hit area) spans the plate
const ROW_H := 68.0
const ROW_TOPS: Array = [92.0, 176.0]
const ROW_PLATE_X := 28.0        # item plate left edge
const ROW_PLATE_W := 404.0       # item plate right edge => plate end - 24 for the quiet rail
const ROW_PLATE_Y := 5.0         # item plate top inside the row (MenuRow: 5)
const ROW_PLATE_H := 58.0        # MenuRow: 58
const LABEL_X := 40.0            # = ROW_PLATE_X + 12, exactly like MenuRow's 60 in a plate at 48
const LABEL_SHIFT := 9.0         # the active label settles 9 px right (Main grammar)
const LEDGE_Y := 64.0            # the gold ledge sits at the row's bottom (MenuRow: 64)
const LEDGE_H := 3.0
const QUIET_H := 2.0
const QUIET_Y := 42.0            # the quiet rail sits at the label's baseline
const QUIET_GAP := 8.0           # ... 8 px after the label's shaped text
const QUIET_RIGHT_INSET := 24.0  # ... ending 24 px before the item plate's right edge

const ACTIVE_SIZE := 36
const INACTIVE_SIZE := 26

const ITEM_RESUME := 0
const ITEM_LEAVE := 1

var _state := STATE_CLOSED
var _story := false
var _active := ITEM_RESUME
var _dim: ColorRect
var _plate: Panel
var _title: Label
var _rows: Array = []
var _hover_connected := false

func _ready() -> void:
    name = "PauseOverlay"
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
    _title.name = "PauseTitle"
    _title.text = "PAUSED"
    _title.position = Vector2(40.0, 28.0)
    _title.size = Vector2(380.0, 40.0)
    _title.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _title.add_theme_font_override("font", Tokens.font("semibold"))
    _title.add_theme_font_size_override("font_size", 30)
    _title.add_theme_color_override("font_color", Tokens.CREAM)
    _plate.add_child(_title)

    _rows = [_make_row("RowResume", ITEM_RESUME, "RESUME"), _make_row("RowLeave", ITEM_LEAVE, "LEAVE MATCH")]
    _rows[ITEM_RESUME]["hit"].pressed.connect(_on_resume_pressed)
    _rows[ITEM_LEAVE]["hit"].pressed.connect(_on_leave_pressed)
    for index in _rows.size():
        var hit: Button = _rows[index]["hit"]
        hit.focus_entered.connect(_on_action_focused.bind(index))
    _set_active_action(ITEM_RESUME)

    # Pause is a trapped two-action surface. It never lets tree-order focus
    # escape to the gameplay HUD behind it.
    var hits: Array = [_rows[ITEM_RESUME]["hit"], _rows[ITEM_LEAVE]["hit"]]
    FocusGraph.chain(hits, true)
    for direction in [&"left", &"right", &"top", &"bottom"]:
        FocusGraph.wire(hits[0], hits[1], [direction])
        FocusGraph.wire(hits[1], hits[0], [direction])

func _make_row(node_name: String, index: int, text: String) -> Dictionary:
    var row: Control = (MenuRowScene as PackedScene).instantiate()
    row.name = node_name
    row.position = Vector2(0.0, float(ROW_TOPS[index]))
    row.size = Vector2(ROW_W, ROW_H)
    _plate.add_child(row)

    var hit: Button = row.get_node("HitArea")
    hit.position = Vector2.ZERO
    hit.size = Vector2(ROW_W, ROW_H)
    # No row chrome of any kind: the plate/rails/label ARE the state.
    Tokens.apply_styles(hit, {
        "normal": Tokens.flat(Color(0, 0, 0, 0)),
        "hover": Tokens.flat(Color(0, 0, 0, 0)),
        "pressed": Tokens.flat(Color(0, 0, 0, 0)),
        "focus": Tokens.flat(Color(0, 0, 0, 0)),
        "disabled": Tokens.flat(Color(0, 0, 0, 0)),
    })
    hit.add_theme_font_override("font", Tokens.font("medium"))
    hit.add_theme_font_size_override("font_size", INACTIVE_SIZE)
    hit.add_theme_color_override("font_color", Color(0, 0, 0, 0))
    hit.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
    hit.add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
    hit.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
    hit.add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0))

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

# --- state machine ----------------------------------------------------------
func state() -> String:
    return _state

func is_open() -> bool:
    return _state == STATE_OPEN

func is_leaving() -> bool:
    return _state == STATE_LEAVING

func open(story := false) -> bool:
    if _state != STATE_CLOSED:
        return false
    _story = bool(story)
    _rows[ITEM_LEAVE]["label"].text = "LEAVE ENCOUNTER" if _story else "LEAVE MATCH"
    _state = STATE_OPEN
    show()
    _dim.modulate.a = 1.0
    _set_active_action(ITEM_RESUME)
    _rows[ITEM_RESUME]["hit"].grab_focus()
    var hand = _hand()
    if hand != null:
        if not _hover_connected and not hand.hover_changed.is_connected(_on_hover_changed):
            hand.hover_changed.connect(_on_hover_changed)
            _hover_connected = true
        hand.begin_screen("pause")
        hand.add_target(_rows[ITEM_RESUME]["hit"])
        hand.add_target(_rows[ITEM_LEAVE]["hit"])
    opened.emit()
    return true

func resume() -> bool:
    if _state != STATE_OPEN:
        return false
    _state = STATE_CLOSED
    _hide()
    _drop_targets()
    resume_requested.emit()
    return true

func leave() -> bool:
    if _state != STATE_OPEN:
        return false
    _state = STATE_LEAVING
    _hide()
    _drop_targets()
    leave_requested.emit("story" if _story else "vs")
    return true

# The adapter calls this after opening from a semantic keyboard/pad action.
# The physical pointer is never moved; a later genuine motion switches back to
# MOUSE mode via the shared cursor service.
func focus_default() -> void:
    if _state != STATE_OPEN:
        return
    _rows[ITEM_RESUME]["hit"].grab_focus()
    var hand = _hand()
    if hand != null:
        hand.claim_focus()
        hand.set_focus_target(_anchor_for(ITEM_RESUME))

# --- action/focus contract --------------------------------------------------
func _on_resume_pressed() -> void:
    resume()

func _on_leave_pressed() -> void:
    leave()

func _on_action_focused(index: int) -> void:
    if _state != STATE_OPEN:
        return
    var control: Control = _rows[index]["hit"]
    FocusGraph.track(self, control)
    _set_active_action(index)
    var hand = _hand()
    if hand != null and hand.mode == 1:
        hand.set_focus_target(_anchor_for(index))

func _on_hover_changed(target: Control) -> void:
    # Main-row parity: the pointer drives the visible selection. Focus is never
    # stolen by hover (a click that focuses must not hijack the modality).
    if _state != STATE_OPEN or target == null:
        return
    for index in _rows.size():
        if _rows[index]["hit"] == target:
            _set_active_action(index)
            return

func _set_active_action(index: int) -> void:
    _active = clampi(index, ITEM_RESUME, ITEM_LEAVE)
    for i in _rows.size():
        _reflect_row_state(i, i == _active)

func _reflect_row_state(index: int, active: bool) -> void:
    # One row's authored state, switched (never tweened on this surface).
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
    # The quiet rail starts after the label's shaped text and ends at the same
    # right edge on every row (MenuRow's authored grammar).
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

func focus_anchor_for(control: Control) -> Control:
    for index in _rows.size():
        if control == _rows[index]["hit"]:
            return _anchor_for(index)
    return FocusGraph.anchor_of(control)

func _anchor_for(index: int) -> Control:
    return _rows[index]["anchor"]

func _drop_targets() -> void:
    var hand = _hand()
    if hand != null:
        hand.drop_targets()

func _hide() -> void:
    hide()
    _dim.modulate.a = 0.0

# --- public reads -----------------------------------------------------------
func action_resume() -> Button:
    return _rows[ITEM_RESUME]["hit"]

func action_leave() -> Button:
    return _rows[ITEM_LEAVE]["hit"]

func menu_rows() -> Array:
    var out: Array = []
    for entry in _rows:
        out.append(entry["root"])
    return out

func row_hit(index: int) -> Button:
    return _rows[index]["hit"]

func row_label(index: int) -> Label:
    return _rows[index]["label"]

func item_plate(index: int) -> Panel:
    return _rows[index]["plate"]

func active_rail(index: int) -> Panel:
    return _rows[index]["rail"]

func quiet_rail(index: int) -> Panel:
    return _rows[index]["quiet"]

func title_text() -> String:
    return str(_title.text)

func resume_label() -> String:
    return str(_rows[ITEM_RESUME]["label"].text)

func leave_label() -> String:
    return str(_rows[ITEM_LEAVE]["label"].text)

func is_story_pause() -> bool:
    return _story

func plate_rect() -> Rect2:
    return _plate.get_global_rect()

func _hand():
    var cursor = get_node_or_null("/root/Cursor")
    if cursor == null or cursor.hand == null:
        return null
    return cursor.hand
