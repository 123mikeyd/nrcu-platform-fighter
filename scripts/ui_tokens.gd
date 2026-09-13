extends RefCounted
# NRCU frontend design tokens — ONE source for the visual system.
#
# Visual Direction spec (02) §4: spacing scale, type roles, neutral/accent/
# player colors, stroke widths and the image-frame treatment all live here so
# individual screens never eyeball unrelated values. Screens compose in the
# 1280x720 design canvas (project.godot: stretch mode "canvas_items" scales it
# uniformly to the window, so 1080p needs no separate coordinates).

# --- design canvas -------------------------------------------------------
const DESIGN := Vector2(1280.0, 720.0)
const MARGIN := 64.0          # screen breathing room (spec: 48-64)
const MARGIN_RIGHT := 56.0

# --- spacing scale (spec §4.1) -------------------------------------------
const S4 := 4.0
const S8 := 8.0
const S12 := 12.0
const S16 := 16.0
const S24 := 24.0
const S32 := 32.0
const S48 := 48.0
const S64 := 64.0

# --- type roles (spec §6) ------------------------------------------------
const T_HERO := 48
const T_SCREEN := 30
const T_IDENTITY := 34
const T_NAV := 24
const T_ACTION := 20
const T_META := 15
const T_MICRO := 12

# --- color roles (spec §4.2: ~70-80% neutrals, <=10% accent) -------------
const BG_DEEP := Color("0d1617")
const BASE := Color("142123")
const SURFACE_1 := Color("1a2c2e")
const SURFACE_2 := Color("223a3b")
const SURFACE_3 := Color("284e50")
const SURFACE_HI := Color("35595a")
const INK := Color("16292b")
const RULE := Color("1b3436")          # quiet structural line
const RULE_WARM := Color("8a5a2b")     # secondary structural line
const ACCENT := Color("e5ad69")        # the ONE selection accent
const CREAM := Color("fff0cb")
const CREAM_DIM := Color("b9b39d")

const PLAYER_COLORS: Array = [
    Color("d95a4f"), Color("4f7fd9"), Color("d9c04f"), Color("5ad94f"),
]

# --- strokes / radii (spec §5) -------------------------------------------
const STROKE := 1
const STROKE_STRONG := 2
const STROKE_SELECT := 3
const RADIUS_FLAT := 0
const RADIUS_PLATE := 2
const RADIUS_FRAME := 4
# Reserved space around an item so a selection frame can never touch a
# neighbour's border (spec §5.2 / CSS §13.6: pixel-QA requirement).
const SELECTION_GUTTER := 12.0

# --- builders ------------------------------------------------------------
static func flat(bg: Color, border := Color(0, 0, 0, 0), width := 0, radius := RADIUS_PLATE) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = bg
    s.border_color = border
    s.set_border_width_all(width)
    s.set_corner_radius_all(radius)
    return s

static func pad(box: StyleBoxFlat, l: float, t: float, r: float, b: float) -> StyleBoxFlat:
    box.content_margin_left = l
    box.content_margin_top = t
    box.content_margin_right = r
    box.content_margin_bottom = b
    return box

# A quiet structural line/band (spec §4.3: thin rules instead of heavy frames).
static func band(color: Color, height: float) -> Panel:
    var p := Panel.new()
    p.mouse_filter = Control.MOUSE_FILTER_IGNORE
    p.size = Vector2(0.0, height)
    p.add_theme_stylebox_override("panel", flat(color))
    return p

# Unselected: quiet. Selected: structure (plate) + material + ONE accent.
static func row_styles() -> Dictionary:
    return {
        "normal": flat(SURFACE_1, RULE, STROKE),
        "hover": flat(SURFACE_2, RULE_WARM, STROKE),
        "pressed": flat(SURFACE_2, ACCENT, STROKE_STRONG),
        "focus": flat(SURFACE_2, ACCENT, STROKE_STRONG),
    }

static func apply_styles(control: Control, styles: Dictionary) -> void:
    for key in styles.keys():
        control.add_theme_stylebox_override(str(key), styles[key])

# Image frame: real clipping (spec §9.2 — a border drawn over overflow is not
# a mask). clip_contents crops the child hard-edge frame; the texture uses
# cover-crop so raster art never stretches.
static func image_frame(parent: Control, rect: Rect2, texture: Texture2D, inset := 3.0) -> Dictionary:
    var frame := Control.new()
    frame.name = "ImageFrame"
    frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    frame.clip_contents = true
    frame.position = rect.position
    frame.size = rect.size
    parent.add_child(frame)
    var image := TextureRect.new()
    image.name = "FrameImage"
    image.texture = texture
    image.mouse_filter = Control.MOUSE_FILTER_IGNORE
    image.position = Vector2(inset, inset)
    image.size = rect.size - Vector2(inset, inset) * 2.0
    image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    frame.add_child(image)
    var border := Panel.new()
    border.name = "FrameBorder"
    border.mouse_filter = Control.MOUSE_FILTER_IGNORE
    border.position = Vector2.ZERO
    border.size = rect.size
    border.add_theme_stylebox_override("panel", flat(Color(0, 0, 0, 0), RULE_WARM, STROKE, RADIUS_FRAME))
    frame.add_child(border)
    return {"frame": frame, "image": image, "border": border}

# Highlight that never collides: a plate UNDER the item, grown into the
# reserved gutter, plus one accent rule. Never two coincident outlines.
static func selection_plate(parent: Control, rect: Rect2) -> Panel:
    var plate := Panel.new()
    plate.name = "SelectionPlate"
    plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
    plate.position = rect.position
    plate.size = rect.size
    plate.add_theme_stylebox_override("panel", flat(SURFACE_2, ACCENT, STROKE_SELECT, RADIUS_FRAME))
    plate.hide()
    parent.add_child(plate)
    return plate

static func meta_label(text: String) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", T_META)
    l.add_theme_color_override("font_color", CREAM)
    return l

static func heading(text: String, size := T_SCREEN) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", CREAM)
    return l
