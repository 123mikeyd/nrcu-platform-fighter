extends Control
# Stage Select (SSS) - the match's stage picker: Melee grammar in NRCU's art.
#
# Composition (visual spec §13) on the 1280x720 design canvas:
#
#   +---------------------------------------------------------------+
#   | STAGE SELECT                                    [ BACK ]      |  header
#   | one line of intent                                            |
#   +-----------------------------+---------------------------------+
#   | STAGES                      | SELECTED STAGE                  |
#   | stage field: stable 16:9    | big preview frame (its own      |
#   | tiles, reserved selection   | crop policy, never the small    |  body
#   | gutter, authored reserve    | tile node) + stage name + index |
#   | slots that stay reserved    |                                 |
#   +-----------------------------+---------------------------------+
#   | CLICK PREVIEWS - CLICK AGAIN CONFIRMS - BACK / ESC RETURNS    |  footer
#   +---------------------------------------------------------------+
#
# The two regions never share a node: the field ends at x=660 and the preview
# region lives right of x=700, whatever the stage count is, so a tile and the
# preview can never overlap by construction.
#
# Retail grammar that is kept verbatim:
#   - staggered fly-in from the right, tiles arrive 0/5/10 ticks apart
#   - sticky hover: only the tiles report hover, gaps keep the last one
#   - highlight plate in the reserved gutter with the 10-tick pulse
#   - stage name swaps with the 9-tick in / 11-tick out overlap
#   - confirm: 30-tick input lock, cursor drops out, page exits to the setup
#
# Image fitting (spec §9.2): every stage image lives in a Tokens.image_frame -
# a Control with clip_contents (a real crop) around a KEEP_ASPECT_COVERED
# TextureRect. A border drawn over the overflow is not a mask, so nothing here
# fakes a frame or stretches a picture.
#
# Mouse intent (brief §5): the hand never warps and never chases focus, and a
# stationary pointer drives no hover - tile hover is gated behind the cursor's
# own modality, so entering the screen neither inherits the old screen's hover
# nor lets a pointer that happens to sit on a tile steal the sticky hover.
#
# Presentation only: the chosen level id goes back to main.gd, which writes it
# into the hidden setup model (no dropdown is touched here).

signal confirmed(id: String)
signal exit_finished

const Tokens = preload("res://scripts/ui_tokens.gd")
const CursorAnchorScript = preload("res://scripts/frontend/cursor_anchor.gd")
const BackActionScene = preload("res://scenes/components/BackAction.tscn")
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")

const FPS := 60.0

# --- stage field (left region) -------------------------------------------
# The field is the left 55% region (0..704) with the grid centered in it: the
# 24px selection gutters and the ~190px landscape cell (both spec numbers)
# place the reserve row at 43..659, inside the hard x=660 region gate, so a
# tile can never cross into the preview region.
const GRID_COLS := 3
const FIELD_X := 43.0                   # grid axis, centred in the left region
const FIELD_W := 616.0                  # 43 .. 659 (gate: tiles end <= 660)
const FIELD_TOP := 132.0
const FIELD_BOTTOM := 540.0
const GRID_GAP := Tokens.S24            # reserved selection gutter (>= 24)
const RESERVE_ROWS := 3                 # the authored field: 3 x 3 slots
const TILE_AR := 16.0 / 9.0             # landscape, never stretched
const TILE_INSET := 3.0                 # matte between frame line and image
const CAPTION_BAND := 22.0
const CAPTION_MIN_CELL := 64.0
const SELECTION_GROW := 10.0            # must stay below GRID_GAP / 2

# --- preview region (right) ----------------------------------------------
const PREVIEW_RECT := Rect2(732.0, 144.0, 492.0, 276.75)   # 16:9, own crop
const PREVIEW_INSET := 12.0
const PREVIEW_PLATE_GROW := 12.0
const NAME_Y := 466.0
const NAME_H := 44.0
const META_Y := 516.0

