extends Control
# FighterTile — Doc 04 §6 (LOCKED). Portrait-forward roster cell.
#
# Semantic layers (authored in FighterTile.tscn):
#   PortraitFrame      real-clipped masked image frame showing the portrait,
#                      cover-cropped with aspect preserved (Doc 01 §20)
#   NameBand           small lower strip, single line (Doc 04 §6.2)
#   CandidateOverlay   restrained hover/focus state: slight brightness lift +
#                      ONE global-accent lower rule. No pulsing, no double
#                      border, and never a layout-size change (Doc 04 §6.4)
#   TokenLayer         where PlayerTokenView instances are parented (Doc 04 §6.5)
#   CursorAnchor       focus-hand placement in the tile's LOWER-RIGHT region:
#                      the fingertip sits there and the drawn hand body (which
#                      extends down-right of its tip) hangs off the tile past
#                      the name's shaped box, so portrait, chip and name all
#                      stay readable — the same clearance discipline the Main
#                      rail rows are authored with (owner direction: the hand
#                      belongs lower-right on the addressed tile, never at the
#                      portrait's centre-top)
#
# Fixed tile geometry belongs to the CSS screen; this component lays its
# children out proportionally from its own size (set_tile_size / resize), with
# no per-count magic coordinates.

const Tokens = preload("res://scripts/ui_tokens.gd")
const PortraitData = preload("res://scripts/frontend/portrait_data.gd")

const PORTRAIT_INSET := 3.0        # reference inset 2-4 px (Doc 01 §20)
const NAME_BAND_RATIO := 0.22      # proportional lower strip
const NAME_BAND_MIN := 16.0
const NAME_BAND_MAX := 22.0
const ACCENT_RULE := 2.0           # ONE global-accent lower rule
const TOKEN_SIZE := 26.0           # PlayerTokenView reference (Doc 04 §13)
const TOKEN_INSET := 4.0
const TOKEN_GAP := 3.0
# --- the focus-hand pose (owner direction, supersedes the centre-top one) ----
# The fingertip lands in the tile's LOWER-RIGHT region: TIP_INSET px inside the
# tile's lower-right corner. The drawn hand body extends DOWN-RIGHT of its tip
# (and reaches HAND_REACH_LEFT px back over it), so the pose only works while
# the body can hang off the tile past the fighter's name — which is why the
# name's shaped box decides the clearance below, never a guessed margin.
const TIP_INSET := Vector2(5.0, 2.0)
# The minimum gap kept between the name's shaped box and the drawn body's own
# left reach (AnchorScript.HAND_REACH_LEFT). A wider name pushes the tip right;
# it never lets the hand settle onto the glyphs.
const HAND_CLEARANCE := 2.0
const AnchorScript = preload("res://scripts/frontend/cursor_anchor.gd")

signal tile_pressed(id: String)

@onready var backplate: Panel = $Backplate
@onready var portrait_frame: Control = $PortraitFrame
@onready var portrait_image: TextureRect = $PortraitFrame/PortraitImage
@onready var portrait_border: Panel = $PortraitFrame/PortraitBorder
@onready var candidate_overlay: Control = $CandidateOverlay
@onready var lift: ColorRect = $CandidateOverlay/Lift
@onready var accent_rule: Panel = $CandidateOverlay/AccentRule
@onready var name_band: Panel = $NameBand
@onready var fighter_name: Label = $NameBand/FighterName
@onready var _tokens: Control = $TokenLayer
@onready var _anchor: Control = $CursorAnchor

var fighter_id := ""
var _candidate := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	backplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backplate.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_1, Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_PLATE))
	portrait_frame.clip_contents = true      # real mask, not a drawn-over border
	# The tile root is the ONE pointer target (hover entry + the semantic click
	# that commits / de-selects): a child frame left on the default STOP filter
	# swallows real pointer input over the portrait area — hover entries and
	# left clicks never reached this tile's `_gui_input`, while the harness's
	# direct-call convention hid it. Every child is IGNORE, exactly like the
	# backplate/overlay/name children below.
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_border.add_theme_stylebox_override("panel", Tokens.flat(Color(0, 0, 0, 0), Tokens.RULE, Tokens.STROKE, Tokens.RADIUS_FRAME))
	candidate_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lift.color = Color(1.0, 1.0, 1.0, 0.06)
	accent_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	accent_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
	name_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_band.add_theme_stylebox_override("panel", Tokens.flat(Tokens.SURFACE_2))
	fighter_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fighter_name.clip_text = true
	fighter_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fighter_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fighter_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	fighter_name.add_theme_font_override("font", Tokens.font("semibold"))
	fighter_name.add_theme_color_override("font_color", Tokens.CREAM)
	_tokens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	candidate_overlay.hide()
	resized.connect(_layout)
	_layout()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		tile_pressed.emit(fighter_id)
		accept_event()

# --- API -------------------------------------------------------------------

func setup(id: String, name: String, portrait_tex: Texture2D = null) -> void:
	fighter_id = id
	fighter_name.text = name.to_upper()
	set_portrait(portrait_tex)
	# The name's shaped box feeds both the label's own rect and the focus-hand
	# clearance, so a new name re-runs the layout (guarded: a caller may arm the
	# component before it enters the tree, where the @onready children are not
	# resolved yet — _ready lays it out then).
	if is_node_ready():
		_layout()

func set_portrait(tex: Texture2D) -> void:
	if tex == null and fighter_id != "":
		tex = PortraitData.portrait_texture(fighter_id)
	portrait_image.texture = tex

func portrait_texture() -> Texture2D:
	return portrait_image.texture

