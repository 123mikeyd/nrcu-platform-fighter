extends Control
# Story screen as a Smash-style selection stage (Melee CSS pilot).
#
# Presentation only: the cards and the hand cursor drive the existing hidden
# OptionButton "StoryCharacterSelect" through main.gd. That keeps the selection
# model (and the existing test suite) untouched while the screen learns the
# Smash grammar: pick a fighter with a hand, confirm with a press.
#
# Pilo architecture:
#   story_panel
#   ├── shade
#   ├── center/column          (title, detail, card row via build(), buttons)
#   └── StoryStage (this)      (full-rect overlay; binds the global hand cursor)
#       └── HandCursor

signal chosen(id: String)

const HandCursorScript = preload("res://scripts/hand_cursor.gd")
const CARD_SIZE := Vector2(150, 172)

# Chip flow (Melee CSS grammar): the hand carries the P1 chip until the first
# pick; the chip then falls out of the pinch onto the chosen card. Later picks
# hop the landed chip to the new card.
enum TokenMode { NONE, CARRY, PLACING, LANDED }
# Melee grammar: the chip is SET DOWN, not dropped — a short settle from the
# carried spot (with a small downward nudge), no vertical travel to a slot.
const PLACE_SECONDS := 0.14
const PLACE_NUDGE := 10.0
const CHIP_INSET := 14.1
const CHIP_PX := 20.3

var cursor: Control
var ids: Array[String] = []

var _cards: Array[Button] = []
var _selected_id := ""
var _token_mode: TokenMode = TokenMode.NONE
var _picked := false
var _place_from := Vector2.ZERO
var _place_to := Vector2.ZERO
var _place_t := 0.0
var _chip_index := -1
var _chip_pos := Vector2.ZERO
var _settle := 1.0
var _tex_coin: Texture2D
var _row: Container
# Melee-style input hygiene (01 §2.2/§4.1): inputs are swallowed during a
# short scene-start lock and a short cooldown after every pick.
var _input_lock := 0.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _tex_coin = load("res://assets/ui/coin_p1.png")
    # Prefer the global hand cursor (autoload) so the same glove appears on
    # every screen; fall back to a local instance when it is unavailable.
    var global_cursor := get_node_or_null("/root/Cursor")
    if global_cursor != null and global_cursor.hand != null:
        cursor = global_cursor.hand
    else:
        cursor = HandCursorScript.new()
        cursor.name = "HandCursor"
        add_child(cursor)

func build(fighter_ids: Array[String], row: Container) -> void:
    _row = row
    ids = fighter_ids.duplicate()
    var roster = load("res://scripts/roster.gd")
    for index in ids.size():
        row.add_child(_make_card(index, roster))

func get_cards() -> Array:
    return _cards

func get_selected_id() -> String:
    return _selected_id

func set_selected_id(id: String) -> void:
    _selected_id = id
    _refresh_styles()

func _make_card(index: int, roster) -> Button:
    var id: String = ids[index]
    var card := Button.new()
    card.name = "FighterCard%d" % index
    card.custom_minimum_size = CARD_SIZE
    card.focus_mode = Control.FOCUS_ALL
    card.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, Color("e5ad69"), 2))
    card.add_theme_stylebox_override("hover", _box(Color("3d6362"), Color("e5ad69"), 2))
    card.add_theme_stylebox_override("pressed", _box(Color("2f4f4e"), Color("e5ad69"), 2))
    var accent := Panel.new()
    accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
    accent.position = Vector2(10, 10)
    accent.size = Vector2(CARD_SIZE.x - 20, 12)
    accent.add_theme_stylebox_override("panel", _box(roster.palette(id, 0), Color.TRANSPARENT, 0, 6))
    card.add_child(accent)
    var name_label := Label.new()
    name_label.text = roster.display_name(id).to_upper()
    name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    name_label.position = Vector2(8, 38)
    name_label.size = Vector2(CARD_SIZE.x - 16, 70)
    name_label.add_theme_font_size_override("font_size", 16)
    name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    card.add_child(name_label)
    card.pressed.connect(_on_card_pressed.bind(index))
    cursor.add_target(card)
    _cards.append(card)
    return card

func begin_pick() -> void:
    # Called when the screen opens: no pick yet, the hand carries the chip.
    _picked = false
    _token_mode = TokenMode.CARRY
    _chip_index = -1
    _place_t = 0.0
    _settle = 1.0
    cursor.set_carry()
    cursor.press_frame_enabled = false
    lock_input(0.33)
    _refresh_styles()

func get_input_lock() -> float:
    return _input_lock

func lock_input(seconds: float) -> void:
    _input_lock = maxf(_input_lock, seconds)

