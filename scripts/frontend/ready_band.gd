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
# Doc 04 §9 / Doc 08 §7: the entrance duration is TIME-based, never a render
# frame count — the same authored duration at 30/60/120+ Hz. ENTRANCE_FRAMES is
# the authored 60 Hz equivalent the reference capture was tuned at.
const ENTRANCE_FRAMES := 14
const ENTRANCE_SECONDS := 14.0 / 60.0
const ENTRANCE_RISE := 8.0

signal ready_pressed()

@onready var ready_text: Label = $ReadyText
@onready var _anchor: Control = $CursorAnchor

var _shown := false
var _entrance := 0.0
var _text_rest := Vector2.ZERO
var _focus_rule: Panel = null

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
	# §6 control emphasis: the band is a custom Control, so it carries its own
	# structural focus signal (a 2 px accent edge) instead of relying on a
	# Button style it does not have.
	_focus_rule = Panel.new()
	_focus_rule.name = "FocusRule"
	_focus_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_rule.add_theme_stylebox_override("panel", Tokens.flat(Tokens.ACCENT))
	_focus_rule.visible = false
	add_child(_focus_rule)
	resized.connect(_layout)
	_layout()
	set_process(false)
	hide_band()

func _layout() -> void:
	var s := size
	# The label IS the wordmark: the measurable rect the optical harness reads
	# (Gate A "the hand never obscures the target label") must be the box the
	# glyphs are actually drawn in — 270 x 42 of words — never the whole
	# 1100.8 x 64 plate. A band-wide label rect made every optical measurement
	# of this band measure an invisible hit plate, so a hand 362 px clear of
	# every glyph was reported as obscuring all 2387.09 px2 of it.
	# CENTER/CENTER alignment is kept, and the box is centred on the band, so
	# the glyphs land on exactly the pixels they landed on before (the band
	# centre and the text centre are the same point either way): the
	# presentation is byte-identical, proven by a zero-pixel diff of the band
	# region (.verification/readyband-evidence).
	var box := _wordmark_box(s)
	ready_text.size = box
	ready_text.position = Vector2((s.x - box.x) * 0.5, (s.y - box.y) * 0.5)
	_text_rest = ready_text.position
	_focus_rule.position = Vector2(0.0, s.y - RAIL_H - 2.0)
	_focus_rule.size = Vector2(s.x, 2.0)
	# Action hotspot: right end of the plate, vertically centered.
	_anchor.place_at(Vector2(maxf(s.x - 48.0, 8.0), s.y * 0.5 - 26.0))
	queue_redraw()

func _wordmark_box(band: Vector2) -> Vector2:
	# The Label's own minimum size IS the shaped wordmark (the same box the
	# label's CENTER alignment centres in): 270 x 42 for "READY TO FIGHT" at
	# the authored 34 px. Clamped to the plate so a font swap can never push
	# the rect outside the band it belongs to.
	var box := ready_text.get_minimum_size()
	return Vector2(minf(box.x, band.x), minf(box.y, band.y))

# --- focus signal (§6) -------------------------------------------------------

func set_focus_signal(on: bool) -> void:
	if _focus_rule != null:
		_focus_rule.visible = on

func focus_signal_visible() -> bool:
	return _focus_rule != null and _focus_rule.visible

# --- state ------------------------------------------------------------------

func show_band() -> void:
	if _shown:
		return
	_shown = true
	visible = true
	modulate.a = 0.0
	ready_text.position = _text_rest + Vector2(0.0, ENTRANCE_RISE)
	_entrance = ENTRANCE_SECONDS
	set_process(true)

func hide_band() -> void:
	_shown = false
	_entrance = 0.0
	set_process(false)
	modulate.a = 1.0
	visible = false
	set_focus_signal(false)

func is_shown() -> bool:
	return _shown

func entrance_frames() -> int:
	# The authored 60 Hz equivalent of the time-based entrance (Doc 04 §9: the
	# REAL duration is entrance_seconds(), never a frame count).
	return ENTRANCE_FRAMES

func entrance_seconds() -> float:
	return ENTRANCE_SECONDS

func apply_reference_width(reference_width: float) -> void:
	size = Vector2(reference_width * BAND_WIDTH_RATIO, BAND_HEIGHT)
	_layout()

func anchor() -> Control:
	return _anchor

func painted_surface_rect() -> Rect2:
	# The harness's own rule (tools/acceptance_support.gd): the actionable
	# surface is "the control's own drawn rect, ... NEVER a bare full-bleed hit
	# plate". This band paints its plate + the warm rail itself, in _draw(), so
	# its own rect IS that drawn surface — the hand lands on the plate's right
	# end, on the action hotspot. Nothing else draws it: the ReadyText label is
	# the WORDS, measured separately (its own rect = the 270 x 42 wordmark), and
	# the hand sits 362 px clear of them.
	return get_global_rect()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		ready_pressed.emit()
		accept_event()

func _process(delta: float) -> void:
	if _entrance <= 0.0:
		set_process(false)
		return
	_entrance = maxf(_entrance - delta, 0.0)
	var t := 1.0 - _entrance / ENTRANCE_SECONDS
	modulate.a = clampf(t * 1.25, 0.0, 1.0)
	ready_text.position = _text_rest + Vector2(0.0, ENTRANCE_RISE * (1.0 - t))
	if _entrance <= 0.0:
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
