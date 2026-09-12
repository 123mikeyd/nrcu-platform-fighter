extends Control
# Character select as the CSS stage (Dossier WP-03 / 62, NRCU adaptation):
# the roster sits in two staggered rows, the hand carries the P1 token until
# the first pick, the token is SET DOWN onto the chosen card (Melee grammar),
# the big name swaps with the 9-in / 11-out overlap, confirm locks input
# (30-tick analog) and the page exits back to the setup.
# Presentation only: the choice goes back to main.gd, which writes it into the
# hidden setup model. Story selection stays story_stage.gd.

signal confirmed(id: String)
signal exit_finished

const FPS := 60.0
const CARD_SIZE := Vector2(250.0, 170.0)
const GAP := 16.0
const ROW1_Y := 300.0
const ROW2_Y := 500.0
const NAME_Y := 598.0
const ENTER_LOCK := 0.5
const CONFIRM_LOCK := 30.0 / FPS
const NAME_IN := 9.0 / FPS
const NAME_OUT := 11.0 / FPS
const PULSE_TICKS := 10.0
const PLACE_SECONDS := 0.14
const PLACE_NUDGE := 10.0
const CHIP_INSET := 14.1
const CHIP_PX := 20.3

enum Phase { ENTERING, IDLE, CONFIRMING, EXITING }
enum TokenMode { NONE, CARRY, PLACING, LANDED }

var cursor: Control

var _slots: Array = []
var _cards: Array = []
var _content: Control
var _box: Panel
var _badge: Panel
var _name_label: Label
var _back: Button
var _phase: Phase = Phase.IDLE
var _token_mode: TokenMode = TokenMode.NONE
var _lock := 0.0
var _hovered := -1
var _current := -1
var _focus_index := -1
var _confirmed := ""
var _pulse := 0.0
var _chip_index := -1
var _chip_pos := Vector2.ZERO
var _place_from := Vector2.ZERO
var _place_to := Vector2.ZERO
var _place_t := 0.0
var _settle := 1.0
var _chip_alpha := 1.0
var _chip_rect: TextureRect
var _tex_coin: Texture2D

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _tex_coin = load("res://assets/ui/coin_p1.png")
    var root = get_node_or_null("/root/Cursor")
    if root != null:
        cursor = root.hand

