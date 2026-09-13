extends Control
# NRCU Title / Start screen — frontend brief §3 route: BOOT -> TITLE -> MAIN MENU.
#
# A title card, not a menu: the room background keeps the frame, there is no
# panel, one hero wordmark and one quiet prompt. Everything interactive lives
# in scenes/home.tscn; this scene's only job is to hand the player over.
#
# Esc is deliberately not special here: it counts as "any key" and simply
# advances to the menu. This page owns no quit page (home.gd does), and
# get_tree().auto_accept_quit is left untouched so the boot path still quits.
const Style = preload("res://scripts/demo_style.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

const MENU_SCENE := "res://scenes/home.tscn"
# Melee-style input hygiene (Doc 01 §3.1): a short lock so the key that closed
# the previous screen — or a held Enter — cannot skip the title instantly.
const INPUT_LOCK := 0.35
const HERO_SIZE := 128
const PROMPT_SIZE := 16
const WORDMARK := "NRCU"

var _lock := 0.0
var _ambient := 0.0
var _leaving := false
var _bg: TextureRect
var _accent: Panel
var _prompt_rule: Panel
var _prompt: Label

func _ready() -> void:
    get_window().title = "NRCU — Friend Demo"
    theme = Style.make()
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    # Nothing on the card is clickable, and the card must not eat the click
    # that starts the game: every control ignores the mouse so a key press,
    # a mouse click and a pad button all reach _unhandled_input alike.
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _build_background()
    _build_card()
    _lock = INPUT_LOCK
    # Cursor: the global hand is re-anchored at the current pointer position
    # (read-only, never warped) and any hover inherited from the previous
    # screen is dropped.
    var cursor := get_node_or_null("/root/Cursor")
    if cursor != null and cursor.hand != null:
        cursor.hand.reset_for_screen()

func _process(delta: float) -> void:
    if _lock > 0.0:
        _lock = maxf(_lock - delta, 0.0)
    _ambient += delta
    # Ambient motion, independent of any interaction: the room breathes and
    # the accent rule / prompt keep their own slow clocks. The background scale
    # never drops below 1.0, so the cover-crop can never show an edge.
    if _bg != null and _bg.size.x > 0.0:
        _bg.pivot_offset = _bg.size * 0.5
        var breath := 1.0 + 0.012 * (0.5 + 0.5 * sin(TAU * _ambient / 11.0))
        _bg.scale = Vector2(breath, breath)
    if _accent != null:
        _accent.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(TAU * _ambient / 5.5))
    if _prompt != null:
        _prompt.modulate.a = 0.68 + 0.14 * (0.5 + 0.5 * sin(TAU * _ambient / 2.8))

func _build_background() -> void:
    # The shelf room stays visible — no menu board, no scrim over the art.
    _bg = TextureRect.new()
    _bg.name = "ShelfBackground"
    _bg.texture = load("res://assets/menu/shelf_background.png")
    _bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    _bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_bg)

func _label(text: String, size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    return label

func _build_card() -> void:
    var margin := Tokens.MARGIN
    # Hero wordmark: the one loud element in the frame (spec §11 title card).
    var wordmark := _label(WORDMARK, HERO_SIZE, Tokens.CREAM)
    wordmark.name = "Wordmark"
    wordmark.position = Vector2(margin, 180.0)
    add_child(wordmark)

    # Thin accent rule under the wordmark, sized to the letterforms and placed
    # from the real font baseline (no guessed metrics). One accent, one pulse.
    var font := theme.default_font
    var text_size := font.get_string_size(WORDMARK, HORIZONTAL_ALIGNMENT_LEFT, -1, HERO_SIZE)
    var baseline: float = wordmark.position.y + font.get_ascent(HERO_SIZE)
    _accent = Tokens.band(Tokens.ACCENT, 4.0)
    _accent.name = "AccentRule"
    _accent.position = Vector2(margin, baseline + Tokens.S16)
    _accent.size = Vector2(text_size.x, 4.0)
    add_child(_accent)

    # Restrained identity line, then a hairline rule closing the card block.
    var subtitle := _label("PLATFORM FIGHTER — FRIEND DEMO", Tokens.T_META, Tokens.CREAM_DIM)
    subtitle.name = "Subtitle"
    subtitle.position = Vector2(margin + Tokens.S4, _accent.position.y + Tokens.S24)
    add_child(subtitle)

    var hairline := Tokens.band(Tokens.RULE, 1.0)
    hairline.name = "HairlineRule"
    hairline.position = Vector2(margin, 604.0)
    hairline.size = Vector2(Tokens.DESIGN.x - margin - Tokens.MARGIN_RIGHT, 1.0)
    add_child(hairline)

    # Prompt block: clean space of its own in the lower third of the panel
    # wall, left-aligned with the wordmark column and anchored by one dim
    # accent rule. The position is measured against the shelf art — y 468-500
    # is the quiet band of that column (no book spines, no shelf lip), so the
    # prompt needs no backing plate.
    _prompt = _label("CLICK OR PRESS ANY KEY", PROMPT_SIZE, Tokens.CREAM)
    _prompt.name = "Prompt"
    _prompt.position = Vector2(margin, 470.0)
    add_child(_prompt)

    var prompt_size := font.get_string_size(_prompt.text, HORIZONTAL_ALIGNMENT_LEFT, -1, PROMPT_SIZE)
    _prompt_rule = Tokens.band(Tokens.ACCENT, 3.0)
    _prompt_rule.name = "PromptRule"
    _prompt_rule.position = Vector2(margin, 500.0)
    _prompt_rule.size = Vector2(prompt_size.x, 3.0)
    _prompt_rule.modulate.a = 0.55
    add_child(_prompt_rule)

    # Build tag: quiet corner of the floor, out of the shelf detail.
    var build := _label("BUILD 0.1 — SHELF", Tokens.T_MICRO, Tokens.CREAM_DIM)
    build.name = "BuildLine"
    build.position = Vector2(Tokens.DESIGN.x - Tokens.MARGIN_RIGHT - 240.0, 688.0)
    build.size = Vector2(240.0, 20.0)
    build.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    add_child(build)

func _unhandled_input(event: InputEvent) -> void:
    if _lock > 0.0 or _leaving:
        return
    if _starts_game(event):
        get_viewport().set_input_as_handled()
        begin()

func _starts_game(event: InputEvent) -> bool:
    if event is InputEventKey:
        return event.pressed and not event.echo
    if event is InputEventMouseButton:
        return event.pressed
    if event is InputEventJoypadButton:
        return event.pressed
    return false

func begin() -> void:
    # The single transition path: key press, mouse click, pad button and the
    # headless test all end up here.
    if _leaving:
        return
    _leaving = true
    var tween := create_tween().set_parallel()
    tween.tween_property(self, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    tween.chain().tween_callback(_enter_menu)

func _enter_menu() -> void:
    get_tree().change_scene_to_file(MENU_SCENE)
