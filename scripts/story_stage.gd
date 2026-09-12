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
#   └── StoryStage (this)      (full-rect overlay; owns the HandCursor)
#       └── HandCursor

signal chosen(id: String)

const HandCursorScript = preload("res://scripts/hand_cursor.gd")
const CARD_SIZE := Vector2(150, 172)

# Chip flow (Melee CSS grammar): the hand carries the P1 chip until the first
# pick; the chip then falls out of the pinch onto the chosen card. Later picks
# hop the landed chip to the new card.
enum TokenMode { NONE, CARRY, FALLING, LANDED }
const FALL_SECONDS := 0.32

var cursor: Control
var ids: Array[String] = []

var _cards: Array[Button] = []
var _selected_id := ""
var _token_mode: TokenMode = TokenMode.NONE
var _picked := false
var _fall_from := Vector2.ZERO
var _fall_to := Vector2.ZERO
var _fall_t := 0.0
var _fall_index := -1
var _chip_pos := Vector2.ZERO
var _settle := 1.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    cursor = HandCursorScript.new()
    cursor.name = "HandCursor"
    add_child(cursor)

func build(fighter_ids: Array[String], row: Container) -> void:
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

func focus_selected() -> void:
    var index := ids.find(_selected_id)
    if index >= 0 and index < _cards.size():
        _cards[index].grab_focus()

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
    _fall_index = -1
    _fall_t = 0.0
    _settle = 1.0
    cursor.set_carry("P1")
    _refresh_styles()

func get_chip_position() -> Vector2:
    return _chip_pos

func is_chip_landed() -> bool:
    return _token_mode == TokenMode.LANDED

func _on_card_pressed(index: int) -> void:
    var first_pick: bool = not _picked
    _picked = true
    _selected_id = ids[index]
    if first_pick:
        var from: Vector2 = cursor.release_carry() if cursor.is_carrying() else _chip_pos
        _begin_fall(from, index)
    elif _token_mode == TokenMode.FALLING:
        # Re-pick while the chip is mid-air: retarget the fall (keep the drop line).
        _fall_index = index
        _fall_to = _landing_pos(_fall_from, index)
    elif index != _fall_index:
        _begin_fall(_chip_pos, index)
    _refresh_styles()
    chosen.emit(_selected_id)

func _refresh_styles() -> void:
    for index in _cards.size():
        var selected: bool = _picked and ids[index] == _selected_id
        var fill := Color("35595a") if selected else Color("284e50")
        var border := Color("e5ad69") if selected else Color("1b3436")
        _cards[index].add_theme_stylebox_override("normal", _box(fill, border, 3 if selected else 2))

func _landing_pos(from: Vector2, index: int) -> Vector2:
    # The chip falls straight down from where it was released and rests on the
    # card's floor. x stays put (clamped so the chip keeps fully inside the
    # picked card) — it never drifts to a preset slot.
    var rect := _cards[index].get_global_rect()
    return Vector2(clampf(from.x, rect.position.x + 26.0, rect.end.x - 26.0), rect.position.y + rect.size.y - 26.0)

func _begin_fall(from: Vector2, index: int) -> void:
    _fall_from = from
    _fall_to = _landing_pos(from, index)
    _fall_index = index
    _fall_t = 0.0
    _settle = 1.0
    _token_mode = TokenMode.FALLING
    _refresh_styles()
    queue_redraw()

func _process(delta: float) -> void:
    if _token_mode == TokenMode.FALLING:
        _fall_t = minf(_fall_t + delta / FALL_SECONDS, 1.0)
        var progress_x := minf(_fall_t * 2.2, 1.0)
        var progress_y := pow(_fall_t, 1.4)
        _chip_pos = Vector2(lerpf(_fall_from.x, _fall_to.x, progress_x), lerpf(_fall_from.y, _fall_to.y, progress_y))
        if _fall_t >= 1.0:
            _chip_pos = _fall_to
            _token_mode = TokenMode.LANDED
            _settle = 0.0
        queue_redraw()
    elif _token_mode == TokenMode.LANDED and _settle < 1.0:
        _settle = minf(_settle + delta / 0.16, 1.0)
        queue_redraw()

func _draw() -> void:
    if _token_mode != TokenMode.FALLING and _token_mode != TokenMode.LANDED:
        return
    var squash := 1.0 - _settle
    draw_set_transform(_chip_pos, 0.0, Vector2(1.0 + 0.28 * squash, 1.0 - 0.28 * squash))
    draw_circle(Vector2.ZERO, 22.0, Color("8a5a2b"))
    draw_circle(Vector2.ZERO, 20.0, Color("e5ad69"))
    var font := ThemeDB.fallback_font
    var width := font.get_string_size("P1", HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
    draw_string(font, Vector2(-width * 0.5, 6.0), "P1", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("284e50"))

func _box(bg: Color, border: Color, width: int, radius := 10) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = bg
    box.border_color = border
    box.set_border_width_all(width)
    box.set_corner_radius_all(radius)
    box.content_margin_left = 6
    box.content_margin_right = 6
    return box