func build(slots: Array) -> void:
    _slots = slots
    _content = Control.new()
    _content.name = "CharContent"
    _content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_content)
    var view: Vector2 = get_viewport_rect().size
    var title := Label.new()
    title.text = "CHOOSE YOUR FIGHTER"
    title.position = Vector2(64.0, 44.0)
    title.add_theme_font_size_override("font_size", 30)
    _content.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "Click a fighter to confirm it - Esc / BACK returns to the setup."
    subtitle.position = Vector2(66.0, 84.0)
    subtitle.add_theme_font_size_override("font_size", 16)
    subtitle.modulate = Color(1, 1, 1, 0.72)
    _content.add_child(subtitle)
    _back = Button.new()
    _back.name = "CharBack"
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
    var count: int = _slots.size()
    var row1 := mini(count, 4)
    var row2: int = maxi(count - 4, 0)
    var row1_total: float = row1 * CARD_SIZE.x + maxf(row1 - 1, 0) * GAP
    var row2_total: float = row2 * CARD_SIZE.x + maxf(row2 - 1, 0) * GAP
    var row1_x: float = (view.x - row1_total) * 0.5 + CARD_SIZE.x * 0.5
    var row2_x: float = (view.x - row2_total) * 0.5 + CARD_SIZE.x * 0.5
    for i in count:
        var slot: Dictionary = _slots[i]
        var in_row2: bool = i >= 4
        var col: int = i - 4 if in_row2 else i
        var center := Vector2(
            (row2_x if in_row2 else row1_x) + col * (CARD_SIZE.x + GAP),
            ROW2_Y if in_row2 else ROW1_Y)
        slot["anchor"] = center
        var card := Button.new()
        card.name = "FighterCard" + str(i)
        card.size = CARD_SIZE
        card.custom_minimum_size = CARD_SIZE
        card.pivot_offset = CARD_SIZE * 0.5
        card.add_theme_stylebox_override("normal", _flat(Color("284e50"), Color("1b3436"), 2, 12))
        card.add_theme_stylebox_override("hover", _flat(Color("3d6362"), Color("e5ad69"), 2, 12))
        card.add_theme_stylebox_override("pressed", _flat(Color("2f4f4e"), Color("e5ad69"), 3, 12))
        card.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12))
        card.position = center - CARD_SIZE * 0.5
        var accent := Panel.new()
        accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
        accent.position = Vector2(10.0, 10.0)
        accent.size = Vector2(CARD_SIZE.x - 20.0, 14.0)
        accent.add_theme_stylebox_override("panel", _flat(slot["palette"], Color(0, 0, 0, 0), 0, 7))
        card.add_child(accent)
        var name_label := Label.new()
        name_label.text = str(slot["name"]).to_upper()
        name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        name_label.position = Vector2(8.0, 36.0)
        name_label.size = Vector2(CARD_SIZE.x - 16.0, CARD_SIZE.y - 70.0)
        name_label.add_theme_font_size_override("font_size", 26)
        name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card.add_child(name_label)
        card.pressed.connect(_on_card_pressed.bind(i))
        card.mouse_entered.connect(_on_card_hovered.bind(i))
        _content.add_child(card)
        _cards.append(card)
        if cursor != null:
            cursor.add_target(card)
    _badge = Panel.new()
    _badge.name = "CurrentBadge"
    _badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _badge.add_theme_stylebox_override("panel", _flat(Color("e5ad69"), Color("8a5a2b"), 2, 8))
    _badge.size = Vector2(104.0, 30.0)
    var badge_label := Label.new()
    badge_label.text = "CURRENT"
    badge_label.add_theme_font_size_override("font_size", 14)
    badge_label.add_theme_color_override("font_color", Color("273a37"))
    badge_label.position = Vector2(0.0, 4.0)
    badge_label.size = Vector2(104.0, 22.0)
    badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _badge.add_child(badge_label)
    _badge.hide()
    _content.add_child(_badge)
    _name_label = Label.new()
    _name_label.name = "FighterName"
    _name_label.size = Vector2(view.x, 54.0)
    _name_label.position = Vector2(0.0, NAME_Y)
    _name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _name_label.add_theme_font_size_override("font_size", 40)
    _content.add_child(_name_label)
    # The token must draw ABOVE the cards: a parent's own _draw sits below its
    # children in Godot, so the chip lives as the last child instead.
    _chip_rect = TextureRect.new()
    _chip_rect.name = "TokenChip"
    _chip_rect.texture = _tex_coin
    # EXPAND_KEEP_SIZE would ignore the small size and render the raw texture;
    # IGNORE_SIZE keeps the story chip's 20.3 px look (same token everywhere).
    _chip_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _chip_rect.size = Vector2(CHIP_PX, CHIP_PX)
    _chip_rect.pivot_offset = Vector2(CHIP_PX, CHIP_PX) * 0.5
    _chip_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _chip_rect.hide()
    _content.add_child(_chip_rect)
    if cursor != null:
        cursor.add_target(_back)