# --- chrome --------------------------------------------------------------
const HEADER_TITLE_Y := 28.0
const HEADER_SUBTITLE_Y := 68.0
const REGION_CAPTION_Y := 108.0
const DIVIDER_X := 704.0                # left region = 55% of the canvas
const FOOTER_RULE_Y := 600.0
const FOOTER_TEXT_Y := 612.0

# --- motion (retail ticks) -----------------------------------------------
const FLYIN_DELAY_TICKS := [0.0, 5.0, 10.0]
const FLYIN_TICKS := 12.0
const ENTER_LOCK := 0.35
const CONFIRM_LOCK := 30.0 / FPS
const NAME_IN := 9.0 / FPS
const NAME_OUT := 11.0 / FPS
const PULSE_TICKS := 10.0
const PREVIEW_IN_TICKS := 8.0
const PREVIEW_FADE_IN := 0.18
const PREVIEW_FADE_DELAY := 0.05
const EXIT_SECONDS := 0.22

enum Phase { ENTERING, IDLE, CONFIRMING, EXITING }

var cursor: Control

var _slots: Array = []
var _tiles: Array = []
var _tile_anchors: Array = []
var _captions: Array = []
var _content: Control
var _preview_layer: Control
var _preview: TextureRect
var _preview_image: TextureRect
var _box: Panel
var _name_label: Label
var _meta_label: Label
var _back: Button
var _park := Vector2(1900.0, 375.0)
var _phase: Phase = Phase.IDLE
var _lock := 0.0
var _hovered := -1
var _focus_index := -1
var _confirmed := ""
var _pulse := 0.0
var _flyin_pending := 0

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var root = get_node_or_null("/root/Cursor")
    if root != null:
        cursor = root.hand
    # Doc 03 §7/§11: Back and cancel route through the semantic service, never
    # through ad-hoc key decoding (a JoypadButton never reaches such a handler).
    if not FrontendInput.cancel_pressed.is_connected(_on_semantic_cancel):
        FrontendInput.cancel_pressed.connect(_on_semantic_cancel)

func build(slots: Array) -> void:
    # Re-entrant: rebuilding with a different stage list replaces the old
    # field (used by the scalability tests with synthetic stage counts).
    if _content != null and is_instance_valid(_content):
        _content.queue_free()
        _content = null
        _slots = []
        _tiles.clear()
        _tile_anchors.clear()
        _captions.clear()
        _preview_layer = null
        _preview = null
        _preview_image = null
        _box = null
    _slots = slots
    _content = Control.new()
    _content.name = "StageContent"
    _content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_content)
    _build_header()
    _build_divider()
    _build_preview()
    _build_field()
    _build_footer()
    _wire_focus_graph()
    _ensure_focus_alive()
    if cursor != null:
        cursor.add_target(_back)

func _build_header() -> void:
    var title := Tokens.heading("STAGE SELECT", Tokens.T_SCREEN)
    title.position = Vector2(Tokens.MARGIN, HEADER_TITLE_Y)
    _content.add_child(title)
    var subtitle := Tokens.meta_label("Pick the stage the match is played on.")
    subtitle.position = Vector2(Tokens.MARGIN + 2.0, HEADER_SUBTITLE_Y)
    subtitle.modulate = Color(1, 1, 1, 0.62)
    _content.add_child(subtitle)
    # BACK is always visible: the page is never a trap. It owns an authored
    # CursorAnchor like every other focusable control here (Doc 03 §6).
    _back = BackActionScene.instantiate()
    _back.name = "StageBack"
    _back.text = "BACK"
    _back.size = Vector2(170.0, 46.0)
    _back.position = Vector2(Tokens.DESIGN.x - Tokens.MARGIN_RIGHT - 170.0, HEADER_TITLE_Y + 2.0)
    _back.pressed.connect(request_back)
    _back.focus_entered.connect(_on_back_focused)
    _content.add_child(_back)
    # The shared BackAction owns the authored CursorAnchor and its visual state;
    # this screen only supplies geometry and the existing route signal.

