extends Control
# Character Select (CSS) - the player-facing VS screen.
#
# Composition (visual spec §13), four regions at the 1280x720 design canvas:
#
#   ┌─────────────────────────────────────────────────────────────┐
#   │ CHARACter SELECT              MODE/RULES      BACK / READY  │  header
#   ├────────────────────────────────┬────────────────────────────┤
#   │ COMPACT ROSTER GRID            │ SELECTED FIGHTER HERO      │  body
#   │ stable scalable cells          │ live 3D model + name       │
#   ├────────────────────────────────┴────────────────────────────┤
#   │ P1 BAY │ P2 BAY │ P3 BAY │ P4 BAY                          │  bays
#   └─────────────────────────────────────────────────────────────┘
#
# The screen edits a persistent MatchSelectionState: assigning a fighter goes
# to the ACTIVE bay (click a bay to activate it), READY hands over to the
# stage page, BACK returns to the main menu. The chip is set down on the
# assigned card - the same token flow as the story selection.
#
# Mouse intent (brief §5): the hand never warps; a stationary pointer drives
# no hover (screens gate `mouse_entered` behind the cursor's modality).

signal ready_requested
signal back_requested
signal exit_finished

const Tokens = preload("res://scripts/ui_tokens.gd")
const HeroRig = preload("res://scripts/hero_rig.gd")

const FPS := 60.0

# --- roster field (left) -------------------------------------------------
const COLS := 5
const CELL_W := 100.0
const CELL_H := 84.0
const CELL_GAP := Tokens.SELECTION_GUTTER      # reserved gutter: the selection
const FIELD_X := 64.0                          # plate can never touch a neighbour
const FIELD_W := 576.0
const FIELD_TOP := 132.0
const FIELD_BOTTOM := 540.0
const ENTRY_STAGGER_TICKS := 3.0
const ENTRY_STAGGER_MAX := 14

# --- hero region (right) -------------------------------------------------
const HERO_RECT := Rect2(664.0, 132.0, 552.0, 336.0)
const NAME_Y := 480.0
const NAME_H := 60.0

# --- player bays (bottom) ------------------------------------------------
const BAY_W := 276.0
const BAY_H := 138.0
const BAY_Y := 552.0
const BAY_GAP := 16.0

# --- header --------------------------------------------------------------
const HEADER_TITLE_Y := 28.0
const MODE_Y := 88.0

const SELECTION_GROW := 5.0     # must stay below CELL_GAP/2
const ENTER_LOCK := 0.5
const NAME_IN := 9.0 / FPS
const NAME_OUT := 11.0 / FPS
const PULSE_TICKS := 10.0
const PLACE_SECONDS := 0.14
const PLACE_NUDGE := 10.0
const CHIP_INSET := 14.1
const CHIP_PX := 20.3
const HERO_DEBOUNCE := 0.09

const KINDS := ["human", "bot", "empty"]
const KIND_LABELS := {"human": "HMN", "bot": "CPU", "empty": "EMPTY"}
const DIFFICULTIES := ["easy", "normal", "hard"]
const DIFF_LABELS := {"easy": "EASY", "normal": "NORMAL", "hard": "HARD"}
const PLAYER_COLORS := Tokens.PLAYER_COLORS

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
var _hero: SubViewportContainer
var _hero_caption: Label
var _phase: Phase = Phase.IDLE
var _token_mode: TokenMode = TokenMode.NONE
var _lock := 0.0
var _hovered := -1
var _active := 0
var _focus_card := -1
var _pulse := 0.0
var _ready_pulse := 0.0
var _chip_index := -1
var _chip_pos := Vector2.ZERO
var _place_from := Vector2.ZERO
var _place_to := Vector2.ZERO
var _place_t := 0.0
var _settle := 1.0
var _chip_alpha := 1.0
var _chip_rect: TextureRect
var _tex_coin: Texture2D
var _hero_id := ""
var _hero_pending := ""
var _hero_timer := 0.0

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _tex_coin = load("res://assets/ui/coin_p1.png")
    var root = get_node_or_null("/root/Cursor")
    if root != null:
        cursor = root.hand

