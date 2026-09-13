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
#   CursorAnchor       focus-hand placement near the portrait, below the tile's
#                      lower-left corner, so artwork/name stay uncovered
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

func set_tile_size(new_size: Vector2) -> void:
	size = Vector2(maxf(new_size.x, 24.0), maxf(new_size.y, 24.0))
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
	fighter_name.position = Vector2(4.0, 0.0)
	fighter_name.size = Vector2(maxf(s.x - 8.0, 8.0), band)
	fighter_name.add_theme_font_size_override("font_size", clampi(int(roundf(s.y * 0.155)), 10, 15))
	_tokens.position = portrait.position
	_tokens.size = portrait.size
	# Focus hand settles below the tile's lower-left corner: the hand sprite
	# extends right/down from the anchor, so artwork and name stay uncovered.
	_anchor.place_at(Vector2(6.0, s.y + 4.0))

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