func _build_divider() -> void:
    # One quiet vertical rule: the field and the preview read as two regions.
    var divider := Panel.new()
    divider.name = "RegionRule"
    divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
    divider.position = Vector2(DIVIDER_X, REGION_CAPTION_Y)
    divider.size = Vector2(Tokens.STROKE, FOOTER_RULE_Y - REGION_CAPTION_Y)
    divider.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE))
    _content.add_child(divider)

func _build_preview() -> void:
    # The preview is its own region with its own crop policy: the tile node is
    # never scaled up here. The visible picture lives in a Tokens frame
    # (clip + cover + border); StagePreview is the region node that owns it.
    var caption := Tokens.heading("SELECTED STAGE", Tokens.T_MICRO)
    caption.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    caption.position = Vector2(PREVIEW_RECT.position.x + 2.0, REGION_CAPTION_Y)
    _content.add_child(caption)
    _preview_layer = Control.new()
    _preview_layer.name = "PreviewLayer"
    _preview_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _content.add_child(_preview_layer)
    var plate := Panel.new()
    plate.name = "PreviewPlate"
    plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
    plate.position = PREVIEW_RECT.position - Vector2(PREVIEW_PLATE_GROW, PREVIEW_PLATE_GROW)
    plate.size = PREVIEW_RECT.size + Vector2(PREVIEW_PLATE_GROW, PREVIEW_PLATE_GROW) * 2.0
    plate.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_FRAME))
    _preview_layer.add_child(plate)
    _preview = TextureRect.new()
    _preview.name = "StagePreview"
    _preview.position = PREVIEW_RECT.position
    _preview.size = PREVIEW_RECT.size
    _preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _preview_layer.add_child(_preview)
    var framed: Dictionary = Tokens.image_frame(_preview, Rect2(Vector2.ZERO, PREVIEW_RECT.size), null, PREVIEW_INSET)
    var image: TextureRect = framed["image"]
    image.name = "StagePreviewImage"
    _preview_image = image
    _name_label = Label.new()
    _name_label.name = "StageName"
    _name_label.size = Vector2(PREVIEW_RECT.size.x, NAME_H)
    _name_label.position = Vector2(PREVIEW_RECT.position.x, NAME_Y)
    _name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _name_label.add_theme_font_size_override("font_size", Tokens.T_IDENTITY)
    _content.add_child(_name_label)
    var rule := Panel.new()
    rule.name = "NameRule"
    rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
    rule.position = Vector2(PREVIEW_RECT.position.x + 2.0, NAME_Y + NAME_H - 6.0)
    rule.size = Vector2(PREVIEW_RECT.size.x - 4.0, Tokens.STROKE_STRONG)
    rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.RULE_WARM))
    _content.add_child(rule)
    _meta_label = Tokens.meta_label("")
    _meta_label.name = "StageIndex"
    _meta_label.position = Vector2(PREVIEW_RECT.position.x + 2.0, META_Y)
    _meta_label.modulate = Color(1, 1, 1, 0.62)
    _content.add_child(_meta_label)

