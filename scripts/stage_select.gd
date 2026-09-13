extends Control
# Stage select, Melee grammar (Dossier WP-04 / 542-544) in NRCU's own art:
#   - staggered tile entrance: one shared off-screen anchor on the right, the
#     tiles arrive 0/5/10 ticks apart (retail: PositionAnimation TRAX rows)
#   - sticky hover: only the stage tiles report hover; gaps keep the last one
#   - highlight box follows the hovered tile with the 10-tick pulse
#   - stage name swaps with the 9-tick in / 11-tick out overlap
#   - confirm: 30-tick input lock, cursor drops out, page exits to setup
# Presentation only: the chosen level id goes back to main.gd, which writes it
# into the hidden setup model (no dropdown is touched here).

signal confirmed(id: String)
signal exit_finished

const FPS := 60.0
# Stage tiles are compact and scalable; the preview and the name are their
# own regions (the tile is not the preview).
const COLS := 4
const CELL_W := 140.0
const CELL_H := 92.0
const GAP := 10.0
const FIELD_X := 60.0
const FIELD_W := 590.0
const FIELD_TOP := 170.0
const FIELD_BOTTOM := 540.0
const PREVIEW_RECT := Rect2(700.0, 170.0, 540.0, 300.0)
const NAME_Y := 486.0
const FLYIN_DELAY_TICKS := [0.0, 5.0, 10.0]
const FLYIN_TICKS := 12.0
const ENTER_LOCK := 0.35
const CONFIRM_LOCK := 30.0 / FPS
const NAME_IN := 9.0 / FPS
const NAME_OUT := 11.0 / FPS
const PULSE_TICKS := 10.0

enum Phase { ENTERING, IDLE, CONFIRMING, EXITING }

var cursor: Control

var _slots: Array = []
var _tiles: Array = []
var _content: Control
var _box: Panel
var _preview: TextureRect
var _name_label: Label
var _back: Button
var _park := Vector2(1900.0, 375.0)
var _phase: Phase = Phase.IDLE
var _lock := 0.0
var _hovered := -1
var _focus_index := -1
var _confirmed := ""
var _pulse := 0.0

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var root = get_node_or_null("/root/Cursor")
    if root != null:
        cursor = root.hand

