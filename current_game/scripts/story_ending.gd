extends Control
# Final Story clear (Mike 2026-09-30): the victory screen holds "STORY COMPLETE?",
# then a slow fade to black and the credits roll. Fades and a steady scroll only,
# no flashing. Enter / click skips to the end.
signal finished

const Credits = preload("res://scripts/story_credits.gd")
const HOLD := 4.0          # victory pose + "STORY COMPLETE?" before the fade
const FADE := 1.6
const SCROLL_SPEED := 62.0 # px per second
const LINE := 74.0

var black: ColorRect
var roll: Control
var _motion: Tween
var _scrolling := false
var _roll_height := 0.0

func _ready() -> void:
	name = "StoryEnding"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = preload("res://scripts/demo_style.gd").make()
	black = ColorRect.new()
	black.name = "FadeToBlack"
	black.color = Color(0, 0, 0, 1)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	roll = Control.new()
	roll.name = "CreditsRoll"
	roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(roll)
	set_process(false)
	hide()

func _line(text: String, y: float, size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(140, y)
	l.size = Vector2(1000, LINE)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	roll.add_child(l)

func _build_roll() -> void:
	for c in roll.get_children(): c.queue_free()
	var y := 0.0
	_line(Credits.HEADING, y, 64, Color("f2d27a")); y += LINE * 2.0
	for n in Credits.NAMES:
		_line(n, y, 40, Color("e8eef2")); y += LINE
	y += LINE
	_line(Credits.CLOSING, y, 30, Color("b2c5cd")); y += LINE
	_roll_height = y

func play() -> void:
	_build_roll()
	roll.position = Vector2(0, 720)
	roll.modulate.a = 1.0
	black.modulate.a = 0.0
	_scrolling = false
	show()
	if _motion and _motion.is_valid(): _motion.kill()
	_motion = create_tween()
	_motion.tween_interval(HOLD)
	_motion.tween_property(black, "modulate:a", 1.0, FADE)
	_motion.tween_callback(func():
		_scrolling = true
		set_process(true))

func is_rolling() -> bool:
	return visible and _scrolling

func _process(delta: float) -> void:
	if not _scrolling: return
	roll.position.y -= SCROLL_SPEED * delta
	# Stop with the closing line resting near the middle, then hand back.
	if roll.position.y <= 330.0 - _roll_height + LINE:
		_scrolling = false
		set_process(false)
		if _motion and _motion.is_valid(): _motion.kill()
		_motion = create_tween()
		_motion.tween_interval(2.0)
		_motion.tween_property(roll, "modulate:a", 0.0, 1.0)
		_motion.tween_callback(_end)

func skip() -> void:
	if not visible: return
	if _motion and _motion.is_valid(): _motion.kill()
	_end()

func _end() -> void:
	_scrolling = false
	set_process(false)
	hide()
	finished.emit()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		skip()
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_accept"):
		skip()
		get_viewport().set_input_as_handled()