func build(cards: Array) -> void:
    # Re-entrant: rebuilding with a different roster replaces the old field
    # (used by the scalability tests with synthetic fighter counts).
    if _content != null and is_instance_valid(_content):
        _content.queue_free()
        _content = null
        _cards.clear()
        _card_buttons.clear()
        _panels.clear()
    _cards = cards
    _hero_id = ""
    _content = Control.new()
    _content.name = "CharContent"
    _content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_content)
    _build_header()
    _build_roster()
    _build_hero()
    for p in 4:
        _build_panel(p)
    _wire_focus_graph()
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
        cursor.add_target(_mode_button)
        cursor.add_target(_ready_button)

func _build_header() -> void:
    var title := Tokens.heading("CHARACTER SELECT", Tokens.T_SCREEN)
    title.position = Vector2(Tokens.MARGIN, HEADER_TITLE_Y)
    _content.add_child(title)
    var subtitle := Tokens.meta_label("Pick a fighter for every player - READY goes to the stage page.")
    subtitle.position = Vector2(Tokens.MARGIN + 2.0, HEADER_TITLE_Y + 40.0)
    subtitle.modulate = Color(1, 1, 1, 0.62)
    _content.add_child(subtitle)
    # Mode / rules region: a long quiet band, not a rounded pill.
    _mode_button = Button.new()
    _mode_button.name = "ModeToggle"
    _mode_button.size = Vector2(320.0, 38.0)
    _mode_button.position = Vector2(Tokens.MARGIN, MODE_Y)
    _mode_button.add_theme_font_size_override("font_size", Tokens.T_META)
    Tokens.apply_styles(_mode_button, {
        "normal": Tokens.flat(Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE),
        "hover": Tokens.flat(Tokens.SURFACE_2, Tokens.RULE_WARM, Tokens.STROKE),
        "pressed": Tokens.flat(Tokens.SURFACE_2, Tokens.ACCENT, Tokens.STROKE_STRONG),
        "focus": Tokens.flat(Tokens.SURFACE_2, Tokens.ACCENT, Tokens.STROKE_STRONG),
    })
    _mode_button.pressed.connect(_on_mode_pressed)
    _content.add_child(_mode_button)
    _back = Button.new()
    _back.name = "CharBack"
    _back.text = "BACK"
    _back.size = Vector2(170.0, 46.0)
    _back.position = Vector2(Tokens.DESIGN.x - Tokens.MARGIN_RIGHT - 170.0, HEADER_TITLE_Y + 2.0)
    _back.add_theme_font_size_override("font_size", Tokens.T_ACTION)
    Tokens.apply_styles(_back, Tokens.row_styles())
    _back.pressed.connect(func() -> void: back_requested.emit())
    _content.add_child(_back)
    # READY is a state of the screen, not a form submit: a status ribbon that
    # states the requirement, lights up and pulses once the setup is valid.
    _ready_button = Button.new()
    _ready_button.name = "ReadyButton"
    _ready_button.text = "NEED 2 FIGHTERS"
    _ready_button.size = Vector2(320.0, 38.0)
    _ready_button.position = Vector2(Tokens.DESIGN.x - Tokens.MARGIN_RIGHT - 320.0, MODE_Y)
    _ready_button.add_theme_font_size_override("font_size", Tokens.T_META)
    _ready_button.pressed.connect(_on_ready_pressed)
    _content.add_child(_ready_button)

