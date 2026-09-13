extends Control
# Character Select (CSS) - the player-facing VS screen.
#
# Layout: the mode control (FFA / Teams) and READY in the top row, the
# fighter grid in the middle (two staggered rows), the big name display and
# four player panels (HMN/CPU/EMPTY, fighter, CPU difficulty, team).
# The screen edits a persistent MatchSelectionState: assigning a fighter goes
# to the ACTIVE panel (click a panel to activate it), READY hands over to the
# stage page, BACK returns to the main menu. The chip is set down on the
# assigned card - the same token flow as the story selection.

signal ready_requested
signal back_requested
signal exit_finished

const FPS := 60.0
const CARD_SIZE := Vector2(232.0, 128.0)
const GAP := 14.0
const ROW1_Y := 250.0
const ROW2_Y := 394.0
const NAME_Y := 478.0
const PANEL_SIZE := Vector2(280.0, 130.0)
const PANEL_Y := 530.0
const ENTER_LOCK := 0.5
const NAME_IN := 9.0 / FPS
const NAME_OUT := 11.0 / FPS
const PULSE_TICKS := 10.0
const PLACE_SECONDS := 0.14
const PLACE_NUDGE := 10.0
const CHIP_INSET := 14.1
const CHIP_PX := 20.3
const KINDS := ["human", "bot", "empty"]
const KIND_LABELS := {"human": "HMN", "bot": "CPU", "empty": "EMPTY"}
const DIFFICULTIES := ["easy", "normal", "hard"]
const DIFF_LABELS := {"easy": "EASY", "normal": "NORMAL", "hard": "HARD"}

enum Phase { ENTERING, IDLE, EXITING }
enum TokenMode { NONE, CARRY, PLACING, LANDED }

var cursor: Control

var _state
var _cards: Array = []
var _card_buttons: Array = []
var _panels: Array = []
var _content: Control
var _box: Panel
var _name_label: Label
var _mode_button: Button
var _ready_button: Button
var _back: Button
var _phase: Phase = Phase.IDLE
var _token_mode: TokenMode = TokenMode.NONE
var _lock := 0.0
var _hovered := -1
var _active := 0
var _focus_card := -1
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