func build(slots: Array) -> void:
    # Re-entrant: rebuilding with a different stage list replaces the old
    # field (used by the scalability tests with synthetic stage counts).
    if _content != null and is_instance_valid(_content):
        _content.queue_free()
        _content = null
        _slots = []
        _tiles.clear()
    _slots = slots
    _content = Control.new()
    _content.name = "StageContent"
    _content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_content)
    var view: Vector2 = get_viewport_rect().size
    _park = Vector2(maxf(view.x, 1280.0) + 620.0, FIELD_TOP + CELL_H * 0.5)
    var title := Label.new()
    title.text = "STAGE SELECT"
    title.position = Vector2(64.0, 44.0)
    title.add_theme_font_size_override("font_size", 30)
    _content.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "Click a stage to confirm it - Esc / BACK goes back."
    subtitle.position = Vector2(66.0, 84.0)
    subtitle.add_theme_font_size_override("font_size", 16)
    subtitle.modulate = Color(1, 1, 1, 0.72)
    _content.add_child(subtitle)
    _back = Button.new()
    _back.name = "StageBack"
    _back.text = "BACK"
    _back.size = Vector2(170.0, 50.0)
    _back.position = Vector2(maxf(view.x, 1280.0) - 234.0, 44.0)
    _back.pressed.connect(request_back)
    _content.add_child(_back)
    _box = Panel.new()
    _box.name = "SelectBox"
    _box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _box.add_theme_stylebox_override("panel", _flat(Color(0, 0, 0, 0), Color("e5ad69"), 3, 14))
    _box.hide()
    _content.add_child(_box)
    # Stage grid: stable cell scale; more stages pack tighter, the reserved
    # field and the preview/name regions stay fixed.
    var count: int = _slots.size()
    var rows: int = maxi(ceili(float(count) / COLS), 1)
    var cell_h: float = minf(CELL_H, (FIELD_BOTTOM - FIELD_TOP - (rows - 1) * GAP) / rows)
    var cell_w: float = cell_h * (CELL_W / CELL_H)
    var cell_size := Vector2(cell_w, cell_h)
    for i in count:
        var slot: Dictionary = _slots[i]
        var row: int = i / COLS
        var col: int = i % COLS
        var in_row: int = mini(count - row * COLS, COLS)
        var row_total: float = in_row * cell_w + maxf(in_row - 1, 0) * GAP
        var row_x: float = FIELD_X + (FIELD_W - row_total) * 0.5 + cell_w * 0.5
        var center := Vector2(row_x + col * (cell_w + GAP), FIELD_TOP + cell_h * 0.5 + row * (cell_h + GAP))
        slot["anchor"] = center
        var tile := Button.new()
        tile.name = "StageTile" + str(i)
        tile.size = cell_size
        tile.custom_minimum_size = cell_size
        tile.pivot_offset = cell_size * 0.5
        tile.add_theme_stylebox_override("normal", _flat(Color("284e50"), Color("1b3436"), 2, 12))
        tile.add_theme_stylebox_override("hover", _flat(Color("284e50"), Color("1b3436"), 2, 12))
        tile.add_theme_stylebox_override("pressed", _flat(Color("3a6364"), Color("e5ad69"), 2, 12))
        tile.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12))
        tile.position = center - cell_size * 0.5
        var picture := TextureRect.new()
        picture.name = "StageThumbnail" + str(i)
        picture.texture = load(str(slot["tex"]))
        picture.position = Vector2(5.0, 5.0)
        picture.size = Vector2(cell_w - 10.0, cell_h - 30.0)
        picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
        tile.add_child(picture)
        var caption := Label.new()
        caption.text = str(slot["name"])
        caption.position = Vector2(4.0, cell_h - 25.0)
        caption.size = Vector2(cell_w - 8.0, 20.0)
        caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        caption.add_theme_font_size_override("font_size", 12)
        caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
        tile.add_child(caption)
        tile.pressed.connect(_on_tile_pressed.bind(i))
        tile.mouse_entered.connect(_on_tile_hovered.bind(i))
        _content.add_child(tile)
        _tiles.append(tile)
        if cursor != null:
            cursor.add_target(tile)
    # The preview is its own region: the tile is not the preview.
    _preview = TextureRect.new()
    _preview.name = "StagePreview"
    _preview.position = PREVIEW_RECT.position
    _preview.size = PREVIEW_RECT.size
    _preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _content.add_child(_preview)
    var preview_frame := Panel.new()
    preview_frame.name = "PreviewFrame"
    preview_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    preview_frame.position = PREVIEW_RECT.position - Vector2(6.0, 6.0)
    preview_frame.size = PREVIEW_RECT.size + Vector2(12.0, 12.0)
    preview_frame.add_theme_stylebox_override("panel", _flat(Color(0, 0, 0, 0), Color("8a5a2b"), 2, 10))
    _content.add_child(preview_frame)
    _name_label = Label.new()
    _name_label.name = "StageName"
    _name_label.size = Vector2(PREVIEW_RECT.size.x, 56.0)
    _name_label.position = Vector2(PREVIEW_RECT.position.x, NAME_Y)
    _name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _name_label.add_theme_font_size_override("font_size", 34)
    _content.add_child(_name_label)
    if cursor != null:
        cursor.add_target(_back)