func _build_roster() -> void:
    # Stable, compact cells: seven fighters occupy a subset of the reserved
    # field; a much larger roster packs tighter without a redesign. Each cell
    # keeps CELL_GAP/2 of free space on every side, so the hover plate can
    # never touch a neighbour.
    var count: int = _cards.size()
    var rows: int = maxi(ceili(float(count) / COLS), 1)
    var cell_h: float = minf(CELL_H, (FIELD_BOTTOM - FIELD_TOP - (rows - 1) * CELL_GAP) / rows)
    var cell_w: float = cell_h * (CELL_W / CELL_H)
    _box = Tokens.selection_plate(_content, Rect2())
    _box.name = "SelectBox"
    for i in count:
        var slot: Dictionary = _cards[i]
        var row: int = i / COLS
        var col: int = i % COLS
        # Left-aligned rows: the grid reads as one systematic field, not
        # individually centered ornaments.
        var row_x: float = FIELD_X + cell_w * 0.5
        var center := Vector2(row_x + col * (cell_w + CELL_GAP), FIELD_TOP + cell_h * 0.5 + row * (cell_h + CELL_GAP))
        slot["anchor"] = center
        var card := Button.new()
        card.name = "FighterCard" + str(i)
        card.size = Vector2(cell_w, cell_h)
        card.custom_minimum_size = card.size
        card.pivot_offset = card.size * 0.5
        card.add_theme_font_size_override("font_size", Tokens.T_META)
        Tokens.apply_styles(card, {
            "normal": Tokens.flat(Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE),
            "hover": Tokens.flat(Tokens.SURFACE_2, Tokens.RULE_WARM, Tokens.STROKE),
            "pressed": Tokens.flat(Tokens.SURFACE_3, Tokens.ACCENT, Tokens.STROKE_STRONG),
            "focus": Tokens.flat(Tokens.SURFACE_2, Tokens.ACCENT, Tokens.STROKE_STRONG),
        })
        card.position = center - card.size * 0.5
        var accent := Panel.new()
        accent.name = "Accent"
        accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
        accent.position = Vector2.ZERO
        accent.size = Vector2(4.0, cell_h)
        accent.add_theme_stylebox_override("panel", Tokens.flat(slot["palette"]))
        card.add_child(accent)
        var name_label := Label.new()
        name_label.text = str(slot["name"])
        name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        name_label.position = Vector2(10.0, 4.0)
        name_label.size = Vector2(cell_w - 16.0, cell_h - 8.0)
        name_label.add_theme_font_size_override("font_size", Tokens.T_META)
        name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card.add_child(name_label)
        card.pressed.connect(_on_card_pressed.bind(i))
        card.mouse_entered.connect(_on_card_hovered.bind(i))
        _content.add_child(card)
        _card_buttons.append(card)
        if cursor != null:
            cursor.add_target(card)

func _build_hero() -> void:
    # Identity region: one live 3D model, its own quiet frame; deliberately
    # lighter than the roster so the two regions never compete.
    var caption := Tokens.heading("SELECTED FIGHTER", Tokens.T_MICRO)
    caption.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    caption.position = Vector2(HERO_RECT.position.x + 2.0, HERO_RECT.position.y - 24.0)
    _content.add_child(caption)
    var hero_frame := Panel.new()
    hero_frame.name = "HeroFrame"
    hero_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hero_frame.position = HERO_RECT.position
    hero_frame.size = HERO_RECT.size
    hero_frame.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_2, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_FRAME))
    _content.add_child(hero_frame)
    _hero = HeroRig.new()
    _hero.name = "HeroRig"
    _hero.position = HERO_RECT.position + Vector2(4.0, 4.0)
    _hero.size = HERO_RECT.size - Vector2(8.0, 8.0)
    _content.add_child(_hero)
    _hero_caption = Tokens.meta_label("")
    _hero_caption.name = "HeroHint"
    _hero_caption.position = HERO_RECT.position + Vector2(10.0, HERO_RECT.size.y - 28.0)
    _hero_caption.add_theme_font_size_override("font_size", Tokens.T_MICRO)
    _hero_caption.modulate = Color(1, 1, 1, 0.55)
    _content.add_child(_hero_caption)
    _name_label = Label.new()
    _name_label.name = "FighterName"
    _name_label.size = Vector2(HERO_RECT.size.x, NAME_H)
    _name_label.position = Vector2(HERO_RECT.position.x, NAME_Y)
    _name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _name_label.add_theme_font_size_override("font_size", Tokens.T_IDENTITY)
    _content.add_child(_name_label)
    var underline := Panel.new()
    underline.name = "NameRule"
    underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
    underline.position = Vector2(HERO_RECT.position.x + 2.0, NAME_Y + NAME_H - 6.0)
    underline.size = Vector2(HERO_RECT.size.x - 4.0, 2.0)
    underline.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE_WARM))
    _content.add_child(underline)