func _build_field() -> void:
    var caption := Tokens.heading("STAGES", Tokens.T_MICRO)
    caption.add_theme_color_override("font_color", Tokens.CREAM_DIM)
    caption.position = Vector2(FIELD_X, REGION_CAPTION_Y)
    _content.add_child(caption)
    var count: int = _slots.size()
    var cols: int = _columns(count)
    var cell: Vector2 = _cell_size(count, cols)
    _build_reserve(count, cols, cell)
    # The highlight is a plate UNDER the tiles: it grows into the reserved
    # gutter, so it can never coincide with a tile border and never moves a
    # tile's layout bounds.
    _box = Tokens.selection_plate(_content, Rect2())
    _box.name = "SelectBox"
    var band: float = minf(CAPTION_BAND, cell.y * 0.34)
    var show_caption: bool = cell.y >= CAPTION_MIN_CELL
    for i in count:
        var slot: Dictionary = _slots[i]
        var row: int = i / cols
        var col: int = i % cols
        var corner := Vector2(FIELD_X + col * (cell.x + GRID_GAP), FIELD_TOP + row * (cell.y + GRID_GAP))
        slot["anchor"] = corner + cell * 0.5
        var tile := Button.new()
        tile.name = "StageTile" + str(i)
        tile.size = cell
        tile.custom_minimum_size = cell
        tile.pivot_offset = cell * 0.5
        tile.add_theme_font_size_override("font_size", Tokens.T_META)
        # The frame owns the outline, so the button itself draws no second
        # border: state shows as the matte tone, selection as the plate.
        Tokens.apply_styles(tile, {
            "normal": Tokens.flat(Tokens.SURFACE_3),
            "hover": Tokens.flat(Tokens.SURFACE_HI),
            "pressed": Tokens.flat(Tokens.SURFACE_2),
            "focus": Tokens.flat(Color(0, 0, 0, 0)),
        })
        tile.position = corner
        var framed: Dictionary = Tokens.image_frame(tile, Rect2(Vector2.ZERO, cell), load(str(slot["tex"])), TILE_INSET)
        var thumb: TextureRect = framed["image"]
        thumb.name = "StageThumbnail" + str(i)
        var border: Panel = framed["border"]
        border.add_theme_stylebox_override("panel", Tokens.flat(Color(0, 0, 0, 0), Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_FRAME))
        var label: Label = null
        if show_caption:
            var scrim := Panel.new()
            scrim.name = "CaptionScrim"
            scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
            scrim.position = Vector2(TILE_INSET, cell.y - TILE_INSET - band)
            scrim.size = Vector2(cell.x - TILE_INSET * 2.0, band)
            scrim.add_theme_stylebox_override("panel", Tokens.flat(Color(Tokens.BG_DEEP, 0.82)))
            tile.add_child(scrim)
            label = Label.new()
            label.name = "Caption"
            label.text = str(slot["name"])
            label.position = Vector2(TILE_INSET + 3.0, cell.y - TILE_INSET - band + 1.0)
            label.size = Vector2(cell.x - TILE_INSET * 2.0 - 6.0, band)
            label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
            label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
            label.add_theme_font_size_override("font_size", Tokens.T_MICRO)
            label.add_theme_color_override("font_color", Tokens.CREAM_DIM)
            label.mouse_filter = Control.MOUSE_FILTER_IGNORE
            tile.add_child(label)
        tile.pressed.connect(_on_tile_pressed.bind(i))
        tile.mouse_entered.connect(_on_tile_hovered.bind(i))
        # §13: a focus move IS a preview move — exactly like mouse hover.
        tile.focus_entered.connect(_on_tile_focused.bind(i))
        # Authored focus-cursor anchor: the caption strip is the tile's only
        # measured surface and its text must stay readable, so the fingertip
        # lands at the strip's TRAILING end — on the surface, with the hand
        # sprite (which draws down-right of the tip) in the quiet gutter beside
        # the tile instead of over the caption. Without a caption the tile
        # falls back to the shared default ratio on the tile itself.
        var caption_right: float = cell.x - TILE_INSET
        var anchor_at := cell * Vector2(0.80, 0.72)
        if show_caption:
            anchor_at = Vector2(caption_right + CursorAnchorScript.HAND_REACH_LEFT + 1.8,
                    cell.y - TILE_INSET - band + 3.0)
        var anchor := CursorAnchorScript.new()
        anchor.name = "TileAnchor" + str(i)
        anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
        anchor.place_at(anchor_at)
        tile.add_child(anchor)
        _tile_anchors.append(anchor)
        _content.add_child(tile)
        _tiles.append(tile)
        _captions.append(label)
        if cursor != null:
            cursor.add_target(tile)

func _build_reserve(count: int, cols: int, cell: Vector2) -> void:
    # The field is authored, not stretched: the slots the current set leaves
    # empty are drawn as quiet reserved cells, so empty space reads as room
    # for more stages instead of a grid that failed to fill.
    var reserved: int = RESERVE_ROWS * GRID_COLS
    if count >= reserved or cols != GRID_COLS:
        return
    for j in range(count, reserved):
        var row: int = j / cols
        var col: int = j % cols
        var ghost := Panel.new()
        ghost.name = "StageReserve" + str(j)
        ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
        ghost.position = Vector2(FIELD_X + col * (cell.x + GRID_GAP), FIELD_TOP + row * (cell.y + GRID_GAP))
        ghost.size = cell
        ghost.add_theme_stylebox_override("panel", Tokens.flat(Color(0, 0, 0, 0), Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_FRAME))
        _content.add_child(ghost)