func play_enter() -> void:
    # 20F one-shot enter (Melee ENTER_TO): the card row eases in from slightly
    # small + transparent. Containers own position, so we animate scale+fade.
    if _row == null:
        return
    _row.pivot_offset = Vector2(_row.size.x * 0.5, 0.0)
    _row.modulate.a = 0.0
    _row.scale = Vector2(0.96, 0.92)
    var tween := create_tween().set_parallel()
    tween.tween_property(_row, "modulate:a", 1.0, 0.33).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_property(_row, "scale", Vector2.ONE, 0.33).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func get_chip_position() -> Vector2:
    return _chip_pos

func is_chip_visible() -> bool:
    return _token_mode == TokenMode.PLACING or _token_mode == TokenMode.LANDED

func clear_chip() -> void:
    # Drop the selection chip entirely (the selection is over, e.g. the
    # encounter started and the results screen reuses this panel).
    _token_mode = TokenMode.NONE
    _chip_index = -1
    _settle = 1.0
    queue_redraw()

func is_chip_landed() -> bool:
    return _token_mode == TokenMode.LANDED

func _on_card_pressed(index: int) -> void:
    if _input_lock > 0.0:
        return
    lock_input(0.083)
    var first_pick: bool = not _picked
    _picked = true
    _selected_id = ids[index]
    if first_pick:
        var from: Vector2 = cursor.release_carry() if cursor.is_carrying() else _chip_pos
        _begin_place(from, from + Vector2(0.0, PLACE_NUDGE), index)
    elif _token_mode == TokenMode.PLACING:
        # Re-pick while the chip is moving: retarget the placement.
        _chip_index = index
        _place_to = _place_target(_place_from + Vector2(0.0, PLACE_NUDGE), index)
    elif index != _chip_index:
        var anchor: Vector2 = cursor.chip_world_position() + Vector2(0.0, PLACE_NUDGE)
        _begin_place(_chip_pos, anchor, index)
    _refresh_styles()
    chosen.emit(_selected_id)

func _refresh_styles() -> void:
    for index in _cards.size():
        var selected: bool = _picked and ids[index] == _selected_id
        var fill := Color("35595a") if selected else Color("284e50")
        var border := Color("e5ad69") if selected else Color("1b3436")
        _cards[index].add_theme_stylebox_override("normal", _box(fill, border, 3 if selected else 2))

func _place_target(from: Vector2, index: int) -> Vector2:
    # Keep the set-down chip fully inside the picked card, near where the hand
    # was — it is never re-homed to a preset slot.
    var rect := _cards[index].get_global_rect()
    return Vector2(
        clampf(from.x, rect.position.x + CHIP_INSET, rect.end.x - CHIP_INSET),
        clampf(from.y, rect.position.y + CHIP_INSET, rect.end.y - CHIP_INSET))

func _begin_place(from: Vector2, to: Vector2, index: int) -> void:
    _place_from = from
    _place_to = _place_target(to, index)
    _chip_index = index
    _place_t = 0.0
    _settle = 1.0
    _token_mode = TokenMode.PLACING
    _refresh_styles()
    queue_redraw()

func _process(delta: float) -> void:
    if _input_lock > 0.0:
        _input_lock = maxf(_input_lock - delta, 0.0)
    if _token_mode == TokenMode.PLACING:
        _place_t = minf(_place_t + delta / PLACE_SECONDS, 1.0)
        var ease := 1.0 - pow(1.0 - _place_t, 3.0)
        _chip_pos = _place_from.lerp(_place_to, ease)
        if _place_t >= 1.0:
            _chip_pos = _place_to
            _token_mode = TokenMode.LANDED
            _settle = 0.0
        queue_redraw()
    elif _token_mode == TokenMode.LANDED and _settle < 1.0:
        _settle = minf(_settle + delta / 0.16, 1.0)
        queue_redraw()

func _draw() -> void:
    if _token_mode != TokenMode.PLACING and _token_mode != TokenMode.LANDED:
        return
    var squash := 1.0 - _settle
    draw_set_transform(_chip_pos, 0.0, Vector2(1.0 + 0.28 * squash, 1.0 - 0.28 * squash))
    if _tex_coin != null:
        var half := Vector2(CHIP_PX, CHIP_PX) * 0.5
        draw_texture_rect(_tex_coin, Rect2(-half, half * 2.0), false)
        return
    draw_circle(Vector2.ZERO, CHIP_PX * 0.5, Color("8a5a2b"))
    draw_circle(Vector2.ZERO, CHIP_PX * 0.5 - 2.0, Color("e5ad69"))

func _box(bg: Color, border: Color, width: int, radius := 10) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = bg
    box.border_color = border
    box.set_border_width_all(width)
    box.set_corner_radius_all(radius)
    box.content_margin_left = 6
    box.content_margin_right = 6
    return box