func _wire_focus_graph() -> void:
    # Keyboard/controller parity (QA §3): a complete route without the mouse.
    # Cards form the grid; rows walk with left/right, columns with up/down;
    # the header (BACK/READY/MODE) and the player bays are reachable from it.
    var n := _card_buttons.size()
    if n == 0:
        return
    for i in n:
        var card: Button = _card_buttons[i]
        var col: int = i % COLS
        var row: int = i / COLS
        var left_i: int = i - 1 if col > 0 else -1
        var right_i: int = i + 1 if col < COLS - 1 and i + 1 < n else -1
        var up_i: int = i - COLS if row > 0 else -1
        var down_i: int = i + COLS if i + COLS < n else -1
        if left_i >= 0:
            card.focus_neighbor_left = card.get_path_to(_card_buttons[left_i])
        if right_i >= 0:
            card.focus_neighbor_right = card.get_path_to(_card_buttons[right_i])
        card.focus_neighbor_top = card.get_path_to(_back)
        if up_i >= 0:
            card.focus_neighbor_top = card.get_path_to(_card_buttons[up_i])
        if down_i >= 0:
            card.focus_neighbor_bottom = card.get_path_to(_card_buttons[down_i])
        else:
            card.focus_neighbor_bottom = card.get_path_to(_panels[int(col) % 4]["box"])
    for index in _panels.size():
        var bay: Button = _panels[index]["box"]
        bay.focus_neighbor_left = bay.get_path_to(_panels[(index - 1 + 4) % 4]["box"])
        bay.focus_neighbor_right = bay.get_path_to(_panels[(index + 1) % 4]["box"])
        bay.focus_neighbor_top = bay.get_path_to(_card_buttons[mini(index, n - 1)])
    _back.focus_neighbor_right = _back.get_path_to(_ready_button)
    _back.focus_neighbor_bottom = _back.get_path_to(_card_buttons[n - 1])
    _ready_button.focus_neighbor_left = _ready_button.get_path_to(_back)
    _ready_button.focus_neighbor_bottom = _ready_button.get_path_to(_panels[3]["box"])
    _mode_button.focus_neighbor_right = _mode_button.get_path_to(_ready_button)
    _mode_button.focus_neighbor_bottom = _mode_button.get_path_to(_card_buttons[0])

