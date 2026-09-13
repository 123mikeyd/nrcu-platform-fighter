extends RefCounted
# NRCU frontend design tokens — ONE source for the shared visual system.
#
# Step 0 structure: reference geometry, colors, type roles, motion timings and
# z-layers live here. This is NOT a layout factory: screens and components own
# their authored .tscn geometry and only pull values/roles from here.
#
# 1280x720 is the authoring/reference canvas (Doc 01 §4): runtime UI renders
# natively at the output resolution through canvas_items + expand, with every
# screen placing its core UI inside a centered ReferenceFrame.

# --- design canvas / reference geometry ---------------------------------
const DESIGN := Vector2(1280.0, 720.0)
const MARGIN := 56.0          # nominal safe margin (Doc 01 §5)
const MARGIN_RIGHT := 56.0
const REFERENCE_SAFE := Rect2(56.0, 24.0, 1168.0, 672.0)  # Doc 04 §3 safe area

# --- spacing scale (Doc 01 §5) ------------------------------------------
const S4 := 4.0
const S8 := 8.0
const S12 := 12.0
const S16 := 16.0
const S24 := 24.0
const S32 := 32.0
const S48 := 48.0
const S56 := 56.0
const S64 := 64.0

# --- type roles (Doc 01 §6 / Doc 08) ------------------------------------
# DISPLAY 40-54 · SCREEN 28-34 · IDENTITY 28-38 · NAV 21-27 · META 13-16 · HELP 12-14
const T_DISPLAY := 48
const T_SCREEN := 30
const T_IDENTITY := 30
const T_NAV := 24
const T_META := 14
const T_HELP := 13
# aliases kept for components authored against earlier role names
const T_HERO := 48
const T_ACTION := 20
const T_MICRO := 12

# --- typography (Doc 08: Zilla Slab, bundled, OFL) ----------------------
const FONT_REGULAR := "res://assets/fonts/ZillaSlab-Regular.ttf"
const FONT_MEDIUM := "res://assets/fonts/ZillaSlab-Medium.ttf"
const FONT_SEMIBOLD := "res://assets/fonts/ZillaSlab-SemiBold.ttf"
const FONT_BOLD := "res://assets/fonts/ZillaSlab-Bold.ttf"

static func font(weight := "regular") -> FontFile:
    var path := FONT_REGULAR
    match weight:
        "bold":
            path = FONT_BOLD
        "semibold":
            path = FONT_SEMIBOLD
        "medium":
            path = FONT_MEDIUM
    return load(path)

# --- color roles (Doc 01 §7) --------------------------------------------
const BG_DEEP := Color("0d1617")       # BASE_0
const BASE := Color("142123")          # BASE_1
const SURFACE_1 := Color("1a2c2e")     # SURFACE_0
const SURFACE_2 := Color("223a3b")     # SURFACE_1
const SURFACE_3 := Color("284e50")
const SURFACE_HI := Color("35595a")
const INK := Color("16292b")
const RULE := Color("1b3436")
const RULE_WARM := Color("8a5a2b")
const ACCENT := Color("e5ad69")        # ACCENT_GLOBAL
const CREAM := Color("fff0cb")         # TEXT_PRIMARY
const CREAM_DIM := Color("b9b39d")     # TEXT_SECONDARY
const DISABLED := Color("5a655f")
const ERROR := Color("d95a4f")

const PLAYER_COLORS: Array = [
    Color("d95a4f"), Color("4f7fd9"), Color("d9c04f"), Color("5ad94f"),
]
# Team identity is deliberately distinct from P1-P4 player colors (Doc 06 §5).
const TEAM_A := Color("4fd9c0")
const TEAM_B := Color("d94f9e")

# --- strokes / radii (Doc 01 §8) ----------------------------------------
const STROKE := 1
const STROKE_STRONG := 2
const STROKE_SELECT := 3
const RADIUS_FLAT := 0
const RADIUS_PLATE := 2
const RADIUS_FRAME := 4
# Reserved space around an item so a selection frame can never touch a
# neighbour's border.
const SELECTION_GUTTER := 12.0

# --- motion grammar (Doc 01 §17), frames at 60 Hz -----------------------
const MOTION_CLICK := 6
const MOTION_ACQUIRE := 10
const MOTION_SELECT := 13
const MOTION_LOCAL := 20
const MOTION_SCREEN := 28

# --- z-layer bands (Doc 01 §22) -----------------------------------------
const LAYER_BG := 0
const LAYER_FRAME := 100
const LAYER_CONTENT := 200
const LAYER_SELECTION := 300
const LAYER_FX := 400
const LAYER_TRANSITION := 880
const LAYER_CURSOR := 1000
const LAYER_DEBUG := 1100

# --- reference frame (Doc 01 §4A / Doc 09 §1A) --------------------------
static func reference_rect(viewport_size: Vector2) -> Rect2:
    var origin := (viewport_size - DESIGN) * 0.5
    return Rect2(origin, DESIGN)

static func make_reference_frame(parent: Control) -> Control:
    # Centered 1280x720 logical frame. Pure anchors: at 16:9 it fills the
    # canvas; on expanded aspects extra space stays outside it and critical
    # UI never hugs a physical edge.
    var frame := Control.new()
    frame.name = "ReferenceFrame"
    frame.anchor_left = 0.5
    frame.anchor_right = 0.5
    frame.anchor_top = 0.5
    frame.anchor_bottom = 0.5
    frame.offset_left = -DESIGN.x * 0.5
    frame.offset_top = -DESIGN.y * 0.5
    frame.offset_right = DESIGN.x * 0.5
    frame.offset_bottom = DESIGN.y * 0.5
    frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if parent != null:
        parent.add_child(frame)
    return frame

static func make_fullbleed(parent: Control) -> Control:
    # FullBleedBackground: fills the expanded root viewport.
    var bleed := Control.new()
    bleed.name = "FullBleed"
    bleed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bleed.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if parent != null:
        parent.add_child(bleed)
    return bleed

# --- theme ---------------------------------------------------------------
static func make_theme() -> Theme:
    # Quiet neutral defaults (Doc 09 §14). Signature geometry belongs to the
    # components; generic controls must not leak rounded-card chrome.
    var t := Theme.new()
    t.default_font = font("regular")
    t.default_font_size = 20
    for type in ["Label", "Button", "OptionButton", "PopupMenu", "CheckButton"]:
        t.set_color("font_color", type, CREAM)
        t.set_color("font_hover_color", type, CREAM)
        t.set_color("font_focus_color", type, CREAM)
    for type in ["Button", "OptionButton"]:
        t.set_stylebox("normal", type, flat(Color(0, 0, 0, 0)))
        t.set_stylebox("hover", type, flat(Color(1, 1, 1, 0.05)))
        t.set_stylebox("pressed", type, flat(Color(1, 1, 1, 0.09)))
        t.set_stylebox("disabled", type, flat(Color(0, 0, 0, 0)))
        t.set_stylebox("focus", type, flat(Color(0, 0, 0, 0), ACCENT, STROKE_STRONG))
    t.set_stylebox("panel", "PopupMenu", flat(SURFACE_1))
    return t

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

# A quiet structural line/band.
static func band(color: Color, height: float) -> Panel:
    var p := Panel.new()
    p.mouse_filter = Control.MOUSE_FILTER_IGNORE
    p.size = Vector2(0.0, height)
    p.add_theme_stylebox_override("panel", flat(color))
    return p

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

# Image frame: real clipping (a border drawn over overflow is not a mask).
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
# reserved gutter. Never two coincident outlines.
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