func open_with(current_id: String, focus_id: String) -> void:
    _confirmed = ""
    _phase = Phase.ENTERING
    _lock = ENTER_LOCK
    _hovered = -1
    _pulse = 0.0
    _box.hide()
    _focus_index = _index_of(focus_id)
    if _focus_index < 0:
        _focus_index = _index_of(current_id)
    if _preview != null:
        _preview.texture = null
    _name_label.text = "CHOOSE YOUR STAGE"
    _name_label.modulate = Color(1, 1, 1, 0.55)
    _name_label.position.y = NAME_Y
    _content.modulate.a = 1.0
    Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
    if cursor != null:
        # Stage Select always uses the regular cursor (project decision):
        # the Character Select token state must never leak in here.
        cursor.visible = true
        cursor.clear_carry()
        cursor.press_frame_enabled = true
    for i in _tiles.size():
        var tile: Button = _tiles[i]
        tile.modulate.a = 1.0
        tile.scale = Vector2.ONE
        tile.position = _park - tile.size * 0.5
        var target: Vector2 = _slots[i]["anchor"] - tile.size * 0.5
        var tween := create_tween()
        tween.tween_property(tile, "position", target, FLYIN_TICKS / FPS).set_delay(FLYIN_DELAY_TICKS[i] / FPS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        if i == _tiles.size() - 1:
            tween.finished.connect(_on_flyin_done)

func _on_flyin_done() -> void:
    if _phase != Phase.ENTERING:
        return
    _phase = Phase.IDLE
    if _focus_index >= 0:
        hover_slot(_focus_index)
        _focus_index = -1

func hover_slot(index: int) -> void:
    if _phase == Phase.EXITING or _phase == Phase.CONFIRMING:
        return
    if index < 0 or index >= _tiles.size():
        return
    if index == _hovered:
        return
    _hovered = index
    var tile: Button = _tiles[index]
    var rect := tile.get_rect()
    _box.position = rect.position - Vector2(10.0, 10.0)
    _box.size = rect.size + Vector2(20.0, 20.0)
    _box.show()
    if _preview != null:
        _preview.texture = load(str(_slots[index]["tex"]))
    _swap_name(str(_slots[index]["name"]))

func _on_tile_hovered(index: int) -> void:
    hover_slot(index)

func _on_tile_pressed(index: int) -> void:
    if _phase != Phase.IDLE or _lock > 0.0:
        return
    if _hovered != index:
        hover_slot(index)
        return
    confirm()

func confirm() -> void:
    if _phase != Phase.IDLE or _lock > 0.0 or _hovered < 0:
        return
    _confirmed = str(_slots[_hovered]["id"])
    _phase = Phase.CONFIRMING
    _lock = CONFIRM_LOCK
    if cursor != null:
        cursor.visible = false
    var tile: Button = _tiles[_hovered]
    var pop := create_tween()
    pop.tween_property(tile, "scale", Vector2(1.05, 1.05), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    pop.tween_property(tile, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    confirmed.emit(_confirmed)

func request_back() -> void:
    if _phase == Phase.CONFIRMING or _phase == Phase.EXITING:
        return
    _confirmed = ""
    play_exit()

func play_exit() -> void:
    if _phase == Phase.EXITING:
        return
    _phase = Phase.EXITING
    _lock = 0.0
    _box.hide()
    var tween := create_tween()
    tween.tween_property(_content, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    tween.tween_callback(func() -> void: exit_finished.emit())

func reset() -> void:
    _phase = Phase.IDLE
    _lock = 0.0
    _hovered = -1
    _confirmed = ""
    if _box != null:
        _box.hide()
    if cursor != null:
        cursor.visible = true

func get_tiles() -> Array:
    return _tiles

func get_back_button() -> Button:
    return _back

func get_hovered_id() -> String:
    return str(_slots[_hovered]["id"]) if _hovered >= 0 else ""

func get_confirmed_id() -> String:
    return _confirmed

func get_name_text() -> String:
    return _name_label.text if _name_label != null else ""

func get_box_visible() -> bool:
    return _box != null and _box.visible

func get_input_lock() -> float:
    return _lock

func lock_input(seconds: float) -> void:
    _lock = maxf(_lock, seconds)

func is_exiting() -> bool:
    return _phase == Phase.EXITING

func is_confirming() -> bool:
    return _phase == Phase.CONFIRMING

func _index_of(id: String) -> int:
    for i in _slots.size():
        if str(_slots[i]["id"]) == id:
            return i
    return -1

func _swap_name(text: String) -> void:
    if _name_label.text == text:
        return
    var outgoing := Label.new()
    outgoing.text = _name_label.text
    outgoing.position = _name_label.position
    outgoing.size = _name_label.size
    outgoing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    outgoing.add_theme_font_size_override("font_size", 34)
    outgoing.modulate = _name_label.modulate
    _content.add_child(outgoing)
    _name_label.text = text
    _name_label.position.y = NAME_Y + 14.0
    _name_label.modulate = Color(1, 1, 1, 0.0)
    var incoming := create_tween().set_parallel()
    incoming.tween_property(_name_label, "modulate:a", 1.0, NAME_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    incoming.tween_property(_name_label, "position:y", NAME_Y, NAME_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    var leaving := create_tween().set_parallel()
    leaving.tween_property(outgoing, "modulate:a", 0.0, NAME_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    leaving.tween_property(outgoing, "position:y", NAME_Y - 14.0, NAME_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    leaving.chain().tween_callback(outgoing.queue_free)

func _process(delta: float) -> void:
    if _lock > 0.0:
        _lock = maxf(_lock - delta, 0.0)
    if _box != null and _box.visible and _phase != Phase.EXITING:
        _pulse += delta
        _box.modulate.a = 0.72 + 0.28 * (0.5 + 0.5 * sin(TAU * _pulse / (PULSE_TICKS / FPS)))
    if _phase == Phase.CONFIRMING and _lock <= 0.0:
        play_exit()

func _unhandled_key_input(event: InputEvent) -> void:
    if not is_visible_in_tree():
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
            confirm()
            get_viewport().set_input_as_handled()

func _flat(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = border
    style.set_border_width_all(width)
    style.set_corner_radius_all(radius)
    return style