func _build_footer() -> void:
    var rule := Tokens.band(Tokens.RULE, Tokens.STROKE)
    rule.name = "FooterRule"
    rule.position = Vector2(FIELD_X, FOOTER_RULE_Y)
    rule.size = Vector2(Tokens.DESIGN.x - Tokens.MARGIN_RIGHT - FIELD_X, Tokens.STROKE)
    _content.add_child(rule)
    var hint := Tokens.meta_label("CLICK A STAGE TO PREVIEW IT - CLICK IT AGAIN TO CONFIRM - BACK / ESC RETURNS")
    hint.name = "FooterHint"
    hint.position = Vector2(FIELD_X + 2.0, FOOTER_TEXT_Y)
    hint.modulate = Color(1, 1, 1, 0.62)
    _content.add_child(hint)

func _columns(count: int) -> int:
    # The authored field holds the reserve grid (3x3). A larger set packs
    # tighter by widening the grid, never by growing a single cell.
    if count <= RESERVE_ROWS * GRID_COLS:
        return GRID_COLS
    if count <= 16:
        return 4
    if count <= 25:
        return 5
    return 6

func _cell_size(count: int, cols: int) -> Vector2:
    # One stable landscape cell: the column bound and the row bound both
    # apply, and the 16:9 ratio is fixed, so more stages shrink both axes
    # together instead of restretching a tile.
    var rows: int = maxi(ceili(float(count) / float(cols)), 1)
    var by_w: float = (FIELD_W - (cols - 1) * GRID_GAP) / float(cols)
    var by_h: float = (FIELD_BOTTOM - FIELD_TOP - (rows - 1) * GRID_GAP) / float(rows)
    var w: float = minf(by_w, by_h * TILE_AR)
    return Vector2(w, w / TILE_AR)