func open_with(current_id: String, focus_id: String, player_index: int) -> void:
    _confirmed = ""
    _phase = Phase.ENTERING
    _lock = ENTER_LOCK
    _hovered = -1
    _pulse = 0.0
    _box.hide()
    _chip_index = -1
    _settle = 1.0
    _chip_alpha = 1.0
    _focus_index = _index_of(focus_id)
    if _focus_index < 0:
        _focus_index = _index_of(current_id)
    _current = _index_of(current_id)
    if _current >= 0:
        var anchor: Vector2 = _slots[_current]["anchor"]
        _badge.position = anchor + Vector2(CARD_SIZE.x * 0.5 - _badge.size.x - 12.0, -CARD_SIZE.y * 0.5 + 12.0)
        _badge.show()
    else:
        _badge.hide()
    _name_label.text = "CHOOSE YOUR FIGHTER"
    _name_label.modulate = Color(1, 1, 1, 0.55)
    _name_label.position.y = NAME_Y
    _content.modulate.a = 1.0
    Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
    if cursor != null:
        cursor.visible = true
        cursor.set_carry()
        cursor.press_frame_enabled = false
    _token_mode = TokenMode.CARRY
    _refresh_styles()
    for i in _cards.size():
        var card: Button = _cards[i]
        card.modulate.a = 0.0
        card.scale = Vector2.ONE
        var target: Vector2 = _slots[i]["anchor"] - CARD_SIZE * 0.5
        card.position = target + Vector2(0.0, 18.0)
        var tween := create_tween()
        tween.tween_property(card, "position", target, 0.22).set_delay(i * 3.0 / FPS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        tween.parallel().tween_property(card, "modulate:a", 1.0, 0.22).set_delay(i * 3.0 / FPS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        if i == _cards.size() - 1:
            tween.finished.connect(_on_entry_done)

func _on_entry_done() -> void:
    if _phase != Phase.ENTERING:
        return
    _phase = Phase.IDLE
    if _focus_index >= 0:
        hover_slot(_focus_index)
        _focus_index = -1

func hover_slot(index: int) -> void:
    if _phase == Phase.EXITING or _phase == Phase.CONFIRMING:
        return
    if index < 0 or index >= _cards.size():
        return
    if index == _hovered:
        return
    _hovered = index
    var card: Button = _cards[index]
    var rect := card.get_rect()
    _box.position = rect.position - Vector2(14.0, 14.0)
    _box.size = rect.size + Vector2(28.0, 28.0)
    _box.show()
    _swap_name(str(_slots[index]["name"]))

func _on_card_hovered(index: int) -> void:
    hover_slot(index)

func _on_card_pressed(index: int) -> void:
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
    var card: Button = _cards[_hovered]
    var pop := create_tween()
    pop.tween_property(card, "scale", Vector2(1.05, 1.05), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    pop.tween_property(card, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    # Token: set the chip down on the chosen card (Melee grammar: a short
    # settle from the carried spot with a small downward nudge, never a
    # re-homing to a preset slot).
    if _token_mode == TokenMode.CARRY:
        var from: Vector2 = cursor.release_carry() if cursor != null and cursor.is_carrying() else _chip_pos
        _begin_place(from, from + Vector2(0.0, PLACE_NUDGE), _hovered)
    elif _token_mode == TokenMode.PLACING:
        _chip_index = _hovered
        _place_to = _place_target(_place_from + Vector2(0.0, PLACE_NUDGE), _hovered)
    elif _hovered != _chip_index:
        var anchor: Vector2 = cursor.chip_world_position() + Vector2(0.0, PLACE_NUDGE) if cursor != null else _chip_pos
        _begin_place(_chip_pos, anchor, _hovered)
    _refresh_styles()
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
    _token_mode = TokenMode.NONE
    _chip_index = -1
    _chip_alpha = 1.0
    if _box != null:
        _box.hide()
    if cursor != null:
        cursor.visible = true
    _update_chip_visual()

func get_cards() -> Array:
    return _cards

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

func is_chip_landed() -> bool:
    return _token_mode == TokenMode.LANDED

func get_chip_position() -> Vector2:
    return _chip_pos

func _index_of(id: String) -> int:
    for i in _slots.size():
        if str(_slots[i]["id"]) == id:
            return i
    return -1

func _refresh_styles() -> void:
    for index in _cards.size():
        var selected: bool = _confirmed != "" and str(_slots[index]["id"]) == _confirmed
        var fill := Color("35595a") if selected else Color("284e50")
        var border := Color("e5ad69") if selected else Color("1b3436")
        _cards[index].add_theme_stylebox_override("normal", _flat(fill, border, 3 if selected else 2, 12))

func _place_target(from: Vector2, index: int) -> Vector2:
    var rect: Rect2 = _cards[index].get_global_rect()
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
    _update_chip_visual()

func _swap_name(text: String) -> void:
    if _name_label.text == text:
        return
    var outgoing := Label.new()
    outgoing.text = _name_label.text
    outgoing.position = _name_label.position
    outgoing.size = _name_label.size
    outgoing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    outgoing.add_theme_font_size_override("font_size", 40)
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
    if _token_mode == TokenMode.PLACING:
        _place_t = minf(_place_t + delta / PLACE_SECONDS, 1.0)
        var ease := 1.0 - pow(1.0 - _place_t, 3.0)
        _chip_pos = _place_from.lerp(_place_to, ease)
        if _place_t >= 1.0:
            _chip_pos = _place_to
            _token_mode = TokenMode.LANDED
            _settle = 0.0
        _update_chip_visual()
    elif _token_mode == TokenMode.LANDED and _settle < 1.0:
        _settle = minf(_settle + delta / 0.16, 1.0)
        _update_chip_visual()
    if _phase == Phase.EXITING and _chip_alpha > 0.0:
        _chip_alpha = maxf(_chip_alpha - delta / 0.2, 0.0)
        _update_chip_visual()
    if _phase == Phase.CONFIRMING and _lock <= 0.0:
        play_exit()

func _update_chip_visual() -> void:
    if _chip_rect == null:
        return
    var show_now: bool = _token_mode == TokenMode.PLACING or _token_mode == TokenMode.LANDED
    _chip_rect.visible = show_now and _chip_alpha > 0.01
    if not _chip_rect.visible:
        return
    _chip_rect.position = _chip_pos - Vector2(CHIP_PX, CHIP_PX) * 0.5
    _chip_rect.modulate.a = _chip_alpha
    var squash := 1.0 - _settle
    _chip_rect.scale = Vector2(1.0 + 0.28 * squash, 1.0 - 0.28 * squash)

func _unhandled_key_input(event: InputEvent) -> void:
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