func build(cards: Array) -> void:
    _cards = cards
    _content = Control.new()
    _content.name = "CharContent"
    _content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_content)
    var view: Vector2 = get_viewport_rect().size
    var title := Label.new()
    title.text = "CHARACTER SELECT"
    title.position = Vector2(64.0, 44.0)
    title.add_theme_font_size_override("font_size", 30)
    _content.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "Pick a fighter for every player - READY goes to the stage page."
    subtitle.position = Vector2(66.0, 84.0)
    subtitle.add_theme_font_size_override("font_size", 16)
    subtitle.modulate = Color(1, 1, 1, 0.72)
    _content.add_child(subtitle)
    _back = Button.new()
    _back.name = "CharBack"
    _back.text = "BACK"
    _back.size = Vector2(170.0, 50.0)
    _back.position = Vector2(maxf(view.x, 1280.0) - 234.0, 44.0)
    _back.pressed.connect(func() -> void: back_requested.emit())
    _content.add_child(_back)
    _mode_button = Button.new()
    _mode_button.name = "ModeToggle"
    _mode_button.size = Vector2(330.0, 46.0)
    _mode_button.position = Vector2(64.0, 126.0)
    _mode_button.pressed.connect(_on_mode_pressed)
    _content.add_child(_mode_button)
    _ready_button = Button.new()
    _ready_button.name = "ReadyButton"
    _ready_button.text = "READY  >"
    _ready_button.size = Vector2(216.0, 46.0)
    _ready_button.position = Vector2(maxf(view.x, 1280.0) - 280.0, 126.0)
    _ready_button.pressed.connect(_on_ready_pressed)
    _content.add_child(_ready_button)
    _box = Panel.new()
    _box.name = "SelectBox"
    _box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _box.add_theme_stylebox_override("panel", _flat(Color(0, 0, 0, 0), Color("e5ad69"), 3, 12))
    _box.hide()
    _content.add_child(_box)
    var count: int = _cards.size()
    var row1 := mini(count, 4)
    var row2: int = maxi(count - 4, 0)
    var row1_total: float = row1 * CARD_SIZE.x + maxf(row1 - 1, 0) * GAP
    var row2_total: float = row2 * CARD_SIZE.x + maxf(row2 - 1, 0) * GAP
    var row1_x: float = (view.x - row1_total) * 0.5 + CARD_SIZE.x * 0.5
    var row2_x: float = (view.x - row2_total) * 0.5 + CARD_SIZE.x * 0.5
    for i in count:
        var slot: Dictionary = _cards[i]
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
        card.add_theme_stylebox_override("normal", _flat(Color("284e50"), Color("1b3436"), 2, 10))
        card.add_theme_stylebox_override("hover", _flat(Color("3d6362"), Color("e5ad69"), 2, 10))
        card.add_theme_stylebox_override("pressed", _flat(Color("2f4f4e"), Color("e5ad69"), 3, 10))
        card.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10))
        card.position = center - CARD_SIZE * 0.5
        var accent := Panel.new()
        accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
        accent.position = Vector2(10.0, 8.0)
        accent.size = Vector2(CARD_SIZE.x - 20.0, 12.0)
        accent.add_theme_stylebox_override("panel", _flat(slot["palette"], Color(0, 0, 0, 0), 0, 6))
        card.add_child(accent)
        var name_label := Label.new()
        name_label.text = str(slot["name"])
        name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        name_label.position = Vector2(8.0, 28.0)
        name_label.size = Vector2(CARD_SIZE.x - 16.0, CARD_SIZE.y - 54.0)
        name_label.add_theme_font_size_override("font_size", 20)
        name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card.add_child(name_label)
        card.pressed.connect(_on_card_pressed.bind(i))
        card.mouse_entered.connect(_on_card_hovered.bind(i))
        _content.add_child(card)
        _card_buttons.append(card)
        if cursor != null:
            cursor.add_target(card)
    for p in 4:
        _build_panel(p)
    _name_label = Label.new()
    _name_label.name = "FighterName"
    _name_label.size = Vector2(view.x, 40.0)
    _name_label.position = Vector2(0.0, NAME_Y)
    _name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _name_label.add_theme_font_size_override("font_size", 26)
    _content.add_child(_name_label)
    # The token must draw ABOVE the cards: a parent's own _draw sits below its
    # children in Godot, so the chip lives as the last child instead.
    _chip_rect = TextureRect.new()
    _chip_rect.name = "TokenChip"
    _chip_rect.texture = _tex_coin
    _chip_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _chip_rect.size = Vector2(CHIP_PX, CHIP_PX)
    _chip_rect.pivot_offset = Vector2(CHIP_PX, CHIP_PX) * 0.5
    _chip_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _chip_rect.hide()
    _content.add_child(_chip_rect)
    if cursor != null:
        cursor.add_target(_back)

func _build_panel(index: int) -> void:
    var box := Button.new()
    box.name = "PanelBox" + str(index)
    box.size = PANEL_SIZE
    box.position = Vector2(50.0 + index * 300.0, PANEL_Y)
    box.add_theme_stylebox_override("normal", _flat(Color("284e50"), Color("1b3436"), 2, 12))
    box.add_theme_stylebox_override("hover", _flat(Color("2f4f4e"), Color("8a5a2b"), 2, 12))
    box.add_theme_stylebox_override("pressed", _flat(Color("2f4f4e"), Color("e5ad69"), 2, 12))
    box.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12))
    box.pressed.connect(_on_panel_pressed.bind(index))
    _content.add_child(box)
    var tag := Label.new()
    tag.text = "P%d" % (index + 1)
    tag.position = Vector2(10.0, 6.0)
    tag.add_theme_font_size_override("font_size", 22)
    tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(tag)
    var kind := Button.new()
    kind.name = "PanelKind" + str(index)
    kind.position = Vector2(186.0, 6.0)
    kind.size = Vector2(84.0, 34.0)
    kind.add_theme_font_size_override("font_size", 13)
    kind.pressed.connect(_on_kind_pressed.bind(index))
    box.add_child(kind)
    var fighter := Label.new()
    fighter.name = "PanelFighter" + str(index)
    fighter.position = Vector2(10.0, 46.0)
    fighter.size = Vector2(260.0, 28.0)
    fighter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    fighter.add_theme_font_size_override("font_size", 18)
    fighter.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(fighter)
    var diff := Button.new()
    diff.name = "PanelDiff" + str(index)
    diff.position = Vector2(10.0, 86.0)
    diff.size = Vector2(124.0, 36.0)
    diff.add_theme_font_size_override("font_size", 12)
    diff.pressed.connect(_on_diff_pressed.bind(index))
    box.add_child(diff)
    var team := Button.new()
    team.name = "PanelTeam" + str(index)
    team.position = Vector2(146.0, 86.0)
    team.size = Vector2(124.0, 36.0)
    team.add_theme_font_size_override("font_size", 12)
    team.pressed.connect(_on_team_pressed.bind(index))
    box.add_child(team)
    _panels.append({"box": box, "kind": kind, "fighter": fighter, "diff": diff, "team": team})
    if cursor != null:
        cursor.add_target(box)
        cursor.add_target(kind)
        cursor.add_target(diff)
        cursor.add_target(team)