func set_candidate(on: bool) -> void:
	if _candidate == on:
		return
	_candidate = on
	# Presentation only: lift + one accent edge. Layout bounds never change.
	candidate_overlay.visible = on

func is_candidate() -> bool:
	return _candidate

func token_layer() -> Control:
	return _tokens

func anchor() -> Control:
	return _anchor

func name_band_rect() -> Rect2:
	return Rect2(name_band.position, name_band.size)

func portrait_area() -> Rect2:
	return Rect2(portrait_frame.position, portrait_frame.size)

func set_tile_size(new_size: Vector2, minimum := Vector2.ZERO) -> void:
	# The optional floor encodes the owning surface's rule: Character Select's
	# roster tile is the fixed 108x82 reference and NEVER shrinks with roster
	# growth (Doc 01 §8 / Doc 04 §10), while surfaces with their own tighter
	# grid (How to Play's roster strip, Story Briefing) keep their authored
	# size by passing no floor. The render/layout floor of 24 px remains.
	var target := Vector2(maxf(new_size.x, minimum.x), maxf(new_size.y, minimum.y))
	size = Vector2(maxf(target.x, 24.0), maxf(target.y, 24.0))
	_layout()

# --- layout (proportional, from the component's own size) ------------------

func _layout() -> void:
	var s := size
	backplate.position = Vector2.ZERO
	backplate.size = s
	var band := clampf(roundf(s.y * NAME_BAND_RATIO), NAME_BAND_MIN, NAME_BAND_MAX)
	var portrait := Rect2(
		Vector2(PORTRAIT_INSET, PORTRAIT_INSET),
		Vector2(maxf(s.x - PORTRAIT_INSET * 2.0, 8.0), maxf(s.y - band - 2.0 - PORTRAIT_INSET, 8.0)))
	portrait_frame.position = portrait.position
	portrait_frame.size = portrait.size
	portrait_image.position = Vector2.ZERO
	portrait_image.size = portrait.size
	portrait_border.position = Vector2.ZERO
	portrait_border.size = portrait.size
	lift.position = portrait.position
	lift.size = portrait.size
	accent_rule.position = Vector2(0.0, s.y - ACCENT_RULE)
	accent_rule.size = Vector2(s.x, ACCENT_RULE)
	name_band.position = Vector2(0.0, s.y - band)
	name_band.size = Vector2(s.x, band)
	fighter_name.add_theme_font_size_override("font_size", clampi(int(roundf(s.y * 0.155)), 10, 15))
	# The label's OWN rect IS the shaped name, centred in the band: the
	# measurable version of what the player reads. A band-wide label rect is a
	# measurement artefact (the same resolution the READY band's wordmark
	# carries), and the focus-hand pose below is authored against this box.
	# CENTER alignment is kept and the box is centred, so the glyphs land on
	# exactly the pixels they landed on before.
	var name_w: float = _name_box(band).x
	fighter_name.size = Vector2(name_w, band)
	fighter_name.position = Vector2((s.x - name_w) * 0.5, 0.0)
	_tokens.position = portrait.position
	_tokens.size = portrait.size
	_layout_anchor(s, band)

func _name_box(band: float) -> Vector2:
	# The fighter name's shaped box: the text's own advance at the size the
	# label draws it (clamped to the tile's inner width, where clip_text +
	# ellipsis own a name too long for its tile — as before).
	var font := fighter_name.get_theme_font("font")
	var fs: int = fighter_name.get_theme_font_size("font_size")
	var shaped: float = font.get_string_size(str(fighter_name.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	return Vector2(clampf(shaped, 1.0, maxf(size.x - 8.0, 8.0)), band)

func _layout_anchor(s: Vector2, band: float) -> void:
	# Focus hand: the fingertip lands in the tile's LOWER-RIGHT region (owner
	# direction) while the drawn body — which draws DOWN-RIGHT of the tip and
	# reaches HAND_REACH_LEFT px back over it — stays clear of the fighter's
	# name, exactly like the Main rail rows keep their body off the label.
	# The tip takes the authored inset from the tile's lower-right corner and is
	# pushed right only when the name's shaped box would otherwise reach into
	# the body's own left reach: a longer name (or another font) moves the tip,
	# it never puts the drawn hand on the glyphs.
	var glyph_right: float = (s.x + _name_box(band).x) * 0.5
	var tip := Vector2(s.x - TIP_INSET.x, s.y - TIP_INSET.y)
	tip.x = clampf(maxf(tip.x, glyph_right + AnchorScript.HAND_REACH_LEFT + HAND_CLEARANCE),
		s.x * 0.5, maxf(s.x - 1.0, 0.0))
	tip.y = clampf(tip.y, s.y * 0.5, maxf(s.y - 1.0, 0.0))
	_anchor.place_at(tip)

# --- token placement helpers (never over the name band) --------------------

func token_slots(count: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if count <= 0:
		return out
	var area := portrait_area()
	var step := TOKEN_SIZE + TOKEN_GAP
	var per_row := int(maxf(1.0, floorf((area.size.x - TOKEN_INSET * 2.0 + TOKEN_GAP) / step)))
	for i in count:
		var row := i / per_row
		var col := i % per_row
		var pos := Vector2(
			area.position.x + TOKEN_INSET + col * step,
			area.end.y - TOKEN_INSET - TOKEN_SIZE - row * step)
		out.append(Rect2(pos, Vector2(TOKEN_SIZE, TOKEN_SIZE)))
	return out

func place_token_view(token: Control, index: int, count: int) -> void:
	var slots := token_slots(count)
	if index < 0 or index >= slots.size():
		return
	token.position = slots[index].position
