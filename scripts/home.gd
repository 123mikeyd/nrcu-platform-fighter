extends Control
# Main Menu (visual spec §12). Not a translucent panel with four rounded
# buttons: an authored composition — wordmark + rule on the left, a vertical
# stack of long option bands, and a context region on the right that answers
# the selected option (descriptor + geometric motif). Selection uses three
# coordinated layers (plate appears, material/label change, ONE accent bar),
# never a blinking outline. The composition stands on its own on a neutral
# background; the temporary shelf art is atmosphere, not structure.
#
# The title/start screen is its own scene (scenes/title.tscn): BOOT -> TITLE
# -> this menu.

const Style = preload("res://scripts/demo_style.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const AppStateScript = preload("res://scripts/app_state.gd")

const BAND_X := 64.0
const BAND_W := 470.0
const BAND_H := 62.0
const BAND_GAP := 8.0
const BAND_TOP := 236.0
const BAND_GROW := 12.0
const CONTEXT_RECT := Rect2(620.0, 236.0, 596.0, 286.0)

var buttons: Dictionary = {}
var page: Control
var state := "home"
var _page_lock := 0.0
var _rows: Array = []
var _motif: Control
var _context_title: Label
var _context_body: Label
var _context_label: Label
var _accent_rule: Panel
var _ambient := 0.0
var _selected := 0

func _ready():
    get_window().title = "NRCU — Friend Demo"
    get_window().min_size = Vector2i(800,450)
    theme = Style.make()
    var background := TextureRect.new()
    background.name = "ShelfBackground"
    background.texture = load("res://assets/menu/shelf_background.png")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    get_tree().auto_accept_quit = false
    get_window().close_requested.connect(func(): show_page("quit"))
    show_page("home")
    # Screen entry never warps the pointer and never inherits hover.
    var cursor = get_node_or_null("/root/Cursor")
    if cursor != null and cursor.hand != null:
        cursor.hand.reset_for_screen()

func _process(delta: float) -> void:
    if _page_lock > 0.0:
        _page_lock = maxf(_page_lock - delta, 0.0)
    # Ambient: the accent rule under the wordmark breathes on its own clock,
    # independent of any selection response.
    _ambient += delta
    if _accent_rule != null and is_instance_valid(_accent_rule):
        _accent_rule.modulate = Color(1, 1, 1, 0.78 + 0.22 * (0.5 + 0.5 * sin(TAU * _ambient / 3.6)))

func _nav(action: Callable) -> void:
    # Input hygiene (Doc 01 §3.1): swallow page changes within a short window.
    if _page_lock > 0.0:
        return
    _page_lock = 0.1
    action.call()

func _animate_page() -> void:
    # 20F one-shot page enter (Doc 01 §4.1).
    if page == null:
        return
    page.pivot_offset = Vector2.ZERO
    page.modulate.a = 0.0
    page.scale = Vector2(0.97, 0.95)
    var tween := create_tween().set_parallel()
    tween.tween_property(page, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_property(page, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func show_page(next: String):
    state = next
    buttons.clear()
    _rows.clear()
    _motif = null
    _context_label = null
    _context_title = null
    _context_body = null
    _accent_rule = null
    if is_instance_valid(page):
        remove_child(page)
        page.queue_free()
    page = Control.new()
    page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(page)
    if next == "help":
        var help = Style.help(page, func(): show_page("home"))
        buttons["home"] = help.find_child("HelpBack",true,false)
        _animate_page()
        return
    if next == "home":
        _build_wordmark()
        _build_menu_bands()
        _build_context_region()
    else:
        var title := Label.new()
        title.text = "Leave the room?"
        title.position = Vector2(64, 240)
        title.add_theme_font_size_override("font_size", Tokens.T_SCREEN)
        page.add_child(title)
        _build_quit_rows()
    var values = buttons.values().filter(func(b): return b.visible)
    for i in values.size():
        values[i].focus_neighbor_bottom = values[(i+1)%values.size()].get_path()
        values[i].focus_neighbor_top = values[(i-1+values.size())%values.size()].get_path()
    values[0].grab_focus()
    _on_row_selected(0)
    _animate_page()

func _build_wordmark() -> void:
    var title := Label.new()
    title.text = "NRCU"
    title.position = Vector2(Tokens.MARGIN - 8.0, 48.0)
    title.add_theme_font_size_override("font_size", 104)
    page.add_child(title)
    _accent_rule = Panel.new()
    _accent_rule.name = "TitleRule"
    _accent_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _accent_rule.position = Vector2(Tokens.MARGIN, 176.0)
    _accent_rule.size = Vector2(252.0, 3.0)
    _accent_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
    page.add_child(_accent_rule)
    var caption := Tokens.meta_label("PLATFORM FIGHTER")
    caption.position = Vector2(Tokens.MARGIN + 2.0, 188.0)
    caption.add_theme_font_size_override("font_size", Tokens.T_MICRO)
    caption.modulate = Color(1, 1, 1, 0.6)
    page.add_child(caption)

func _build_menu_bands() -> void:
    var options: Array = [
        {"label": "Play", "id": "play", "numeral": "01", "action": func(): _nav(func(): _enter("vs")), "title": "PLAY", "context": "Pick fighters and a stage, then fight.", "motif": "versus"},
        {"label": "Story Mode", "id": "story", "numeral": "02", "action": func(): _nav(func(): _enter("story")), "title": "STORY MODE", "context": "One encounter: you against Bobo.", "motif": "encounter"},
        {"label": "How to Play", "id": "help", "numeral": "03", "action": func(): _nav(func(): show_page("help")), "title": "HOW TO PLAY", "context": "Moves, rules and controls.", "motif": "guide"},
        {"label": "Quit", "id": "quit", "numeral": "04", "action": func(): _nav(func(): show_page("quit")), "title": "QUIT", "context": "Leave the room.", "motif": "leave"},
    ]
    for i in options.size():
        var option: Dictionary = options[i]
        var row := Button.new()
        row.name = str(option["id"])
        row.text = ""
        row.position = Vector2(BAND_X, BAND_TOP + i * (BAND_H + BAND_GAP))
        row.size = Vector2(BAND_W, BAND_H)
        Tokens.apply_styles(row, {
            "normal": _band_style(false),
            "hover": _band_style(true),
            "pressed": _band_style(true),
            "focus": _band_style(true),
        })
        var numeral := Label.new()
        numeral.text = str(option["numeral"])
        numeral.position = Vector2(18.0, 0.0)
        numeral.size = Vector2(48.0, BAND_H)
        numeral.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        numeral.add_theme_font_size_override("font_size", Tokens.T_META)
        numeral.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(numeral)
        var accent := Panel.new()
        accent.name = "Accent"
        accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
        accent.position = Vector2(0.0, 0.0)
        accent.size = Vector2(4.0, BAND_H)
        accent.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
        accent.visible = false
        row.add_child(accent)
        var label := Label.new()
        label.text = str(option["label"])
        label.position = Vector2(74.0, 0.0)
        label.size = Vector2(BAND_W - 120.0, BAND_H)
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.add_theme_font_size_override("font_size", Tokens.T_NAV + 4)
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(label)
        var rule := Panel.new()
        rule.name = "Rule"
        rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
        rule.position = Vector2(0.0, BAND_H - 1.0)
        rule.size = Vector2(BAND_W, 1.0)
        rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE))
        row.add_child(rule)
        row.pressed.connect(option["action"])
        row.focus_entered.connect(_on_row_selected.bind(i))
        row.mouse_entered.connect(_on_row_hovered.bind(i))
        page.add_child(row)
        buttons[str(option["id"])] = row
        _rows.append({"button": row, "accent": accent, "numeral": numeral, "label": label, "title": option["title"], "context": option["context"], "motif": option["motif"]})
        var cursor = get_node_or_null("/root/Cursor")
        if cursor != null and cursor.hand != null:
            cursor.hand.add_target(row)

func _band_style(selected: bool) -> StyleBoxFlat:
    # Structural layer 1: the plate itself. Unselected bands are just a quiet
    # material with a hairline rule; selection adds the plate and the accent.
    if selected:
        return Tokens.flat(Tokens.SURFACE_2, Tokens.RULE_WARM, Tokens.STROKE)
    return Tokens.flat(Color(0.06, 0.11, 0.11, 0.55), Color(0, 0, 0, 0), 0)

func _build_context_region() -> void:
    var frame := Panel.new()
    frame.name = "ContextFrame"
    frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    frame.position = CONTEXT_RECT.position
    frame.size = CONTEXT_RECT.size
    frame.add_theme_stylebox_override("panel", Tokens.flat(Color(0.06, 0.11, 0.11, 0.62), Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_FRAME))
    page.add_child(frame)
    _context_title = Label.new()
    _context_title.name = "ContextTitle"
    _context_title.position = CONTEXT_RECT.position + Vector2(28.0, 26.0)
    _context_title.size = Vector2(CONTEXT_RECT.size.x - 56.0, 40.0)
    _context_title.add_theme_font_size_override("font_size", Tokens.T_SCREEN)
    page.add_child(_context_title)
    _context_body = Tokens.meta_label("")
    _context_body.name = "ContextBody"
    _context_body.position = CONTEXT_RECT.position + Vector2(28.0, 74.0)
    _context_body.size = Vector2(CONTEXT_RECT.size.x - 56.0, 60.0)
    _context_body.add_theme_font_size_override("font_size", Tokens.T_ACTION)
    _context_body.modulate = Color(1, 1, 1, 0.85)
    _context_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    page.add_child(_context_body)
    _context_label = Label.new()
    _context_label.name = "ContextLine"
    _context_label.position = CONTEXT_RECT.position + Vector2(28.0, CONTEXT_RECT.size.y - 40.0)
    _context_label.size = Vector2(CONTEXT_RECT.size.x - 56.0, 24.0)
    _context_label.add_theme_font_size_override("font_size", Tokens.T_MICRO)
    _context_label.modulate = Color(1, 1, 1, 0.5)
    page.add_child(_context_label)

func _on_row_hovered(index: int) -> void:
    # Stationary pointers must not take over the menu (mouse intent, brief §5).
    var cursor = get_node_or_null("/root/Cursor")
    if cursor != null and cursor.hand != null and not cursor.hand.is_mouse_active():
        return
    _on_row_selected(index)

func _on_row_selected(index: int) -> void:
    if index < 0 or index >= _rows.size():
        return
    _selected = index
    for i in _rows.size():
        var selected: bool = i == index
        var accent: Panel = _rows[i]["accent"]
        accent.visible = selected
        var row_button: Button = _rows[i]["button"]
        row_button.position.x = BAND_X + (BAND_GROW if selected else 0.0)
        row_button.size.x = BAND_W - (BAND_GROW if selected else 0.0)
        var numeral: Label = _rows[i]["numeral"]
        numeral.add_theme_color_override("font_color", Tokens.ACCENT if selected else Tokens.CREAM_DIM)
        var label: Label = _rows[i]["label"]
        label.add_theme_color_override("font_color", Tokens.CREAM if selected else Tokens.CREAM_DIM)
    _apply_context(_rows[index])
    # swap the selection plate material without touching layout bounds
    _rows[index]["button"].add_theme_stylebox_override("normal", _band_style(true))
    for i in _rows.size():
        if i != index:
            _rows[i]["button"].add_theme_stylebox_override("normal", _band_style(false))

func _apply_context(row: Dictionary) -> void:
    if _context_title == null or _context_body == null:
        return
    _context_title.text = str(row["title"])
    _context_body.text = str(row["context"])
    _context_label.text = "ENTER  \u00b7  CLICK"
    if _motif != null and is_instance_valid(_motif):
        _motif.queue_free()
    _motif = _build_motif(str(row["motif"]))
    var tween := create_tween().set_parallel()
    tween.tween_property(_context_title, "modulate:a", 1.0, 12.0 / 60.0).from(0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_property(_context_body, "modulate:a", 1.0, 14.0 / 60.0).from(0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    if _motif != null:
        _motif.modulate.a = 0.0
        var mt := create_tween()
        mt.tween_property(_motif, "modulate:a", 1.0, 16.0 / 60.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _build_motif(kind: String) -> Control:
    # Geometric placeholder motifs (final art later): thin bars arranged per
    # option so the context region answers the selection without illustration.
    var holder := Control.new()
    holder.name = "ContextMotif"
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    holder.position = CONTEXT_RECT.position + Vector2(28.0, 158.0)
    holder.size = Vector2(CONTEXT_RECT.size.x - 56.0, CONTEXT_RECT.size.y - 190.0)
    page.add_child(holder)
    var w: float = holder.size.x
    var h: float = holder.size.y
    var bar := func(x: float, y: float, bw: float, bh: float, color: Color, alpha := 1.0) -> Panel:
        var p := Panel.new()
        p.mouse_filter = Control.MOUSE_FILTER_IGNORE
        p.position = Vector2(x, y)
        p.size = Vector2(bw, bh)
        p.add_theme_stylebox_override("panel", Tokens.flat(Color(color, alpha)))
        holder.add_child(p)
        return p
    match kind:
        "versus":
            # two opposing blocks with a gap: a duel
            bar.call(0.0, h * 0.15, w * 0.42, h * 0.7, Tokens.SURFACE_3)
            bar.call(w * 0.58, h * 0.15, w * 0.42, h * 0.7, Tokens.SURFACE_3)
            bar.call(w * 0.48, h * 0.3, w * 0.04, h * 0.4, Tokens.ACCENT)
        "encounter":
            # a stack of encounter cards
            for i in 4:
                bar.call(w * 0.06 * i, h * 0.2 + i * h * 0.16, w * 0.5, h * 0.1, Tokens.SURFACE_3 if i < 3 else Tokens.ACCENT)
        "guide":
            # a rule list: lines of a manual
            for i in 4:
                bar.call(0.0, i * h * 0.26, w * (0.8 - i * 0.14), 3.0, Tokens.CREAM_DIM, 0.8)
            bar.call(w * 0.86, 0.0, w * 0.14, h * 0.9, Tokens.SURFACE_3)
        _:
            # a door left ajar for QUIT
            bar.call(w * 0.1, 0.0, w * 0.6, h, Tokens.SURFACE_3)
            bar.call(w * 0.76, 0.0, 3.0, h, Tokens.CREAM_DIM, 0.7)
            bar.call(w * 0.62, h * 0.44, w * 0.08, h * 0.12, Tokens.ACCENT)
    return holder

func _build_quit_rows() -> void:
    var options: Array = [
        {"label": "Stay here", "id": "home", "action": func(): _nav(func(): show_page("home"))},
        {"label": "Quit", "id": "exit", "action": func(): _nav(func(): get_tree().quit())},
    ]
    for i in options.size():
        var option: Dictionary = options[i]
        var row := Button.new()
        row.name = str(option["id"])
        row.text = str(option["label"])
        row.position = Vector2(BAND_X, 320.0 + i * (BAND_H + BAND_GAP))
        row.size = Vector2(BAND_W, BAND_H)
        row.add_theme_font_size_override("font_size", Tokens.T_NAV)
        Tokens.apply_styles(row, Tokens.row_styles())
        row.pressed.connect(option["action"])
        page.add_child(row)
        buttons[str(option["id"])] = row
        var cursor = get_node_or_null("/root/Cursor")
        if cursor != null and cursor.hand != null:
            cursor.hand.add_target(row)

func add_button(label: String, id: String, y: float, action: Callable):
    var b := Button.new()
    b.name = id
    b.text = label
    b.position = Vector2(BAND_X, y)
    b.size = Vector2(290,62)
    b.add_theme_font_size_override("font_size", Tokens.T_NAV)
    Tokens.apply_styles(b, Tokens.row_styles())
    page.add_child(b)
    b.pressed.connect(action)
    buttons[id] = b
    var cursor = get_node_or_null("/root/Cursor")
    if cursor != null and cursor.hand != null:
        cursor.hand.add_target(b)

func _enter(mode: String) -> void:
    # Authored transition: the board eases out before the scene change.
    _animate_out_then(func():
        AppStateScript.enter_mode = mode
        get_tree().auto_accept_quit = true
        get_tree().change_scene_to_file("res://scenes/main.tscn"))

func _animate_out_then(action: Callable) -> void:
    if page == null:
        action.call()
        return
    var tween := create_tween().set_parallel()
    tween.tween_property(page, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    tween.tween_property(page, "scale", Vector2(0.98, 0.97), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    tween.chain().tween_callback(action)

func _unhandled_key_input(event):
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        show_page("quit" if state == "home" else "home")
        get_viewport().set_input_as_handled()
    elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10 and OS.is_debug_build() and state == "home":
        # Developer route: the old monolithic setup as a debug launcher,
        # deliberately not part of the normal player menu.
        _nav(func(): _enter("debug"))
        get_viewport().set_input_as_handled()