func _build_panel(index: int) -> void:
    # Player stations, not info cards: player color is structural (left bar,
    # header strip, tinted tag), the whole bay is one clickable surface.
    var pc: Color = PLAYER_COLORS[index]
    var x: float = Tokens.MARGIN + index * (BAY_W + BAY_GAP)
    var box := Button.new()
    box.name = "PanelBox" + str(index)
    box.size = Vector2(BAY_W, BAY_H)
    box.position = Vector2(x, BAY_Y)
    Tokens.apply_styles(box, {
        "normal": _bay_style(pc, false),
        "hover": _bay_style(pc, true),
        "pressed": _bay_style(pc, true),
        "focus": _bay_style(pc, true),
    })
    box.pressed.connect(_on_panel_pressed.bind(index))
    _content.add_child(box)
    var strip := Panel.new()
    strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    strip.position = Vector2(0.0, 0.0)
    strip.size = Vector2(BAY_W, 30.0)
    strip.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_2))
    box.add_child(strip)
    var tag := Label.new()
    tag.text = "P%d" % (index + 1)
    tag.position = Vector2(12.0, 1.0)
    tag.size = Vector2(60.0, 28.0)
    tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    tag.add_theme_font_size_override("font_size", Tokens.T_NAV)
    tag.add_theme_color_override("font_color", pc)
    tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(tag)
    var kind := Button.new()
    kind.name = "PanelKind" + str(index)
    kind.position = Vector2(BAY_W - 94.0, 2.0)
    kind.size = Vector2(84.0, 26.0)
    kind.add_theme_font_size_override("font_size", Tokens.T_MICRO)
    Tokens.apply_styles(kind, Tokens.row_styles())
    kind.pressed.connect(_on_kind_pressed.bind(index))
    box.add_child(kind)
    var fighter := Label.new()
    fighter.name = "PanelFighter" + str(index)
    fighter.position = Vector2(12.0, 46.0)
    fighter.size = Vector2(BAY_W - 24.0, 34.0)
    fighter.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    fighter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    fighter.add_theme_font_size_override("font_size", Tokens.T_ACTION)
    fighter.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(fighter)
    var diff := Button.new()
    diff.name = "PanelDiff" + str(index)
    diff.position = Vector2(12.0, 96.0)
    diff.size = Vector2(120.0, 32.0)
    diff.add_theme_font_size_override("font_size", Tokens.T_MICRO)
    Tokens.apply_styles(diff, Tokens.row_styles())
    diff.pressed.connect(_on_diff_pressed.bind(index))
    box.add_child(diff)
    var team := Button.new()
    team.name = "PanelTeam" + str(index)
    team.position = Vector2(BAY_W - 132.0, 96.0)
    team.size = Vector2(120.0, 32.0)
    team.add_theme_font_size_override("font_size", Tokens.T_MICRO)
    Tokens.apply_styles(team, Tokens.row_styles())
    team.pressed.connect(_on_team_pressed.bind(index))
    box.add_child(team)
    _panels.append({"box": box, "kind": kind, "fighter": fighter, "diff": diff, "team": team, "strip": strip})
    if cursor != null:
        cursor.add_target(box)
        cursor.add_target(kind)
        cursor.add_target(diff)
        cursor.add_target(team)

func _bay_style(pc: Color, hot: bool) -> StyleBoxFlat:
    var s := Tokens.flat(Tokens.SURFACE_2 if hot else Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_PLATE)
    s.border_width_left = 6
    s.border_color = pc
    return s

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
        cursor.reset_for_screen()
        cursor.set_carry()
        cursor.press_frame_enabled = false
    _token_mode = TokenMode.CARRY
    _refresh()
    _refresh_hero(true)
    _focus_card = _card_index_of(str(state.slots[0].get("character", "")))
    for i in _card_buttons.size():
        var card: Button = _card_buttons[i]
        card.modulate.a = 0.0
        card.scale = Vector2.ONE
        var target: Vector2 = _cards[i]["anchor"] - card.size * 0.5
        card.position = target + Vector2(0.0, 18.0)
        var delay: float = mini(i, ENTRY_STAGGER_MAX) * ENTRY_STAGGER_TICKS / FPS
        var tween := create_tween()
        tween.tween_property(card, "position", target, 0.22).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        tween.parallel().tween_property(card, "modulate:a", 1.0, 0.22).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
        cursor.reset_for_screen()
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
    _seed_focus()

func _seed_focus() -> void:
    # Keyboard/controller start: with no focused control the direction keys
    # do nothing. Only seed when the mouse is not the active modality, so a
    # mouse user never sees a focus ring appear on its own.
    if cursor != null:
        if cursor.is_mouse_active():
            return
    if _card_buttons.is_empty():
        return
    var idx: int = _hovered if _hovered >= 0 else 0
    _card_buttons[idx].grab_focus()

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
    _box.position = rect.position - Vector2(SELECTION_GROW, SELECTION_GROW)
    _box.size = rect.size + Vector2(SELECTION_GROW, SELECTION_GROW) * 2.0
    _box.show()
    _swap_name(str(_cards[index]["name"]))
    _queue_hero(str(_cards[index].get("id", "")))

func _on_card_hovered(index: int) -> void:
    # A stationary pointer must not take over the screen: only genuine mouse
    # input counts (the cursor layer tracks the active modality).
    if cursor != null and not cursor.is_mouse_active():
        return
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
    _queue_hero(str(_cards[index].get("id", "")))