func open_with(current_id: String, focus_id: String) -> void:
    _confirmed = ""
    _phase = Phase.ENTERING
    _lock = ENTER_LOCK
    _hovered = -1
    _pulse = 0.0
    _flyin_pending = 0
    _box.hide()
    _focus_index = _index_of(focus_id)
    if _focus_index < 0:
        _focus_index = _index_of(current_id)
    _preview_image.texture = null
    _name_label.text = "CHOOSE YOUR STAGE"
    _name_label.modulate = Color(1, 1, 1, 0.55)
    _name_label.position.y = NAME_Y
    _meta_label.text = ""
    _content.modulate.a = 1.0
    _set_caption_state(-1)
    Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
    if cursor != null:
        # Stage Select always uses the regular cursor (project decision): the
        # Character Select token state must never leak in here. The hand is
        # re-anchored at the pointer as it is now and waits for real motion.
        cursor.visible = true
        cursor.begin_screen("stage_select")
        cursor.clear_carry()
    # The preview region fades on its own clock; the name swaps on its own
    # (see _swap_name), so the two layers never collapse into one fade.
    _preview_layer.modulate.a = 0.0
    var fade := create_tween()
    fade.tween_property(_preview_layer, "modulate:a", 1.0, PREVIEW_FADE_IN).set_delay(PREVIEW_FADE_DELAY).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    var view: Vector2 = get_viewport_rect().size
    _park = Vector2(maxf(view.x, Tokens.DESIGN.x) + 620.0, FIELD_TOP)
    for i in _tiles.size():
        var tile: Button = _tiles[i]
        var target: Vector2 = _slots[i]["anchor"] - tile.size * 0.5
        var ticks: float = FLYIN_DELAY_TICKS[i % FLYIN_DELAY_TICKS.size()]
        tile.scale = Vector2.ONE
        tile.modulate.a = 0.35
        tile.position = Vector2(_park.x - tile.size.x * 0.5, target.y)
        var tween := create_tween()
        tween.tween_property(tile, "position", target, FLYIN_TICKS / FPS).set_delay(ticks / FPS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        tween.parallel().tween_property(tile, "modulate:a", 1.0, FLYIN_TICKS / FPS).set_delay(ticks / FPS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        _flyin_pending += 1
        tween.finished.connect(_on_tile_landed)
    if _tiles.is_empty():
        _on_flyin_done()

func _on_tile_landed() -> void:
    _flyin_pending = maxi(_flyin_pending - 1, 0)
    if _flyin_pending <= 0:
        _on_flyin_done()

func _on_flyin_done() -> void:
    if _phase != Phase.ENTERING:
        return
    _phase = Phase.IDLE
    if _focus_index >= 0:
        hover_slot(_focus_index)
        _focus_index = -1
    _seed_focus()

func _seed_focus() -> void:
    # Keyboard/controller: seed focus on the hovered tile (never for a mouse
    # user, whose hand drives the selection instead).
    if cursor != null and cursor.is_mouse_active():
        return
    var idx: int = _hovered if _hovered >= 0 else 0
    if idx < 0 or idx >= _tiles.size():
        return
    _tiles[idx].grab_focus()
    if cursor != null and cursor.mode == 1 and idx < _tile_anchors.size():
        cursor.set_focus_target(_tile_anchors[idx])

func hover_slot(index: int) -> void:
    # Hover exists only after the entrance: during ENTERING, CONFIRMING and
    # EXITING the field is inert.
    if _phase != Phase.IDLE:
        return
    if index < 0 or index >= _tiles.size():
        return
    if index == _hovered:
        return
    _hovered = index
    var tile: Button = _tiles[index]
    var rect := tile.get_rect()
    _box.position = rect.position - Vector2(SELECTION_GROW, SELECTION_GROW)
    _box.size = rect.size + Vector2(SELECTION_GROW, SELECTION_GROW) * 2.0
    _box.show()
    _pulse = 0.0
    if cursor != null and cursor.mode == 1 and index < _tile_anchors.size():
        # In focus/keyboard mode the hand tracks the logical selection at the
        # tile's authored anchor; the physical mouse is never involved.
        cursor.set_focus_target(_tile_anchors[index])
    _preview_image.texture = load(str(_slots[index]["tex"]))
    _preview_image.modulate.a = 0.55
    var settle := create_tween()
    settle.tween_property(_preview_image, "modulate:a", 1.0, PREVIEW_IN_TICKS / FPS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    _meta_label.text = "STAGE %d / %d" % [index + 1, _tiles.size()]
    _set_caption_state(index)
    _swap_name(str(_slots[index]["name"]))

func _set_caption_state(index: int) -> void:
    for i in _captions.size():
        var caption: Label = _captions[i]
        if caption == null:
            continue
        caption.add_theme_color_override("font_color", Tokens.CREAM if i == index else Tokens.CREAM_DIM)

func _on_tile_hovered(index: int) -> void:
    # A stationary pointer must not take over the screen: only genuine mouse
    # input counts (the cursor layer tracks the active modality), so a pointer
    # that happens to sit on a tile that flew in under it keeps the sticky
    # hover instead of stealing it.
    if cursor != null and not cursor.is_mouse_active():
        return
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
    tween.tween_property(_content, "modulate:a", 0.0, EXIT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    tween.tween_callback(func() -> void: exit_finished.emit())

func reset() -> void:
    _phase = Phase.IDLE
    _lock = 0.0
    _hovered = -1
    _confirmed = ""
    if _box != null:
        _box.hide()
    if _content != null:
        _content.modulate.a = 1.0
    if cursor != null:
        cursor.visible = true
        cursor.begin_screen("stage_select")

func get_tiles() -> Array:
    return _tiles

func get_tile_anchor(index: int) -> Control:
    if index < 0 or index >= _tile_anchors.size():
        return null
    return _tile_anchors[index]

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
    outgoing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    outgoing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
    if _box != null and _box.visible and _phase != Phase.EXITING:
        _pulse += delta
        _box.modulate.a = 0.72 + 0.28 * (0.5 + 0.5 * sin(TAU * _pulse / (PULSE_TICKS / FPS)))
    if _phase == Phase.CONFIRMING and _lock <= 0.0:
        play_exit()

# --- focus topology + semantic path (Doc 03 §6/§7/§11/§13) -----------------
func _wire_focus_graph() -> void:
    # Explicit grid graph: no dependence on automatic tree-order focus. The
    # authored field is a 3x3 reserve grid at the production stage count (and a
    # wider grid packs more stages), so the graph is derived from the real
    # columns/rows: in-row left/right, up to the row above (Back on the top
    # row), down to the row below (nothing below the last row — no wrap).
    if _tiles.is_empty():
        return
    var count := _tiles.size()
    var cols := _columns(count)
    for i in count:
        var tile: Button = _tiles[i]
        var col := i % cols
        var row := i / cols
        FocusGraph.clear(tile, [&"top", &"bottom", &"left", &"right"])
        if col > 0:
            FocusGraph.wire(tile, _tiles[i - 1], [&"left"])
        if col < cols - 1 and i + 1 < count:
            FocusGraph.wire(tile, _tiles[i + 1], [&"right"])
        if row > 0:
            FocusGraph.wire(tile, _tiles[i - cols], [&"top"])
        else:
            FocusGraph.wire(tile, _back, [&"top"])
        if i + cols < count:
            FocusGraph.wire(tile, _tiles[i + cols], [&"bottom"])
    # Back sits above the field: down enters the first tile, left reaches the
    # top row's last tile, and Tab order runs Back -> tiles -> Back.
    FocusGraph.wire(_back, _tiles[0], [&"bottom"])
    FocusGraph.wire(_back, _tiles[mini(cols - 1, count - 1)], [&"left"])
    var chain: Array = [_back]
    chain.append_array(_tiles)
    FocusGraph.chain(chain, true)

func _on_tile_focused(index: int) -> void:
    # §13: focus updates the preview exactly like mouse hover — the selection
    # plate, the stage name/index and the preview image all follow the focused
    # tile. §6: the focus-enter is atomic, so the hand is retargeted even when
    # the tile was already the hovered one (the spring must still settle here).
    if index < 0 or index >= _tiles.size():
        return
    FocusGraph.track(self, _tiles[index])
    if _phase != Phase.IDLE:
        return
    hover_slot(index)
    if cursor != null and cursor.mode == 1 and index < _tile_anchors.size():
        cursor.set_focus_target(_tile_anchors[index])

func _on_back_focused() -> void:
    FocusGraph.track(self, _back)
    if cursor != null and cursor.mode == 1:
        cursor.set_focus_target(FocusGraph.anchor_of(_back))

func focus_anchor_for(control: Control) -> Control:
    # The authored hand target of a focusable control on this screen (Doc 03 §6).
    var index: int = _tiles.find(control)
    if index >= 0 and index < _tile_anchors.size():
        return _tile_anchors[index]
    return FocusGraph.anchor_of(control)

func _ensure_focus_alive() -> void:
    # §6: a control that disappears (a rebuilt field) or becomes unreachable
    # never keeps the focus; the hand retargets immediately.
    if not is_inside_tree():
        return
    var before := FrontendInput.focus_owner()
    var owner := FocusGraph.recover(get_viewport(), self, func() -> Control:
        return _tiles[0] if not _tiles.is_empty() else _back)
    if owner != null and owner != before and cursor != null and cursor.mode == 1:
        var anchor := focus_anchor_for(owner)
        if anchor != null:
            cursor.set_focus_target(anchor)

func _on_semantic_cancel() -> void:
    # §11 Back matrix: SSS (pre-match and from Results) ui_cancel returns.
    if not is_visible_in_tree() or _phase == Phase.CONFIRMING or _phase == Phase.EXITING or _lock > 0.0:
        return
    request_back()
