extends Control
# ReadyBand — Doc 04 §19 (FULL SCREEN-STATE LOCK). Not a button: the dominant
# screen state in which the match can be started.
#
# Presentation:
#   - dark wordmark plate spanning ~86% of the 1280 reference width;
#   - shallow 8 px angled END treatment (drawn, never a full-width rectangle);
#   - ONE warm underside rail (Main Menu shelf language, 2-3 px);
#   - large CREAM "READY TO FIGHT" text;
#   - one short 14-frame entrance (~0.23 s) and then STABLE — no pulsing loop.
#
# The band owns its own click/hit area as ONE mouse target and emits
# `ready_pressed`; validity, requirement text and routing stay with the screen
# (Doc 04 §19 invalid state: nothing is displayed here).
#
# CursorAnchor sits at the right end of the plate, on the action hotspot, so
# the focus hand never covers the wordmark.

const Tokens = preload("res://scripts/ui_tokens.gd")

const BAND_WIDTH_RATIO := 0.86     # within the 82-90% reference span
const BAND_HEIGHT := 64.0           # shallow transition band between roster and bays
const END_CLIP := 8.0              # shallow 6-10 px angled ends
const RAIL_H := 3.0                # one warm underside rail
const READY_TEXT_SIZE := 34        # type role SCREEN (28-34), Doc 08
const ENTRANCE_FRAMES := 14        # 1-shot entrance, then stable (60 Hz)
const ENTRANCE_RISE := 8.0

signal ready_pressed()

@onready var ready_text: Label = $ReadyText
@onready var _anchor: Control = $CursorAnchor

var _shown := false
var _entrance := 0
var _text_rest := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	ready_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ready_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ready_text.add_theme_font_override("font", Tokens.font("bold"))
	ready_text.add_theme_font_size_override("font_size", READY_TEXT_SIZE)
	ready_text.add_theme_color_override("font_color", Tokens.CREAM)
	ready_text.text = "READY TO FIGHT"
	_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()
	set_process(false)
	hide_band()

func _layout() -> void:
	var s := size
	ready_text.position = Vector2(0.0, 0.0)
	ready_text.size = s
	_text_rest = Vector2.ZERO
	# Action hotspot: right end of the plate, vertically centered.
	_anchor.place_at(Vector2(maxf(s.x - 48.0, 8.0), s.y * 0.5 - 26.0))
	queue_redraw()

# --- state ------------------------------------------------------------------

func show_band() -> void:
	if _shown:
		return
	_shown = true
	visible = true
	modulate.a = 0.0
	ready_text.position = _text_rest + Vector2(0.0, ENTRANCE_RISE)
	_entrance = ENTRANCE_FRAMES
	set_process(true)

func hide_band() -> void:
	_shown = false
	_entrance = 0
	set_process(false)
	modulate.a = 1.0
	visible = false

func is_shown() -> bool:
	return _shown

func entrance_frames() -> int:
	return ENTRANCE_FRAMES

func apply_reference_width(reference_width: float) -> void:
	size = Vector2(reference_width * BAND_WIDTH_RATIO, BAND_HEIGHT)
	_layout()

func anchor() -> Control:
	return _anchor

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		ready_pressed.emit()
		accept_event()

func _process(delta: float) -> void:
	if _entrance <= 0:
		set_process(false)
		return
	_entrance -= 1
	var t := 1.0 - float(_entrance) / float(ENTRANCE_FRAMES)
	modulate.a = clampf(t * 1.25, 0.0, 1.0)
	ready_text.position = _text_rest + Vector2(0.0, ENTRANCE_RISE * (1.0 - t))
	if _entrance <= 0:
		# Stable from here on: no continuous pulsing (Doc 04 §19).
		modulate.a = 1.0
		ready_text.position = _text_rest
		set_process(false)

# --- plate drawing -----------------------------------------------------------

func _draw() -> void:
	var w := size.x
	var h := size.y
	# Dark wordmark plate with shallow angled ends (a slanted-block plate, not
	# a plain edge-to-edge dashboard rectangle).
	var plate := PackedVector2Array([
		Vector2(END_CLIP, 0.0),
		Vector2(w - END_CLIP, 0.0),
		Vector2(w, h - RAIL_H),
		Vector2(0.0, h - RAIL_H),
	])
	draw_colored_polygon(plate, Tokens.SURFACE_1)
	# ONE warm underside rail, consistent with the Main Menu shelf edge.
	draw_rect(Rect2(Vector2(0.0, h - RAIL_H), Vector2(w, RAIL_H)), Tokens.RULE_WARM)