func _on_panel_pressed(index: int) -> void:
    if _phase == Phase.EXITING:
        return
    _active = index
    _refresh()
    _refresh_hero(true)

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
        var pc: Color = PLAYER_COLORS[i]
        var style := _bay_style(pc, active)
        style.bg_color = Tokens.SURFACE_3 if active else Tokens.SURFACE_1
        panel["box"].add_theme_stylebox_override("normal", style)
        # Active bay: the header strip darkens toward the player color while
        # the P-tag keeps the saturated color readable on top of it.
        panel["strip"].add_theme_stylebox_override("panel", Tokens.flat(pc.darkened(0.52) if active else Tokens.SURFACE_2))
        panel["kind"].text = str(KIND_LABELS.get(kind, "?"))
        var is_empty: bool = kind == "empty"
        panel["fighter"].text = "-" if is_empty else _display_for(str(slot.get("character", "")))
        panel["diff"].visible = kind == "bot"
        panel["diff"].text = str(DIFF_LABELS.get(str(slot.get("difficulty", "normal")), "?"))
        panel["team"].visible = _state.mode == 1 and not is_empty
        panel["team"].text = "TEAM %s" % ("A" if int(slot.get("team", 0)) == 0 else "B")
    _mode_button.text = "MODE: FREE-FOR-ALL" if _state.mode == 0 else "MODE: TEAMS"
    _ready_button.disabled = not ready_allowed()
    if ready_allowed():
        _ready_button.text = "READY"
        _ready_button.add_theme_stylebox_override("normal", Tokens.flat(Tokens.SURFACE_3, Tokens.ACCENT, Tokens.STROKE_STRONG))
    else:
        _ready_button.text = "NEED 3 FIGHTERS + BOTH TEAMS" if _state.mode == 1 else "NEED 2 FIGHTERS"
        _ready_button.add_theme_stylebox_override("normal", Tokens.flat(Tokens.SURFACE_1, Tokens.RULE_WARM, Tokens.STROKE))
    _ready_button.add_theme_stylebox_override("disabled", Tokens.flat(Tokens.SURFACE_1, Tokens.RULE_WARM, Tokens.STROKE))
    _ready_button.add_theme_stylebox_override("hover", Tokens.flat(Tokens.SURFACE_HI, Tokens.ACCENT, Tokens.STROKE_STRONG))
    _ready_button.add_theme_stylebox_override("pressed", Tokens.flat(Tokens.SURFACE_HI, Tokens.ACCENT, Tokens.STROKE_SELECT))
    _ready_button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))

func _display_for(id: String) -> String:
    return load("res://scripts/roster.gd").display_name(id).to_upper()

func _card_index_of(id: String) -> int:
    for i in _cards.size():
        if str(_cards[i]["id"]) == id:
            return i
    return -1

# --- hero -----------------------------------------------------------------
func _queue_hero(id: String) -> void:
    if id == "" or id == _hero_id:
        return
    _hero_pending = id
    _hero_timer = HERO_DEBOUNCE

func _refresh_hero(immediate := false) -> void:
    if _hero == null:
        return
    var id := _hero_pending
    if immediate:
        _hero_timer = 0.0
        _hero_pending = ""
        if _state != null:
            id = str(_state.slots[_active].get("character", ""))
        if id == "":
            return
    elif _hero_timer > 0.0:
        return
    _hero_pending = ""
    if id == "" or id == _hero_id:
        return
    _hero_id = id
    _hero.set_fighter(id)
    if _hero_caption != null:
        _hero_caption.text = _display_for(id)

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
    outgoing.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    outgoing.add_theme_font_size_override("font_size", Tokens.T_IDENTITY)
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
    if _hero_timer > 0.0:
        _hero_timer = maxf(_hero_timer - delta, 0.0)
        if _hero_timer <= 0.0:
            _refresh_hero()
    # Ambient: the ready state breathes on its own clock (independent of any
    # selection response).
    if _state != null and ready_allowed() and _phase != Phase.EXITING:
        _ready_pulse += delta
        _ready_button.modulate = Color(1, 1, 1, 0.85 + 0.15 * (0.5 + 0.5 * sin(TAU * _ready_pulse / 1.1)))
    else:
        _ready_button.modulate = Color(1, 1, 1, 1)
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