func open_with(state) -> void:
    _state = state
    _active = 0
    _phase = Phase.ENTERING
    _lock = ENTER_LOCK
    _hovered = -1
    _pulse = 0.0
    _box.hide()
    _chip_index = -1
    _settle = 1.0
    _chip_alpha = 1.0
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
    _refresh()
    _focus_card = _card_index_of(str(state.slots[0].get("character", "")))
    for i in _card_buttons.size():
        var card: Button = _card_buttons[i]
        card.modulate.a = 0.0
        card.scale = Vector2.ONE
        var target: Vector2 = _cards[i]["anchor"] - CARD_SIZE * 0.5
        card.position = target + Vector2(0.0, 18.0)
        var tween := create_tween()
        tween.tween_property(card, "position", target, 0.22).set_delay(i * 3.0 / FPS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        tween.parallel().tween_property(card, "modulate:a", 1.0, 0.22).set_delay(i * 3.0 / FPS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        if i == _card_buttons.size() - 1:
            tween.finished.connect(_on_entry_done)

func reopen() -> void:
    # Coming back from the stage page: keep every selection and the chip.
    _content.modulate.a = 1.0
    _phase = Phase.IDLE
    _lock = 0.35
    _box.hide()
    _hovered = -1
    Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
    if cursor != null:
        cursor.visible = true
    _refresh()
    if _state != null:
        hover_slot(_card_index_of(str(_state.slots[_active].get("character", ""))))

func _on_entry_done() -> void:
    if _phase != Phase.ENTERING:
        return
    _phase = Phase.IDLE
    if _focus_card >= 0:
        hover_slot(_focus_card)
        _focus_card = -1

func hover_slot(index: int) -> void:
    if _phase == Phase.EXITING:
        return
    if index < 0 or index >= _card_buttons.size():
        return
    if index == _hovered:
        return
    _hovered = index
    var card: Button = _card_buttons[index]
    var rect := card.get_rect()
    _box.position = rect.position - Vector2(12.0, 12.0)
    _box.size = rect.size + Vector2(24.0, 24.0)
    _box.show()
    _swap_name(str(_cards[index]["name"]))

func _on_card_hovered(index: int) -> void:
    hover_slot(index)

func _on_card_pressed(index: int) -> void:
    if _phase != Phase.IDLE or _lock > 0.0 or _state == null:
        return
    var slot: Dictionary = _state.slots[_active]
    slot["character"] = str(_cards[index]["id"])
    if str(slot.get("kind", "empty")) == "empty":
        slot["kind"] = "human"
    _assign_chip(index)
    _refresh()

func _on_panel_pressed(index: int) -> void:
    if _phase == Phase.EXITING:
        return
    _active = index
    _refresh()

func _on_kind_pressed(index: int) -> void:
    if _state == null:
        return
    var slot: Dictionary = _state.slots[index]
    var kind := str(slot.get("kind", "human"))
    var at: int = KINDS.find(kind)
    slot["kind"] = KINDS[(at + 1) % KINDS.size()]
    _refresh()

func _on_diff_pressed(index: int) -> void:
    if _state == null:
        return
    var slot: Dictionary = _state.slots[index]
    var diff := str(slot.get("difficulty", "normal"))
    var at: int = DIFFICULTIES.find(diff)
    slot["difficulty"] = DIFFICULTIES[(at + 1) % DIFFICULTIES.size()]
    _refresh()

func _on_team_pressed(index: int) -> void:
    if _state == null:
        return
    var slot: Dictionary = _state.slots[index]
    slot["team"] = 1 - int(slot.get("team", 0))
    _refresh()

func _on_mode_pressed() -> void:
    if _state == null:
        return
    _state.mode = 1 - _state.mode
    _refresh()

func _on_ready_pressed() -> void:
    if ready_allowed():
        ready_requested.emit()

func ready_allowed() -> bool:
    return _state != null and _state.can_ready()

func _refresh() -> void:
    if _state == null:
        return
    for i in _panels.size():
        var panel: Dictionary = _panels[i]
        var slot: Dictionary = _state.slots[i]
        var kind := str(slot.get("kind", "human"))
        var active: bool = i == _active
        var fill := Color("35595a") if active else Color("284e50")
        var border := Color("e5ad69") if active else Color("1b3436")
        panel["box"].add_theme_stylebox_override("normal", _flat(fill, border, 3 if active else 2, 12))
        panel["kind"].text = str(KIND_LABELS.get(kind, "?"))
        var is_empty: bool = kind == "empty"
        panel["fighter"].text = "-" if is_empty else _display_for(str(slot.get("character", "")))
        panel["diff"].visible = kind == "bot"
        panel["diff"].text = str(DIFF_LABELS.get(str(slot.get("difficulty", "normal")), "?"))
        panel["team"].visible = _state.mode == 1 and not is_empty
        panel["team"].text = "TEAM %s" % ("A" if int(slot.get("team", 0)) == 0 else "B")
    _mode_button.text = "MODE: FREE-FOR-ALL" if _state.mode == 0 else "MODE: TEAMS"
    _ready_button.disabled = not ready_allowed()

func _display_for(id: String) -> String:
    return load("res://scripts/roster.gd").display_name(id).to_upper()

func _card_index_of(id: String) -> int:
    for i in _cards.size():
        if str(_cards[i]["id"]) == id:
            return i
    return -1

func get_cards() -> Array:
    return _card_buttons

func get_state():
    return _state

func get_active() -> int:
    return _active

func get_ready_button() -> Button:
    return _ready_button

func get_mode_button() -> Button:
    return _mode_button

func get_input_lock() -> float:
    return _lock

func lock_input(seconds: float) -> void:
    _lock = maxf(_lock, seconds)

func is_exiting() -> bool:
    return _phase == Phase.EXITING

func is_chip_landed() -> bool:
    return _token_mode == TokenMode.LANDED

func get_chip_position() -> Vector2:
    return _chip_pos

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
    _token_mode = TokenMode.NONE
    _chip_index = -1
    _chip_alpha = 1.0
    if _box != null:
        _box.hide()
    if _content != null:
        _content.modulate.a = 1.0
    if cursor != null:
        cursor.visible = true
    _update_chip_visual()

func _assign_chip(index: int) -> void:
    # The chip is set down on the assigned card (first assignment) and hops
    # after that - the same Melee-style token flow as the story selection.
    if _token_mode == TokenMode.CARRY:
        var from: Vector2 = cursor.release_carry() if cursor != null and cursor.is_carrying() else _chip_pos
        _begin_place(from, from + Vector2(0.0, PLACE_NUDGE), index)
    elif _token_mode == TokenMode.PLACING:
        _chip_index = index
        _place_to = _place_target(_place_from + Vector2(0.0, PLACE_NUDGE), index)
    elif index != _chip_index:
        var anchor: Vector2 = cursor.chip_world_position() + Vector2(0.0, PLACE_NUDGE) if cursor != null else _chip_pos
        _begin_place(_chip_pos, anchor, index)

func _place_target(from: Vector2, index: int) -> Vector2:
    var rect: Rect2 = _card_buttons[index].get_global_rect()
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
    _update_chip_visual()

func _swap_name(text: String) -> void:
    if _name_label.text == text:
        return
    var outgoing := Label.new()
    outgoing.text = _name_label.text
    outgoing.position = _name_label.position
    outgoing.size = _name_label.size
    outgoing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    outgoing.add_theme_font_size_override("font_size", 26)
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
    if not is_visible_in_tree():
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
            if ready_allowed():
                ready_requested.emit()
                get_viewport().set_input_as_handled()

func _flat(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = border
    style.set_border_width_all(width)
    style.set_corner_radius_all(radius)
    return style
